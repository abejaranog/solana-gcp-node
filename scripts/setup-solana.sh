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
echo "--- [3/7] Installing Rust ---"

# Install Rust globally in /opt/rust
mkdir -p /opt/rust
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable

# Set default toolchain and add components
export PATH="/opt/rust/cargo/bin:$PATH"
rustup default stable
rustup component add rustfmt clippy

# Set permissions for all users
chmod -R 755 /opt/rust

echo "[OK] Rust installed in /opt/rust"

# === 4. SOLANA CLI ===
echo "--- [4/7] Installing Solana CLI ---"

# Download and extract Solana directly to /opt/solana
mkdir -p /opt/solana/bin
SOLANA_VERSION="stable"
curl -sSfL "https://release.anza.xyz/${SOLANA_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2" | tar -xjf - -C /opt/solana --strip-components=1

# Set permissions for all users
chmod -R 755 /opt/solana

echo "[OK] Solana CLI installed in /opt/solana"

# === 5. NODE.JS + YARN ===
echo "--- [5/7] Instalando Node.js y Yarn ---"

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install --global yarn

echo "[OK] Node.js and Yarn installed"

# === 6. ANCHOR FRAMEWORK ===
echo "--- [6/7] Installing Anchor Framework ---"

# Install Anchor using the global Cargo with AVM_HOME in /opt
export PATH="/opt/solana/bin:/opt/rust/cargo/bin:$PATH"
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export AVM_HOME=/opt/avm

# Create /opt/avm directory
mkdir -p /opt/avm

# Install anchor-cli using cargo install (robust and reliable)
echo "Installing anchor-cli using cargo install..."

# Install anchor-cli directly in /opt/avm using cargo install --root
cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked --force --root /opt/avm

# Set permissions for /opt/avm
chmod -R 755 /opt/avm

# Verify anchor binary exists
if [ ! -f "/opt/avm/bin/anchor" ]; then
    echo "  [ERROR] Could not find anchor binary in /opt/avm/bin"
    ls -la /opt/avm/bin/ || echo "  /opt/avm/bin/ is empty"
    exit 1
fi

# Remove the symlink in /opt/rust/cargo/bin if it exists
if [ -L "/opt/rust/cargo/bin/anchor" ]; then
    rm /opt/rust/cargo/bin/anchor
fi

# Create a symlink in /opt/rust/cargo/bin for convenience
ln -sf /opt/avm/bin/anchor /opt/rust/cargo/bin/anchor

echo "[OK] Anchor installed and accessible in /opt/avm/bin"

# Set permissions for all Rust/Cargo binaries
chmod -R 755 /opt/rust/cargo/bin

# Make /home/ubuntu accessible for OS Login users to run smoke test
chmod 755 /home/ubuntu

# === GLOBAL PATH CONFIGURATION ===
# Add /opt directories to global PATH for all users
# Binaries stay in /opt with all their dependencies

echo "Configuring global PATH for all users..."

# Update /etc/environment (loaded by PAM for all users including SSH)
# This is the ONLY reliable way to set PATH for OS Login users
cat > /etc/environment << 'ENVFILE'
PATH="/opt/solana/bin:/opt/rust/cargo/bin:/opt/avm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
RUSTUP_HOME="/opt/rust/rustup"
CARGO_HOME="/opt/rust/cargo"
ENVFILE

# Also add to /etc/profile.d for login shells (belt and suspenders)
cat > /etc/profile.d/solana-dev.sh << 'PROFILEENV'
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export PATH="/opt/solana/bin:/opt/rust/cargo/bin:/opt/avm/bin:$PATH"
PROFILEENV
chmod +x /etc/profile.d/solana-dev.sh

# Add to /etc/bash.bashrc for non-login interactive shells
cat >> /etc/bash.bashrc << 'BASHENV'

