#!/bin/bash
set -e

# 1. Validation
if [ -z "$WALLET_ADDRESS" ]; then
    echo "Error: WALLET_ADDRESS environment variable is not set."
    echo "Please set it in Heroku Config Vars."
    exit 1
fi

echo "🚀 Starting Nexus Worker on Heroku..."
echo "💰 Wallet: $WALLET_ADDRESS"

mkdir -p $HOME/.nexus

echo "👤 Ensuring user is registered..."
nexus-cli register-user --wallet-address "$WALLET_ADDRESS" || true

# 4. Register a NEW Node ID
echo "jg️ Registering new Node ID for this session..."
nexus-cli register-node

# 5. Display the generated ID (For logs)
if [ -f "$HOME/.nexus/config.json" ]; then
    NODE_ID=$(grep "node_id" $HOME/.nexus/config.json | cut -d '"' -f 4)
    echo "✅ Assigned Node ID: $NODE_ID"
else
    echo "⚠️ Warning: Config file not found, registration might have failed."
fi

# 6. Start Proving
echo "⛏️ Starting Prover..."
exec nexus-cli start --headless --max-difficulty large
