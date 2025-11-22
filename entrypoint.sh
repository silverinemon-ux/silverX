#!/bin/bash
set -e

WALLETS=(
    "0xd32adD1c7d37FE9789e630D640D74DB94a0c3Db2" # Wallet 1 (Nodes 1-90)
    # "0xSECOND_WALLET_ADDRESS_HERE"               # Wallet 2 (Nodes 91-180)
    # "0xTHIRD_WALLET_ADDRESS_HERE"                # Wallet 3 (Nodes 181-270)
)

if [ -z "$DYNO" ]; then
    echo "⚠️ Not running on Heroku (DYNO var missing). Defaulting to ID 1."
    DYNO_NUM=1
else
    # Extract the number after the dot
    DYNO_NUM=$(echo "$DYNO" | cut -d '.' -f 2)
fi

echo "🤖 Dyno ID: $DYNO_NUM"

NODES_PER_WALLET=90
WALLET_INDEX=$(( (DYNO_NUM - 1) / NODES_PER_WALLET ))

NUM_WALLETS=${#WALLETS[@]}
SELECTED_INDEX=$(( WALLET_INDEX % NUM_WALLETS ))
CURRENT_WALLET=${WALLETS[$SELECTED_INDEX]}

echo "🧮 Shard Calculation: Group $WALLET_INDEX (assigned to Wallet Index $SELECTED_INDEX)"
echo "💰 Active Wallet: $CURRENT_WALLET"

mkdir -p $HOME/.nexus

echo "👤 Ensuring user is registered..."
nexus-cli register-user --wallet-address "$CURRENT_WALLET" || true

echo "jg️ Registering new Node ID for this session..."
nexus-cli register-node

if [ -f "$HOME/.nexus/config.json" ]; then
    NODE_ID=$(grep "node_id" $HOME/.nexus/config.json | cut -d '"' -f 4)
    echo "✅ Assigned Node ID: $NODE_ID"
else
    echo "⚠️ Warning: Config file not found, registration might have failed."
fi

echo "⛏️ Starting Prover..."
exec nexus-cli start --headless --max-difficulty large
