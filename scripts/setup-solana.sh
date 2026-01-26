#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/solana-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Solana GCP Node Setup - $(date) ==="

# === 1. KERNEL TUNING (Crítico para Solana) ===
echo "--- [1/7] Aplicando Kernel Tuning ---"

cat <<EOF | sudo tee /etc/sysctl.d/99-solana.conf
# UDP Buffer sizes (128MB) - Requerido para gossip protocol
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=134217728
net.core.wmem_default=134217728

# Memory maps para el ledger
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

# Aplicar límites a la sesión actual
ulimit -n 1000000 || true

echo "✅ Kernel tuning aplicado"

# === 2. DEPENDENCIAS DEL SISTEMA ===
echo "--- [2/7] Instalando dependencias del sistema ---"

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

echo "✅ Dependencias instaladas"

# === 3. RUST ===
echo "--- [3/7] Instalando Rust ---"

sudo -u ubuntu bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
sudo -u ubuntu bash -c 'source $HOME/.cargo/env && rustup component add rustfmt clippy'

echo "✅ Rust instalado"

# === 4. SOLANA CLI ===
echo "--- [4/7] Instalando Solana CLI ---"

sudo -u ubuntu bash -c 'sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"'

# Añadir al PATH permanentemente
echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' | sudo -u ubuntu tee -a /home/ubuntu/.bashrc

echo "✅ Solana CLI instalado"

# === 5. NODE.JS + YARN ===
echo "--- [5/7] Instalando Node.js y Yarn ---"

curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install --global yarn

echo "✅ Node.js y Yarn instalados"

# === 6. ANCHOR FRAMEWORK ===
echo "--- [6/7] Instalando Anchor Framework ---"

sudo -u ubuntu bash -c 'source $HOME/.cargo/env && cargo install --git https://github.com/coral-xyz/anchor avm --locked --force'
sudo -u ubuntu bash -c 'source $HOME/.cargo/env && avm install latest && avm use latest'

echo "✅ Anchor instalado"

# === 7. SMOKE TEST SCRIPT ===
echo "--- [7/7] Configurando Smoke Test ---"

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
    echo "  ✅ UDP buffers: $RMEM bytes (OK)"
else
    echo "  ❌ UDP buffers: $RMEM bytes (BAJO)"
    exit 1
fi

echo ""
echo "[3/5] Iniciando test-validator..."
solana-test-validator --ledger /tmp/smoke-test-ledger --quiet &
VALIDATOR_PID=$!

# Esperar a que el validador esté listo (máx 30s)
for i in {1..30}; do
    if solana cluster-version 2>/dev/null; then
        echo "  ✅ Validador respondiendo en intento $i"
        break
    fi
    if [[ $i -eq 30 ]]; then
        echo "  ❌ Validador no respondió en 30s"
        kill $VALIDATOR_PID 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

echo ""
echo "[4/5] Probando airdrop..."
solana config set --url localhost
KEYPAIR=$(solana-keygen new --no-bip39-passphrase --force -o /tmp/smoke-test-keypair.json 2>&1 | grep -oP 'pubkey: \K.*' || cat /tmp/smoke-test-keypair.json | jq -r '.[]' | head -1)
solana airdrop 5 --keypair /tmp/smoke-test-keypair.json 2>/dev/null && echo "  ✅ Airdrop exitoso"

echo ""
echo "[5/5] Limpiando..."
kill $VALIDATOR_PID 2>/dev/null || true
rm -rf /tmp/smoke-test-ledger /tmp/smoke-test-keypair.json

echo ""
echo "=========================================="
echo "   ✅ SMOKE TEST PASSED"
echo "=========================================="
echo ""
echo "Tu nodo Solana está listo para desarrollo."
echo "Ejecuta: solana-test-validator"
EOF

chmod +x /home/ubuntu/run-smoke-test.sh
chown ubuntu:ubuntu /home/ubuntu/run-smoke-test.sh

# === FINALIZACIÓN ===
echo ""
echo "=========================================="
echo "   SETUP COMPLETADO - $(date)"
echo "=========================================="
echo ""
echo "Ejecuta 'run-smoke-test.sh' para verificar la instalación."
echo "Log completo en: $LOG_FILE"