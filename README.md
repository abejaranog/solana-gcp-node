# Solana GCP Node Blueprint

**Infrastructure-as-Code to deploy Solana development nodes on Google Cloud Platform.**

This blueprint solves that problem: from 4+ hours of manual setup to **10 automated minutes**.

---

## Why This Project Exists

**Problem:** Setting up a Solana node isn't just `apt install solana`. It requires specific kernel tuning (UDP buffers, file descriptors), complete toolchain (Rust, Anchor, Node.js), and knowledge of protocol particularities.

**Solution:** Modular Terraform + idempotent startup script that applies the correct optimizations from first boot.

**Impact:**
- **Developer Tooling:** Reduces Solana onboarding friction
- **Censorship Resistance:** Facilitates geographic diversification (includes Madrid region)
- **Reproducibility:** Versioned, auditable infrastructure

---

## Architecture

```
.
├── main.tf                          # Orchestrator: VPC, firewall, modules
├── variables.tf                     # Centralized configuration
├── outputs.tf                       # Endpoints and useful commands
├── terraform_modules/
│   └── solana-node/                 # Reusable module
│       ├── main.tf                  # Instance definition
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    └── setup-solana.sh              # Startup script (kernel + software)
```

**Design Decisions:**

1. **Modularization:** The `solana-node` module is reusable. You can deploy N nodes by changing `node_count`.

2. **Default Service Account:** Uses GCE's default SA instead of creating a custom one. Reason: simplicity > over-engineering. For dev nodes, default permissions are sufficient.

3. **Dual SSH Mode:** IAP (secure) vs direct (fast). The first is default, the second exists for troubleshooting or environments where IAP isn't available.

4. **Idempotent Startup Script:** All tuning is applied on boot. If the instance is recreated, the environment is identical.

---

## Technical Specifications

| Component | Configuration | Justification |
|-----------|---------------|---------------|
| **Compute** | `n2-standard-16` (16 vCPU, 64GB RAM) | Minimum for test-validator without lag |
| **Storage** | 500GB SSD (`pd-ssd`) | Consistent IOPS for ledger I/O |
| **OS** | Ubuntu 22.04 LTS | Long support + Solana compatibility |
| **Region** | `europe-southwest1` (Madrid) | EU geographic diversification |

### Kernel Tuning (critical for Solana)

```bash
net.core.rmem_max=134217728          # UDP RX buffer: 128MB
net.core.wmem_max=134217728          # UDP TX buffer: 128MB
vm.max_map_count=1000000             # Memory maps for ledger
nofile=1000000                       # File descriptors
```

**Why:** Solana protocol uses UDP for gossip/TPU. Small buffers = packet loss = network degradation.

### Complete Stack

- **Rust** (stable): Compiler for Solana programs
- **Solana CLI** (stable): Command-line tools
- **Anchor Framework** (latest): Most used development framework
- **Node.js 20 LTS + Yarn**: For integration tests
- **Utilities:** jq (JSON parsing), fio (disk benchmarking)

---

## Prerequisites

You need three things:

1. **Active GCP project** with billing enabled
2. **gcloud CLI** authenticated:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```
3. **Terraform** >= 1.8.5

Required APIs (Compute Engine, IAP) are enabled automatically.

**Pinned versions:**
- Terraform: `>= 1.8.5` (compatible with higher versions)
- Google Provider: `~> 7.16` (7.16.x, automatic patches, no breaking changes)

---

## Quick Start

### First time (step-by-step guided flow)

The Makefile guides you through the entire process. If you've never used Terraform or GCP, simply run:

```bash
git clone https://github.com/YOUR_USERNAME/solana-gcp-node
cd solana-gcp-node

# View complete help
make help

# Step 1: Verify you have everything installed
make check

# Step 2: Configure your GCP project
export TF_VAR_project_id="your-gcp-project"
make init

# Step 3: Deploy (creates VPC, firewall, Solana node)
make deploy
```

**What gets created?**
- Dedicated VPC (`10.0.0.0/24`)
- Firewall rules (SSH via IAP, RPC/WS open)
- 1 Solana node with 64GB RAM, 500GB SSD

**Time:** ~2 minutes infrastructure + ~8-10 minutes software installation

### Monitor progress

While the node configures:

```bash
# View installation logs in real-time
make logs

