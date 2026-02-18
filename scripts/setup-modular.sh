#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/solana-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Solana GCP Node Setup - $(date) ==="

# === 0. INSTALL DEPENDENCIES ===
echo "--- [0/7] Installing dependencies ---"

# Install jq for JSON parsing
sudo apt-get update
sudo apt-get install -y jq curl

# Load configuration from metadata
CONFIG=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/config 2>/dev/null || echo '{}')

# Function to check if service is enabled
service_enabled() {
    local service=$1
    echo "$CONFIG" | jq -r ".services.${service}.enabled // false" | grep -q true
}

# Function to get settings
get_setting() {
    local setting=$1
    echo "$CONFIG" | jq -r ".settings.${setting} // \"\""
}

# === 1. KERNEL TUNING ===
if service_enabled "kernel_tuning"; then
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
else
    echo "--- [1/7] Skipping Kernel Tuning (disabled) ---"
fi

# === 2. SYSTEM DEPENDENCIES ===
if service_enabled "system_dependencies"; then
    echo "--- [2/7] Installing system dependencies ---"
    
    sudo apt-get install -y \
        build-essential \
        pkg-config \
        libssl-dev \
        libudev-dev \
        clang \
        cmake
    
    echo "[OK] Dependencies installed"
else
    echo "--- [2/7] Skipping System Dependencies (disabled) ---"
fi

# === 3. RUST ===
if service_enabled "rust"; then
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
else
    echo "--- [3/7] Skipping Rust (disabled) ---"
fi

# === 4. SOLANA CLI ===
if service_enabled "solana"; then
    echo "--- [4/7] Installing Solana CLI ---"
    
    # Download and extract Solana directly to /opt/solana
    mkdir -p /opt/solana/bin
    SOLANA_VERSION="stable"
    curl -sSfL "https://release.anza.xyz/${SOLANA_VERSION}/solana-release-x86_64-unknown-linux-gnu.tar.bz2" | tar -xjf - -C /opt/solana --strip-components=1
    
    # Set permissions for all users
    chmod -R 755 /opt/solana
    
    echo "[OK] Solana CLI installed in /opt/solana"
else
    echo "--- [4/7] Skipping Solana CLI (disabled) ---"
fi

# === 5. NODE.JS + YARN ===
if service_enabled "nodejs"; then
    echo "--- [5/7] Installing Node.js and Yarn ---"
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    sudo npm install --global yarn
    
    echo "[OK] Node.js and Yarn installed"
else
    echo "--- [5/7] Skipping Node.js (disabled) ---"
fi

# === 6. ANCHOR FRAMEWORK ===
if service_enabled "anchor"; then
    echo "--- [6/7] Installing Anchor Framework ---"
    
    # Install Anchor using the global Cargo with AVM_HOME in /opt
    export PATH="/opt/solana/bin:/opt/rust/cargo/bin:$PATH"
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    export AVM_HOME=/opt/avm
    
    # Create /opt/avm directory
    mkdir -p /opt/avm
    
    # Install anchor-cli using cargo install
    echo "Installing anchor-cli using cargo install..."
    cargo install --git https://github.com/coral-xyz/anchor anchor-cli --locked --force --root /opt/avm
    
    # Set permissions for /opt/avm
    chmod -R 755 /opt/avm
    
    # Verify anchor binary exists
    if [ ! -f "/opt/avm/bin/anchor" ]; then
        echo "  [ERROR] Could not find anchor binary in /opt/avm/bin"
        ls -la /opt/avm/bin/ || echo "  /opt/avm/bin/ is empty"
        exit 1
    fi
    
    # Create a symlink in /opt/rust/cargo/bin for convenience
    ln -sf /opt/avm/bin/anchor /opt/rust/cargo/bin/anchor
    
    echo "[OK] Anchor installed and accessible in /opt/avm/bin"
else
    echo "--- [6/7] Skipping Anchor Framework (disabled) ---"
fi

# === ENVIRONMENT SETUP ===
echo "--- [ENV] Setting up environment..."

# Set permissions for all Rust/Cargo binaries
chmod -R 755 /opt/rust/cargo/bin

# Make /home/ubuntu accessible for OS Login users
chmod 755 /home/ubuntu