# Solana development environment
export RUSTUP_HOME=/opt/rust/rustup
export CARGO_HOME=/opt/rust/cargo
export PATH="/opt/solana/bin:/opt/rust/cargo/bin:/opt/avm/bin:$PATH"
BASHENV

echo "[OK] Global PATH configured in:"
echo "    - /etc/environment (PAM/all users)"
echo "    - /etc/profile.d (login shells)"
echo "    - /etc/bash.bashrc (interactive shells)"

# === 7. SMOKE TEST SCRIPT ===
echo "--- [7/7] Configuring Smoke Test ---"

cat <<'EOF' > /home/ubuntu/run-smoke-test.sh
#!/bin/bash
set -e

# Load global environment
export AVM_HOME=/opt/avm
source /etc/profile.d/solana-dev.sh 2>/dev/null || true

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

# === 8. VALIDATION TEST ===
echo "--- [8/8] Validating installation for all users ---"

# Test that binaries work for non-root user (ubuntu)
echo "Testing binaries as non-root user..."

# Create a test user to simulate OS Login (fresh user with no custom config)
echo "Creating test user to simulate OS Login..."
useradd -m -s /bin/bash oslogin_test_user 2>/dev/null || true

# Test 1: Direct binary execution (no PATH needed)
echo "Test 1: Direct binary execution..."
if /opt/solana/bin/solana --version >/dev/null 2>&1; then
    echo "  [OK] /opt/solana/bin/solana executable"
else
    echo "  [ERROR] /opt/solana/bin/solana NOT executable"
    ls -la /opt/solana/bin/solana
    exit 1
fi

if /opt/rust/cargo/bin/cargo --version >/dev/null 2>&1; then
    echo "  [OK] /opt/rust/cargo/bin/cargo executable"
else
    echo "  [ERROR] /opt/rust/cargo/bin/cargo NOT executable"
    ls -la /opt/rust/cargo/bin/cargo
    exit 1
fi

if /opt/rust/cargo/bin/anchor --version >/dev/null 2>&1; then
    echo "  [OK] /opt/rust/cargo/bin/anchor executable"
else
    echo "  [ERROR] /opt/rust/cargo/bin/anchor NOT executable"
    echo "  DEBUG: Listing /opt/rust/cargo/bin/anchor:"
    ls -la /opt/rust/cargo/bin/anchor
    echo "  DEBUG: Listing /root/.avm/bin/:"
    ls -la /root/.avm/bin/ || echo "  /root/.avm/bin/ not found"
    exit 1
fi

# Test 2: Test as fresh user with login shell (simulates SSH)
echo "Test 2: Testing as fresh user (simulating OS Login SSH)..."
if sudo -u oslogin_test_user bash -l -c 'solana --version' >/dev/null 2>&1; then
    echo "  [OK] solana accessible via PATH for new user"
else
    echo "  [ERROR] solana NOT in PATH for new user"
    echo "  DEBUG: User PATH is:"
    sudo -u oslogin_test_user bash -l -c 'echo $PATH'
    exit 1
fi

if sudo -u oslogin_test_user bash -l -c 'cargo --version' >/dev/null 2>&1; then
    echo "  [OK] cargo accessible via PATH for new user"
else
    echo "  [ERROR] cargo NOT in PATH for new user"
    exit 1
fi

if sudo -u oslogin_test_user bash -l -c 'anchor --version' >/dev/null 2>&1; then
    echo "  [OK] anchor accessible via PATH for new user"
else
    echo "  [ERROR] anchor NOT in PATH for new user"
    exit 1
fi

# Cleanup test user
userdel -r oslogin_test_user 2>/dev/null || true

echo "[OK] All binaries accessible to all users"

# === FINALIZATION ===
echo ""
echo "========================================"
echo "   SETUP COMPLETE - $(date)"
echo "========================================"
echo ""
echo "Run 'run-smoke-test.sh' to verify installation."
echo "Full log at: $LOG_FILE"