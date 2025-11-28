#!/bin/bash
set -e

# Configuration
# Set this to your Heroku Manager App URL via Config Vars
MANAGER_URL="$MANAGER_URL"

if [ -z "$MANAGER_URL" ]; then
    echo "❌ Error: MANAGER_URL not set."
    exit 1
fi

# Identify the worker, persisting the ID across restarts
CONFIG_DIR="$HOME/.nexus_worker"
CONFIG_FILE="$CONFIG_DIR/worker.conf"
LOG_FILE="$CONFIG_DIR/prover.log"
mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # Source the file to get WORKER_ID
    source "$CONFIG_FILE"
    echo "✅ Found existing Worker ID: $WORKER_ID"
else
    # Generate a new UUID for the worker and save it
    WORKER_ID=$(cat /proc/sys/kernel/random/uuid)
    echo "WORKER_ID=$WORKER_ID" > "$CONFIG_FILE"
    echo "✨ Generated new Worker ID: $WORKER_ID"
fi

# 1. Ask Manager for an assignment (Node ID and Wallet)
echo "📞 Requesting assignment from manager..."
RESPONSE=$(curl -s -X POST "$MANAGER_URL/assign" \
    -H "Content-Type: application/json" \
    -d "{\"worker_id\": \"$WORKER_ID\"}")

if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to contact manager at '$MANAGER_URL'. Is it running and accessible?"
    exit 1
fi

# Parse Node ID and Wallet from the JSON response
NODE_ID=$(echo "$RESPONSE" | grep -o '"node_id"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)
WALLET=$(echo "$RESPONSE" | grep -o '"wallet"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)

if [ -z "$NODE_ID" ] || [ "$NODE_ID" == "null" ] || [ -z "$WALLET" ] || [ "$WALLET" == "null" ]; then
    echo "❌ Failed to get assignment from manager. Response: $RESPONSE"
    exit 1
fi

echo "✅ Assigned Node ID: $NODE_ID"
echo "💰 Assigned Wallet: $WALLET"

# 5. Main Loop (Mining & Heartbeat)
while true; do
    # 3. Create config.json with the assigned Node ID and Wallet
    echo "📝 Creating Nexus config file..."
    mkdir -p "$HOME/.nexus"
    cat > "$HOME/.nexus/config.json" << EOL
{
  "user_id": "generated-by-entrypoint",
  "node_id": "$NODE_ID",
  "wallet_address": "$WALLET",
  "environment": "production"
}
EOL

    # 4. Start Proving
    echo "⛏️ Starting Prover on Node: $NODE_ID (Wallet: $WALLET)..."
    touch "$LOG_FILE" # Ensure log file exists for tail
    
    # Start tail if not already running
    if ! kill -0 $TAIL_PID 2>/dev/null; then
        tail -f "$LOG_FILE" &
        TAIL_PID=$!
    fi

    nexus-cli start --headless --max-difficulty large >> "$LOG_FILE" 2>&1 &
    PROVER_PID=$!

    # Give it a moment to start up or fail
    sleep 3

    # Check if the prover process is still alive
    if ! kill -0 $PROVER_PID >/dev/null 2>&1; then
        echo "❌ Error: The nexus-cli prover failed to start. See logs above for details."
        # If it fails immediately, wait a bit before retrying to avoid tight loop
        sleep 10
        continue 
    fi

    # 5. Heartbeat Loop
    echo "💓 Heartbeat service active..."
    TASKS_COMPLETED=0
    REBALANCE_NEEDED=false

    while kill -0 $PROVER_PID >/dev/null 2>&1; do
        # Count tasks
        CURRENT_TASKS=$(grep -c "Proof submitted" "$LOG_FILE" || true)
        
        if [ "$CURRENT_TASKS" -ne "$TASKS_COMPLETED" ]; then
            echo "📈 Tasks: $CURRENT_TASKS"
            TASKS_COMPLETED=$CURRENT_TASKS
        fi

        # Send Heartbeat
        HEARTBEAT_RESPONSE=$(curl -s -X POST "$MANAGER_URL/heartbeat" \
            -H "Content-Type: application/json" \
            -d "{\"worker_id\": \"$WORKER_ID\", \"node_id\": \"$NODE_ID\", \"wallet\": \"$WALLET\", \"tasks\": $TASKS_COMPLETED}")

        STATUS=$(echo "$HEARTBEAT_RESPONSE" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)
        COMMAND=$(echo "$HEARTBEAT_RESPONSE" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)
        
        # Check for Rebalance
        if [ "$STATUS" == "rebalance" ]; then
            NEW_NODE_ID=$(echo "$HEARTBEAT_RESPONSE" | grep -o '"new_node_id"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)
            NEW_WALLET=$(echo "$HEARTBEAT_RESPONSE" | grep -o '"new_wallet"[[:space:]]*:[[:space:]]*"[^"]*' | cut -d'"' -f4)
            
            if [ -n "$NEW_NODE_ID" ] && [ -n "$NEW_WALLET" ]; then
                echo "⚖️ Rebalancing requested! Switching to Node: $NEW_NODE_ID"
                NODE_ID="$NEW_NODE_ID"
                WALLET="$NEW_WALLET"
                REBALANCE_NEEDED=true
                break # Break inner heartbeat loop to restart miner
            fi
        fi

        if [ "$STATUS" == "re-register" ]; then
            echo "⚠️ Manager requested re-registration. Exiting to restart."
            exit 1 # Let the container restart or handle outer loop if we wanted full re-reg
        fi

        if [ "$STATUS" == "command" ]; then
            echo "🔔 Received command: $COMMAND"
            if [ "$COMMAND" == "restart" ]; then
                echo "🔄 Restarting worker..."
                REBALANCE_NEEDED=true # Reuse rebalance logic to just restart
                break 
            elif [ "$COMMAND" == "stop" ]; then
                echo "🛑 Stopping worker..."
                kill $PROVER_PID 2>/dev/null
                exit 0 
            fi
        fi

        sleep 30
    done
    
    # Cleanup old prover if it's still running (e.g. we broke loop for rebalance)
    if kill -0 $PROVER_PID >/dev/null 2>&1; then
        echo "🛑 Stopping current prover process..."
        kill $PROVER_PID 2>/dev/null
        wait $PROVER_PID 2>/dev/null || true
    fi

    if [ "$REBALANCE_NEEDED" = true ]; then
        echo "🔄 Reconfiguring and restarting miner..."
        continue # Continue outer loop with new NODE_ID/WALLET
    else
        echo "⚠️ Prover process exited unexpectedly. Restarting in 5s..."
        sleep 5
    fi
done

echo "Prover process has ended. Exiting."