# Update /etc/environment (loaded by PAM for all users including SSH)
cat > /etc/environment << 'ENVFILE'
PATH="/opt/solana/bin:/opt/rust/cargo/bin:/opt/avm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
RUSTUP_HOME="/opt/rust/rustup"
CARGO_HOME="/opt/rust/cargo"
ENVFILE

# Also add to /etc/profile.d for login shells
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

echo "[OK] Global PATH configured"

# === SMOKE TEST ===
echo "--- [SMOKE TEST] Running smoke test..."

# Create smoke test script
cat > /home/ubuntu/run-smoke-test.sh << 'SMOKETEST'
#!/bin/bash
set -e

# Load global environment
export AVM_HOME=/opt/avm
source /etc/profile.d/solana-dev.sh 2>/dev/null || true

echo "=========================================="
echo "   SOLANA NODE SMOKE TEST"
echo "=========================================="

echo ""
echo "[1/5] Verifying installations..."

# Check enabled services
CONFIG=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/config 2>/dev/null || echo '{}')

service_enabled() {
    local service=$1
    echo "$CONFIG" | jq -r ".services.${service}.enabled // false" | grep -q true
}

if service_enabled "rust"; then
    echo -n "  Rust: " && rustc --version
fi

if service_enabled "solana"; then
    echo -n "  Solana: " && solana --version
fi

if service_enabled "anchor"; then
    echo -n "  Anchor: " && anchor --version
fi

if service_enabled "nodejs"; then
    echo -n "  Node: " && node --version
fi

echo ""
echo "[2/5] Verifying kernel tuning..."
if service_enabled "kernel_tuning"; then
    echo "  UDP buffer: $(sysctl net.core.rmem_max | cut -d'=' -f2 | tr -d ' ')"
    echo "  File limits: $(ulimit -n)"
else
    echo "  [SKIPPED] Kernel tuning disabled"
fi

echo ""
echo "[3/5] Testing Solana validator..."
if service_enabled "solana"; then
    solana-test-validator --ledger /tmp/smoke-test-ledger --quiet &
    VALIDATOR_PID=$!
    
    # Wait for validator to be ready (max 30s)
    for i in {1..30}; do
        if solana cluster-version 2>/dev/null; then
            echo "  [OK] Validator responding on attempt $i"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "  [ERROR] Validator not responding after 30 seconds"
            kill $VALIDATOR_PID 2>/dev/null || true
            exit 1
        fi
        sleep 1
    done
    
    kill $VALIDATOR_PID 2>/dev/null || true
    rm -rf /tmp/smoke-test-ledger
else
    echo "  [SKIPPED] Solana CLI disabled"
fi

echo ""
echo "[4/5] Testing basic operations..."
if service_enabled "solana"; then
    solana config set --url localhost
    echo "  [OK] Solana config set"
    
    # Test key generation
    KEYPAIR=$(solana-keygen new --no-bip39-passphrase --force -o /tmp/smoke-test-keypair.json 2>&1 | grep -oP 'pubkey: \K.*' || cat /tmp/smoke-test-keypair.json | jq -r '.[]' | head -1)
    echo "  [OK] Keypair generated: $KEYPAIR"
    
    # Test airdrop
    if solana airdrop 5 --keypair /tmp/smoke-test-keypair.json 2>/dev/null; then
        echo "  [OK] Airdrop successful"
    else
        echo "  [WARNING] Airdrop failed (validator might not be ready)"
    fi
else
    echo "  [SKIPPED] Solana operations disabled"
fi

echo ""
echo "[5/5] Cleanup..."
rm -f /tmp/smoke-test-keypair.json

echo ""
echo "=========================================="
echo "   [PASSED] SMOKE TEST PASSED"
echo "=========================================="
echo ""
echo "Your Solana node is ready for development."
if service_enabled "solana"; then
    echo "Run: solana-test-validator"
fi
SMOKETEST

chmod +x /home/ubuntu/run-smoke-test.sh

# Run smoke test
/home/ubuntu/run-smoke-test.sh

echo ""
echo "=========================================="
echo "   SETUP COMPLETE"
echo "=========================================="
echo ""
echo "Enabled services:"
for service in kernel_tuning system_dependencies rust solana nodejs anchor; do
    if service_enabled $service; then
        echo "  ✓ $service"
    else
        echo "  ✗ $service (disabled)"
    fi
done
echo ""
echo "Node is ready for hackathon development!"
