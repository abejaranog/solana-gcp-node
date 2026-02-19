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

## Quick Start

1. **`make install`** — Terraform and gcloud CLI (if you don't have them).
2. **`make check`** — Verify tools and that you're logged in with gcloud.
3. **`make init`** — GCP project (prompts if not set), auth check, Terraform init.
4. **Edit `config/access.yaml`** — Team names and user emails. If the file doesn't exist, the first `make deploy` creates a template; edit it and run `make deploy` again.
5. **`make deploy`** — Deploy nodes.

**Details:** Init writes the project to `terraform.tfvars` and checks user credentials + Application Default Credentials (browser only if ADC is missing). Deploy creates VPC, firewall (SSH via IAP, RPC/WS open), and one node per team — or `solana-dev-node-00`, `01`, … if not using teams. **Time:** ~2 min infra + ~8–10 min software per node.

**After deploy:**

| Goal | Command |
|------|---------|
| Watch installation | `make logs` or `make logs NODE=name` |
| List nodes | `make status` |
| Validate node | `make smoke-test` or `make smoke-test TEAM=alpha` |
| SSH to node | `make ssh` or `make ssh TEAM=alpha` or `make ssh NODE=name` |

SSH uses IAP (port 22 not exposed). See [Available Commands](#available-commands) for the full list.

---

## Prerequisites

- **GCP project** with billing enabled  
- **Terraform** ≥ 1.8.5  
- **gcloud CLI**  

Install tools: `make install` (macOS/Linux). Or install manually: [Terraform](https://www.terraform.io/downloads), [gcloud](https://cloud.google.com/sdk/docs/install).

**Authentication:** `make init` checks user credentials (`gcloud auth login` if needed) and Application Default Credentials (runs `gcloud auth application-default login` only when ADC is missing or expired). APIs (Compute, IAP) are enabled by Terraform on deploy. **Versions:** Terraform `>= 1.8.5`, Google Provider `~> 7.16`.

---

## Available Commands

| Group | Command | Description |
|-------|---------|-------------|
| **Start** | `make help` | Full help and tips |
| | `make install` | Install Terraform and gcloud CLI |
| | `make check` | Verify tools and gcloud auth |
| | `make init` | Project, auth, Terraform init |
| | `make plan` | Preview Terraform changes |
| | `make deploy` | Deploy infrastructure |
| **Nodes on/off** | `make stop` / `make start` | Stop or start all nodes (data preserved) |
| | `make stop NODE=name` / `make start NODE=name` | One node |
| **Monitor** | `make status` | List nodes (uses project from terraform.tfvars) |
| | `make logs` [NODE=name] | Installation logs |
| | `make smoke-test` [TEAM=alpha \| NODE=name] | Validation on node(s). Uses IAP. |
| | `make costs` | Cost breakdown |
| **Access** | `make ssh` [TEAM=alpha \| NODE=name] | SSH to node (IAP) |
| **Cleanup** | `make access` | Manage config/access.yaml |
| | `make destroy` | Remove all infrastructure (confirmation) |
| | `make clean` | Remove local Terraform state/cache only |

---

## Architecture

```
.
├── main.tf                          # Terraform entrypoint, calls solana-node module
├── variables.tf                     # Project, region, zone, machine_type, IAP, node_count
├── outputs.tf                       # Node list, SSH commands, summary
├── terraform.tfvars                 # project_id (created by make init if missing)
├── terraform.tfvars.example         # Example tfvars
├── config/
│   └── access.yaml                 # Teams and user emails (template by deploy if missing)
├── Makefile                         # install, check, init, deploy, status, ssh, logs, stop/start, etc.
├── terraform_modules/
│   └── solana-node/                 # Reusable node module
│       ├── main.tf                  # VPC, firewall, compute instance, startup script
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    ├── setup-modular.sh             # Startup (used if present; teams/services from metadata)
    └── setup-solana.sh              # Fallback (kernel + Rust, Solana, Anchor, Node)
```

**Design decisions:** (1) **Modular:** N nodes via `node_count` or teams in `config/access.yaml`. (2) **Default service account** for simplicity. (3) **SSH via IAP** by default; Makefile uses `--tunnel-through-iap`. (4) **Idempotent startup script** so recreating the instance gives the same environment.

---

## Technical Specifications

Defaults in `variables.tf`; override with `TF_VAR_*` or `terraform.tfvars`.

| Component | Default | Note |
|-----------|---------|------|
| **Compute** | `e2-standard-2` (2 vCPU, 8 GB) | For heavier load use e.g. `TF_VAR_machine_type=n2-standard-16` |
| **Storage** | 500GB SSD (`pd-ssd`) | Ledger I/O |
| **OS** | Ubuntu 22.04 LTS | |
| **Region / Zone** | `europe-southwest1` / `europe-southwest1-a` (Madrid) | Override with `TF_VAR_region` / `TF_VAR_zone` |
| **SSH** | IAP only (`enable_iap_ssh=true`) | Port 22 not exposed |

**Kernel tuning (startup script):** `net.core.rmem_max` / `wmem_max` = 128MB, `vm.max_map_count` = 1M, `nofile` = 1M — required for Solana UDP gossip/TPU.

**Stack on node:** Rust, Solana CLI, Anchor (optional), Node.js 20 LTS + Yarn, jq, fio.

---

## Advanced Configuration

**Teams vs numeric nodes:** With teams in `config/access.yaml` you get `solana-dev-node-alpha`, `-beta`, etc. Without, nodes are `solana-dev-node-00`, `01`, … (`NODE_COUNT`).

**Multiple nodes (numeric):** `TF_VAR_node_count=3 make deploy` → connect with `make ssh NODE=solana-dev-node-02`.

**Direct SSH (no IAP):** `TF_VAR_enable_iap_ssh=false make deploy`. Port 22 exposed; use only for debugging. Restrict with `TF_VAR_allowed_ssh_cidrs` if needed.

**Region/machine:** `TF_VAR_region=us-central1`, `TF_VAR_zone=us-central1-a`, `TF_VAR_machine_type=n2-standard-8` (and re-deploy).

---

## Security

**Scope:** Development only. Ephemeral nodes, no mainnet keys, RPC/WS open for dev.

**SSH:** IAP (default) — port 22 not exposed; all Makefile SSH uses `--tunnel-through-iap`. Direct SSH: `enable_iap_ssh=false` for troubleshooting only.

**RPC/WebSocket:** 8899/8900 open to `0.0.0.0/0`. For production, use Cloud Armor, VPC peering, or VPN.

**Service account:** Default compute SA; change in `terraform_modules/solana-node/main.tf` if you need custom permissions.

---

## Smoke Test

Runs on the node via SSH (IAP): checks Rust/Solana/Anchor/Node, kernel tuning, starts test-validator, airdrop, cleanup. Use `make smoke-test` or `make smoke-test TEAM=alpha` / `NODE=name`. 90s timeout per node when `timeout` is available. On failure, SSH and run `/home/ubuntu/run-smoke-test.sh` or check `/var/log/solana-setup.log`.

---

## Troubleshooting

| Issue | What to do |
|-------|------------|
| **No nodes / wrong project on `make status`** | Set `project_id` in `terraform.tfvars` or `TF_VAR_project_id`; run `gcloud config set project YOUR_PROJECT_ID`. After reauth: `gcloud auth login` and/or `gcloud auth application-default login`. |
| **Startup script fails** | `make logs`; `make ssh` and `tail -f /var/log/solana-setup.log`. Often: slow network or need larger machine type. |
| **Smoke test / SSH doesn't connect** | IAP required. If `make ssh` works, smoke-test should too. Enable API: `gcloud services enable iap.googleapis.com`. |
| **Init keeps asking for project** | Project is in `terraform.tfvars` or env; init writes it there. Deploy reads the same. |
| **Strange output on stop/start** | From gcloud internals (e.g. nc on macOS); nodes still stop/start. |

---

## Estimated Costs

Default `e2-standard-2` in `europe-southwest1`: ~\$0.13/h compute + ~\$0.023/h storage (500GB SSD) → ~\$0.15/h, ~\$112/month (730h). Use `make stop` to pause (data kept); `make destroy` to remove everything.

---

## License

MIT

---

**Author:** @abejaranog — If this helps you, star the repo, report issues, or contribute.
