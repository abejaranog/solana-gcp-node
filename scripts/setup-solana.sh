#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/solana-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Solana GCP Node Setup - $(date) ==="

# === 1. KERNEL TUNING (Critical for Solana) ===
echo "--- [1/7] Applying Kernel Tuning ---"

cat <<EOF | sudo tee /etc/sysctl.d/99-solana.conf
# UDP Buffer sizes (128MB) - Required for gossip protocol
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=134217728
net.core.wmem_default=134217728

# Memory maps for ledger
vm.max_map_count=1000000

# Network optimizations
net.core.netdev_max_backlog=50000
net.ipv4.tcp_max_syn_backlog=30000
net.ipv4.tcp_tw_reuse=1
EOF
sudo sysctl --system

# File descriptor limits
cat <<EOF | sudo tee /etc/security/limits.d/99-solana.conf
* soft nofile 1000000
* hard nofile 1000000
EOF

# Apply limits to current session
ulimit -n 1000000 || true

echo "[OK] Kernel tuning applied"

# === 2. SYSTEM DEPENDENCIES ===
echo "--- [2/7] Installing system dependencies ---"

sudo apt-get update
sudo apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libudev-dev \
    clang \
    cmake \
    jq \
    fio \
    linux-tools-common \
    linux-tools-generic \
    curl \
    git

echo "[OK] Dependencies installed"

# === 3. RUST ===
echo "--- [3/7] Instalando Rust ---"

sudo -u ubuntu bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
sudo -u ubuntu bash -c 'source $HOME/.cargo/env && rustup component add rustfmt clippy'

# Add Rust to global PATH
cat <<'RUSTEOF' | sudo tee -a /etc/bash.bashrc
# Rust environment
export PATH="/home/ubuntu/.cargo/bin:$PATH"
RUSTEOF

echo "[OK] Rust installed"

# === 4. SOLANA CLI ===
echo "--- [4/7] Instalando Solana CLI ---"

sudo -u ubuntu bash -c 'sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"'

# Add Solana to global PATH (for all users)
cat <<'SOLEOF' | sudo tee -a /etc/bash.bashrc
# Solana CLI
export PATH="/home/ubuntu/.local/share/solana/install/active_release/bin:$PATH"
SOLEOF

# Also add to ubuntu user's .bashrc for immediate use
echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' | sudo -u ubuntu tee -a /home/ubuntu/.bashrc

echo "[OK] Solana CLI installed"

# === 5. NODE.JS + YARN ===
echo "--- [5/7] Instalando Node.js y Yarn ---"

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install --global yarn

echo "[OK] Node.js and Yarn installed"

# === 6. ANCHOR FRAMEWORK ===
echo "--- [6/7] Instalando Anchor Framework ---"

sudo -u ubuntu bash -c 'source $HOME/.cargo/env && cargo install --git https://github.com/coral-xyz/anchor avm --locked --force'
sudo -u ubuntu bash -c 'source $HOME/.cargo/env && avm install latest && avm use latest'

# Add Anchor/AVM to global PATH
cat <<'ANCHOREOF' | sudo tee -a /etc/bash.bashrc
# Anchor Framework
export PATH="/home/ubuntu/.avm/bin:$PATH"
ANCHOREOF

echo "[OK] Anchor installed"

# === 7. SMOKE TEST SCRIPT ===
echo "--- [7/7] Configuring Smoke Test ---"

cat <<'EOF' > /home/ubuntu/run-smoke-test.sh
#!/bin/bash
set -e

export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
source "$HOME/.cargo/env"

echo "=========================================="
echo "   SOLANA NODE SMOKE TEST"
echo "=========================================="

echo ""
echo "[1/5] Verificando instalaciones..."
echo -n "  Rust: " && rustc --version
echo -n "  Solana: " && solana --version
echo -n "  Anchor: " && anchor --version
echo -n "  Node: " && node --version

echo ""
echo "[2/5] Verificando kernel tuning..."
RMEM=$(sysctl -n net.core.rmem_max)
if [[ $RMEM -ge 134217728 ]]; then
    echo "  [OK] UDP buffers: $RMEM bytes"
else
    echo "  [ERROR] UDP buffers: $RMEM bytes (TOO LOW)"
    exit 1
fi

echo ""
echo "[3/5] Iniciando test-validator..."
solana-test-validator --ledger /tmp/smoke-test-ledger --quiet &
VALIDATOR_PID=$!

# Esperar a que el validador esté listo (máx 30s)
for i in {1..30}; do
    if solana cluster-version 2>/dev/null; then
        echo "  [OK] Validator responding on attempt $i"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "  [ERROR] Validator did not respond in 30s"
        kill $VALIDATOR_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

echo ""
echo "[4/5] Probando airdrop..."
solana config set --url localhost
KEYPAIR=$(solana-keygen new --no-bip39-passphrase --force -o /tmp/smoke-test-keypair.json 2>&1 | grep -oP 'pubkey: \K.*' || cat /tmp/smoke-test-keypair.json | jq -r '.[]' | head -1)
solana airdrop 5 --keypair /tmp/smoke-test-keypair.json 2>/dev/null && echo "  [OK] Airdrop successful"

echo ""
echo "[5/5] Limpiando..."
kill $VALIDATOR_PID 2>/dev/null || true
rm -rf /tmp/smoke-test-ledger /tmp/smoke-test-keypair.json

echo ""
echo "=========================================="
echo "   [PASSED] SMOKE TEST PASSED"
echo "=========================================="
echo ""
echo "Your Solana node is ready for development."
echo "Run: solana-test-validator"
EOF

chmod +x /home/ubuntu/run-smoke-test.sh
chown ubuntu:ubuntu /home/ubuntu/run-smoke-test.sh

# === FINALIZATION ===
echo ""
echo "========================================"
echo "   SETUP COMPLETE - $(date)"
echo "========================================"
echo ""
echo "Run 'run-smoke-test.sh' to verify installation."
echo "Full log at: $LOG_FILE"