# View node status
make status
```

### Verify everything works

```bash
make smoke-test
```

This validates:
- Rust, Solana CLI, Anchor installed
- Kernel tuning applied (UDP buffers, file limits)
- `solana-test-validator` starts and responds
- Airdrop works

### Connect to the node

```bash
make ssh
```

Uses IAP tunnel (secure, zero-config).

---

## Advanced Configuration

### Deploy multiple nodes

```bash
export TF_VAR_node_count=3
make deploy
```

Nodes are named `solana-dev-node-00`, `solana-dev-node-01`, etc.

View all nodes:

```bash
terraform output nodes
```

Connect to a specific node:

```bash
make ssh NODE=solana-dev-node-02
```

### Open SSH (fast development)

If IAP creates friction (debugging, CI/CD, etc.), you can use direct SSH:

```bash
export TF_VAR_enable_iap_ssh=false
make deploy
```

**Warning:** This exposes port 22 to the internet. Only for temporary development.

To restrict to your IP:

```bash
export TF_VAR_enable_iap_ssh=false
export TF_VAR_allowed_ssh_cidrs='["203.0.113.42/32"]'
make deploy
```

### Change region/machine

```bash
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"
export TF_VAR_machine_type="n2-standard-8"  # 8 vCPU, 32GB RAM
make deploy
```

---

## Available Commands

### Getting Started
| Command | Description |
|---------|-------------|
| `make help` | Shows complete help with step-by-step guide |
| `make check` | Verifies prerequisites (Terraform, gcloud) |
| `make init` | Configures GCP project and initializes Terraform |
| `make plan` | Previews changes without applying them |
| `make deploy` | Deploys complete infrastructure |

### Monitoring
| Command | Description |
|---------|-------------|
| `make status` | Lists all nodes with status and IPs |
| `make logs` | View installation logs in real-time |
| `make smoke-test` | Runs end-to-end validation |

### Access
| Command | Description |
|---------|-------------|
| `make ssh` | Connects to first node |
| `make ssh NODE=solana-dev-node-01` | Connects to specific node |

### Cleanup
| Command | Description |
|---------|-------------|
| `make destroy` | Removes all infrastructure (asks for confirmation) |
| `make clean` | Cleans Terraform temporary files |

---

## Security

### Threat Model

This blueprint is designed for **development environments**, not production. Assumptions:

- **Ephemeral nodes:** Created/destroyed frequently
- **No sensitive data:** No mainnet private keys
- **Public network:** RPC/WS need to be accessible from internet for development

### SSH: Two modes

| Mode | Configuration | When to use |
|------|---------------|-------------|
| **IAP (default)** | `enable_iap_ssh=true` | Normal development, demos, shared environments |
| **Direct** | `enable_iap_ssh=false` | Debugging, CI/CD, troubleshooting |

**IAP (Identity-Aware Proxy):**
- Port 22 **not exposed** to internet
- Requires GCP authentication
- `gcloud compute ssh` handles tunnel automatically
- Zero-config for user

**Direct SSH:**
- Port 22 open (configurable via `allowed_ssh_cidrs`)
- Useful when IAP isn't available
- **Only for temporary development**

### RPC/WebSocket

Ports 8899/8900 are open to `0.0.0.0/0` in both modes. This is intentional to facilitate development.

**For production:** Use Cloud Armor, VPC peering, or VPN.

### Service Account

Uses **default compute service account** instead of creating a custom one. Reasons:

1. **Simplicity:** Fewer resources to manage
2. **Sufficient permissions:** For dev nodes, default permissions cover everything (Compute, Logging, Monitoring)
3. **Less friction:** No additional IAM bindings required

If you need custom permissions, modify `terraform_modules/solana-node/main.tf`.

---

## Smoke Test

Validation script that runs:

```bash
1. Verify versions (Rust, Solana, Anchor, Node)
2. Validate kernel tuning (UDP buffers >= 128MB)
3. Start test-validator
4. Wait for RPC ready (max 30s)
5. Airdrop 5 SOL to temporary keypair
6. Cleanup
```

If it fails, check `/var/log/solana-setup.log` on the instance.

---

## Project Structure

```
.
├── main.tf                          # Main orchestrator
├── variables.tf                     # Configuration
├── outputs.tf                       # Post-deploy info
├── Makefile                         # Helper commands
├── terraform_modules/
│   └── solana-node/                 # Reusable module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    └── setup-solana.sh              # Startup script (175 lines)
```

**Philosophy:** Modularity without over-engineering. The `solana-node` module is reusable but simple.

---

## Troubleshooting

### Startup script fails

```bash
# View complete logs
make logs

# SSH and check manually
make ssh
tail -f /var/log/solana-setup.log
```

Common causes:
- Timeout downloading Rust/Solana (slow network)
- Anchor build fails (insufficient memory - use `n2-standard-16` minimum)

### IAP doesn't work

```bash
# Verify API is enabled
gcloud services list --enabled | grep iap

# If not, enable manually
gcloud services enable iap.googleapis.com
```

### I want to switch from IAP to direct SSH (or vice versa)

```bash
export TF_VAR_enable_iap_ssh=false  # or true
terraform apply
```

Terraform will update only the firewall rule.

---

## Estimated Costs

Based on `n2-standard-16` in `europe-southwest1`:

| Resource | Cost/hour | Cost/month (730h) |
|----------|-----------|-------------------|
| Compute (n2-standard-16) | ~$0.78 | ~$569 |
| Storage (500GB SSD) | ~$0.023 | ~$17 |
| **Total** | **~$0.80** | **~$586** |

**Tip:** Use `make destroy` when not developing. Recreating the node takes 10 minutes.

---

## License

MIT

---

## Author

@abejaranog

If this project saves you time, consider:
- Star on GitHub
- Report issues
- Contribute improvements
