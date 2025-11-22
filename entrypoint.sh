#!/bin/bash
set -e

WALLETS=(
    "0xd32adD1c7d37FE9789e630D640D74DB94aOc3Db2"
    # "0xAnotherWalletAddress..."
)

NODE_IDS=(
    "37356067"
    "37385539"
    "37356068"
    "37308044"
    "37308046"
    "37308047"
    "37308051"
    "37308056"
    "37308076"
    "37308119"
    "37337426"
    "37337427"
    "37337432"
    "37337434"
    "37337436"
    "37337449"
    "37337456"
    "37337467"
    "37337507"
    "37337509"
    "37356024"
    "37356028"
    "37356029"
    "37356033"
    "37356034"
    "37356069"
    "37385497"
    "37385505"
    "37385507"
    "37385516"
    "37385534"
    "37385540"
    "37385570"
    "37385572"
    "37385573"
    "37415179"
    "37415181"
    "37415182"
    "37415193"
    "37415203"
    "37443569"
    "37443577"
    "37443579"
    "37443580"
    "37443584"
    "37443644"
)

echo "🎲 Initializing Random Selection..."

if [ ${#WALLETS[@]} -gt 0 ]; then
    RANDOM_WALLET_INDEX=$(( RANDOM % ${#WALLETS[@]} ))
    CURRENT_WALLET=${WALLETS[$RANDOM_WALLET_INDEX]}
    echo "💰 Selected Wallet: $CURRENT_WALLET"
else
    echo "❌ Error: No wallets defined in WALLETS array."
    exit 1
fi

if [ ${#NODE_IDS[@]} -gt 0 ]; then
    RANDOM_NODE_INDEX=$(( RANDOM % ${#NODE_IDS[@]} ))
    CURRENT_NODE_ID=${NODE_IDS[$RANDOM_NODE_INDEX]}
    echo "🆔 Selected Node ID: $CURRENT_NODE_ID"
else
    echo "⚠️ No pre-defined Node IDs found. A new one will be generated."
    CURRENT_NODE_ID=""
fi

mkdir -p $HOME/.nexus

echo "👤 Ensuring user is registered..."
nexus-cli register-user --wallet-address "$CURRENT_WALLET" > /dev/null 2>&1 || true

# 5. Configure Node Identity
if [ -n "$CURRENT_NODE_ID" ]; then
    echo "⚙️  Writing config for Node ID: $CURRENT_NODE_ID"
    cat <<EOF > $HOME/.nexus/config.json
{
  "user_id": "generated-by-entrypoint",
  "wallet_address": "$CURRENT_WALLET",
  "node_id": "$CURRENT_NODE_ID",
  "environment": "production"
}
EOF
else
    echo "jg️ Registering NEW random Node ID..."
    nexus-cli register-node
fi

echo "⛏️ Starting Prover..."
exec nexus-cli start --headless --max-difficulty large
