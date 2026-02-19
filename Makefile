# Makefile - Solana GCP Node Blueprint
# Step-by-step guide for users without infrastructure experience

.PHONY: help install init check deploy plan destroy ssh logs smoke-test status clean access stop start

# Variables (you can override: make ssh NODE=solana-dev-node-alpha or TEAM=alpha)
ZONE ?= europe-southwest1-a
NODE ?=
TERRAFORM_VERSION ?= 1.8.5
NODE_COUNT ?= 1
# GCP project: read from terraform.tfvars so status/logs/ssh use the same project as Terraform
GCP_PROJECT := $(strip $(shell sed -n 's/^project_id[ \t]*=[ \t]*"\(.*\)".*/\1/p' terraform.tfvars 2>/dev/null))

# Colors for messages
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

#==============================================================================
# HELP - Start here if it's your first time
#==============================================================================

help:
	@echo ""
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          SOLANA GCP NODE - BEGINNER'S GUIDE                   ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)FIRST STEPS (run in order):$(NC)"
	@echo ""
	@echo "  0. $(YELLOW)make install$(NC)    - Install Terraform and gcloud CLI (if needed)"
	@echo "  1. $(YELLOW)make check$(NC)      - Verify you have everything installed"
	@echo "  2. $(YELLOW)make init$(NC)       - Configure your GCP project"
	@echo "  3. $(YELLOW)make plan$(NC)       - Preview what will be created (optional)"
	@echo "  4. $(YELLOW)make deploy$(NC)     - Deploy nodes (creates teams config if needed)"
	@echo ""
	@echo "$(GREEN)NODES ON/OFF (without deleting):$(NC)"
	@echo ""
	@echo "  $(YELLOW)make stop$(NC)         - Stop nodes (saves cost; data preserved)"
	@echo "  $(YELLOW)make start$(NC)        - Start nodes"
	@echo "  $(YELLOW)make stop NODE=name$(NC)   - Stop a specific node"
	@echo "  $(YELLOW)make start NODE=name$(NC)  - Start a specific node"
	@echo ""
	@echo "$(GREEN)MONITORING:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make status$(NC)       - Show deployed nodes status"
	@echo "  $(YELLOW)make logs$(NC)         - View installation logs (first node or NODE=name)"
	@echo "  $(YELLOW)make smoke-test$(NC)   - Run smoke test (all nodes, or TEAM=alpha, or NODE=name)"
	@echo "  $(YELLOW)make costs$(NC)        - Show cost breakdown"
	@echo ""
	@echo "$(GREEN)ACCESS:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make ssh$(NC)          - Connect to first node via SSH"
	@echo "  $(YELLOW)make ssh TEAM=name$(NC)  - Connect to team node (alpha, beta)"
	@echo "  $(YELLOW)make ssh NODE=name$(NC)  - Connect to specific node"
	@echo ""
	@echo "$(GREEN)CLEANUP:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make access$(NC)       - Manage user access to nodes"
	@echo "  $(YELLOW)make destroy$(NC)      - Remove all infrastructure (asks for confirmation)"
	@echo "  $(YELLOW)make clean$(NC)        - Clean Terraform temporary files"
	@echo ""
	@echo "$(BLUE)TIPS:$(NC)"
	@echo "  - Full flow: $(GREEN)make install$(NC) -> $(GREEN)make check$(NC) -> $(GREEN)make init$(NC) -> $(GREEN)make deploy$(NC)"
	@echo "  - Node takes ~8-10 minutes to be ready after deploy; use $(GREEN)make logs$(NC) to watch"
	@echo "  - When done: $(GREEN)make destroy$(NC) to avoid costs (or $(GREEN)make stop$(NC) to pause)"
	@echo ""

#==============================================================================
# INSTALLATION OF PREREQUISITES
#==============================================================================

install:
	@echo ""
	@echo "$(BLUE)Installing prerequisites...$(NC)"
	@echo ""
	@echo "$(YELLOW)Detecting operating system...$(NC)"
	@echo "$(YELLOW)Target Terraform version: $(TERRAFORM_VERSION)$(NC)"
	@echo ""
	@OS=$$(uname -s); \
	if [ "$$OS" = "Darwin" ]; then \
		echo "$(GREEN)macOS detected$(NC)"; \
		if ! command -v brew >/dev/null 2>&1; then \
			echo "$(RED)[ERROR] Homebrew not found$(NC)"; \
			echo "Install Homebrew first: https://brew.sh"; \
			exit 1; \
		fi; \
		echo "$(BLUE)Installing Terraform $(TERRAFORM_VERSION)...$(NC)"; \
		brew tap hashicorp/tap 2>/dev/null || true; \
		brew install hashicorp/tap/terraform@$(TERRAFORM_VERSION) 2>/dev/null || brew install hashicorp/tap/terraform; \
		echo "$(BLUE)Installing gcloud CLI...$(NC)"; \
		brew install --cask google-cloud-sdk || brew upgrade google-cloud-sdk; \
	elif [ "$$OS" = "Linux" ]; then \
		echo "$(GREEN)Linux detected$(NC)"; \
		echo "$(BLUE)Installing Terraform $(TERRAFORM_VERSION)...$(NC)"; \
		wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip; \
		sudo unzip -o /tmp/terraform.zip -d /usr/local/bin/; \
		sudo chmod +x /usr/local/bin/terraform; \
		rm /tmp/terraform.zip; \
		echo "$(BLUE)Installing gcloud CLI...$(NC)"; \
		curl https://sdk.cloud.google.com | bash; \
		exec -l $$SHELL; \
	else \
		echo "$(RED)[ERROR] Unsupported OS: $$OS$(NC)"; \
		echo "Please install manually:"; \
		echo "  - Terraform $(TERRAFORM_VERSION): https://www.terraform.io/downloads"; \
		echo "  - gcloud CLI: https://cloud.google.com/sdk/docs/install"; \
		exit 1; \
	fi
	@echo ""
	@echo "$(GREEN)[OK] Installation complete$(NC)"
	@echo ""
	@echo "$(YELLOW)Next step:$(NC) make check (to verify installation)"
	@echo ""

#==============================================================================
# PREREQUISITES VERIFICATION
#==============================================================================

check:
	@echo ""
	@echo "$(BLUE)Verifying prerequisites...$(NC)"
	@echo ""
	@command -v terraform >/dev/null 2>&1 && \
		echo "$(GREEN)[OK] Terraform installed:$(NC) $$(terraform version | head -n1)" || \
		(echo "$(RED)[ERROR] Terraform NOT found$(NC)" && \
		 echo "  Install from: https://www.terraform.io/downloads" && exit 1)
	@command -v gcloud >/dev/null 2>&1 && \
		echo "$(GREEN)[OK] gcloud CLI installed:$(NC) $$(gcloud version | head -n1)" || \
		(echo "$(RED)[ERROR] gcloud CLI NOT found$(NC)" && \
		 echo "  Install from: https://cloud.google.com/sdk/docs/install" && exit 1)
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1 && \
		echo "$(GREEN)[OK] gcloud authenticated:$(NC) $$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" || \
		(echo "$(RED)[ERROR] gcloud NOT authenticated$(NC)" && \
		 echo "  Run: gcloud auth login" && exit 1)
	@echo ""
	@echo "$(GREEN)[OK] All prerequisites are OK$(NC)"
	@echo ""

#==============================================================================
# PROJECT INITIALIZATION
#==============================================================================

init: check
	@echo ""
	@echo "$(BLUE)Configuring project...$(NC)"
	@echo ""
	@if [ -n "$$TF_VAR_project_id" ]; then \
		echo "$(GREEN)[OK] Project configured (env):$(NC) $$TF_VAR_project_id"; \
	else \
		project_id=$$(sed -n 's/^project_id[ \t]*=[ \t]*"\(.*\)".*/\1/p' terraform.tfvars 2>/dev/null); \
		if [ -n "$$project_id" ]; then \
			echo "$(GREEN)[OK] Project configured (terraform.tfvars):$(NC) $$project_id"; \
			export TF_VAR_project_id="$$project_id"; \
		else \
			echo "$(YELLOW)Project ID not set.$(NC) List projects: $(GREEN)gcloud projects list$(NC)"; \
			echo ""; \
			read -p "Enter your GCP project ID: " project_id && [ -n "$$project_id" ] || (echo "$(RED)Project ID cannot be empty$(NC)" && exit 1); \
			(grep -v '^project_id' terraform.tfvars 2>/dev/null; echo 'project_id = "'"$$project_id"'"') > terraform.tfvars.tmp && mv terraform.tfvars.tmp terraform.tfvars; \
			export TF_VAR_project_id="$$project_id"; \
			echo "$(GREEN)[OK] Project saved to terraform.tfvars:$(NC) $$project_id"; \
		fi; \
	fi
	@echo ""
	@echo "$(BLUE)Checking gcloud authentication...$(NC)"
	@gcloud auth print-access-token >/dev/null 2>&1 || \
		(echo "$(RED)[ERROR] User credentials expired or invalid$(NC)" && \
		 echo "  Run: $(GREEN)gcloud auth login$(NC)" && exit 1)
	@echo "$(GREEN)[OK] User credentials valid$(NC)"
	@echo ""
	@echo "$(BLUE)Checking Application Default Credentials (for Terraform)...$(NC)"
	@gcloud auth application-default print-access-token >/dev/null 2>&1 && echo "$(GREEN)[OK] ADC already valid$(NC)" || \
		(echo "$(YELLOW)ADC missing or expired. Opening browser to sign in...$(NC)" && \
		 gcloud auth application-default login)
	@echo ""
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	@terraform init -upgrade
	@echo ""
	@echo "$(GREEN)[OK] Initialization complete$(NC)"
	@echo ""
	@echo "$(YELLOW)Next step:$(NC) make plan  (to preview what will be created)"
	@echo "        or: make deploy (to deploy directly)"
	@echo ""

#==============================================================================
# PLANNING (PREVIEW)
#==============================================================================

plan:
	@echo ""
	@echo "$(BLUE)Previewing changes...$(NC)"
	@echo ""
	@echo "This shows you WHAT will be created without creating anything yet."
	@echo ""
	@terraform plan
	@echo ""
	@echo "$(YELLOW)If everything looks good, run:$(NC) make deploy"
	@echo ""

#==============================================================================
# DEPLOYMENT
#==============================================================================

deploy:
	@echo ""
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║                  DEPLOYING SOLANA NODES                        ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@project_id="$$TF_VAR_project_id"; [ -z "$$project_id" ] && project_id="$(GCP_PROJECT)"; \
	if [ -z "$$project_id" ]; then \
		echo "$(RED)[ERROR] Project not configured$(NC)"; \
		echo ""; \
		echo "Run: $(GREEN)make init$(NC)  (or set TF_VAR_project_id or add project_id to terraform.tfvars)"; \
		echo ""; \
		exit 1; \
	fi; \
	echo "$(YELLOW)Project:$(NC) $$project_id"
	@echo ""
	# Check if teams config exists, create if not
	@if [ ! -f "config/access.yaml" ]; then \
		echo "$(YELLOW)[INFO] No teams config found. Creating template...$(NC)"; \
		mkdir -p config; \
		echo "# Team Configuration for Solana Nodes" > config/access.yaml; \
		echo "teams:" >> config/access.yaml; \
		echo "  alpha:" >> config/access.yaml; \
		echo "    users:" >> config/access.yaml; \
		echo "      - \"dev1@company.com\"" >> config/access.yaml; \
		echo "      - \"dev2@company.com\"" >> config/access.yaml; \
		echo "  beta:" >> config/access.yaml; \
		echo "    users:" >> config/access.yaml; \
		echo "      - \"dev3@company.com\"" >> config/access.yaml; \
		echo "      - \"dev4@company.com\"" >> config/access.yaml; \
		echo "$(GREEN)[OK] Template created in config/access.yaml$(NC)"; \
		echo "Edit the file with your team emails and run 'make deploy' again."; \
		echo ""; \
		exit 0; \
	fi
	# Check if teams config has real users (not just template)
	@if grep -q "dev1@company.com\|dev2@company.com\|dev3@company.com\|dev4@company.com" config/access.yaml; then \
		echo "$(YELLOW)[WARNING] Template emails detected in config/access.yaml$(NC)"; \
		echo "Please edit the file with real team emails before deploying."; \
		echo ""; \
		echo "Current teams:"; \
		if command -v yq >/dev/null 2>&1; then \
			yq e '.teams | to_entries | .[] | "Team: \(.key) | Users: \(.value.users | length) users"' config/access.yaml 2>/dev/null || echo "  Could not parse YAML"; \
		else \
			echo "  Install 'yq' for better formatting or view config/access.yaml directly"; \
		fi; \
		echo ""; \
		echo "Edit config/access.yaml and run 'make deploy' again."; \
		exit 0; \
	fi
	# Show deployment mode
	@if [ -f "config/access.yaml" ]; then \
		if command -v yq >/dev/null 2>&1; then \
			TEAMS_COUNT=$$(yq e '.teams | to_entries | select(.value.users | length > 0) | length' config/access.yaml 2>/dev/null || echo "0"); \
		else \
			TEAMS_COUNT=$$(grep -c "users:" config/access.yaml 2>/dev/null || echo "0"); \
		fi; \
		if [ "$$TEAMS_COUNT" -gt 0 ]; then \
			echo "$(GREEN)[TEAMS MODE] Using teams configuration$(NC)"; \
			echo "Teams: $$TEAMS_COUNT"; \
			echo "Nodes will be named: solana-dev-node-{team_name}"; \
		else \
			echo "$(YELLOW)[TRADITIONAL MODE] Using node count$(NC)"; \
			echo "Node count: $(NODE_COUNT)"; \
			echo "Nodes will be named: solana-dev-node-00, solana-dev-node-01, ..."; \
			export TF_VAR_node_count=$(NODE_COUNT); \
		fi; \
	else \
		echo "$(YELLOW)[TRADITIONAL MODE] Using node count$(NC)"; \
		echo "Node count: $(NODE_COUNT)"; \
		echo "Nodes will be named: solana-dev-node-00, solana-dev-node-01, ..."; \
		export TF_VAR_node_count=$(NODE_COUNT); \
	fi
	@echo ""
	@echo "$(BLUE)Terraform is creating infrastructure...$(NC)"
	@TF_OUTPUT=$$(terraform apply -auto-approve -refresh=false 2>&1); \
	TF_EXIT=$$?; \
	echo "$$TF_OUTPUT"; \
	if [ $$TF_EXIT -ne 0 ]; then \
		if echo "$$TF_OUTPUT" | grep -qiE "(does not have enough resources|unavailable.*zone|Try a different zone|Try a different VM hardware|insufficient resources)"; then \
			echo ""; \
			echo "$(RED)╔════════════════════════════════════════════════════════════════╗$(NC)"; \
			echo "$(RED)║          ERROR: INSUFFICIENT RESOURCES IN ZONE                  ║$(NC)"; \
			echo "$(RED)╚════════════════════════════════════════════════════════════════╝$(NC)"; \
			echo ""; \
			echo "$(YELLOW)Deployment failed because there are not enough resources available in the selected zone.$(NC)"; \
			echo ""; \
			echo "$(BLUE)SOLUTIONS:$(NC)"; \
			echo ""; \
			echo "$(GREEN)Option 1: Change region and zone$(NC)"; \
			echo "  Edit $(YELLOW)variables.tf$(NC) or $(YELLOW)terraform.tfvars$(NC) and modify:"; \
			echo "    $(YELLOW)region = \"us-central1\"$(NC)  # or europe-west1, europe-west4, us-east1, etc."; \
			echo "    $(YELLOW)zone   = \"us-central1-a\"$(NC)  # must match the region"; \
			echo ""; \
			echo "  Or use environment variables:"; \
			echo "    $(GREEN)TF_VAR_region=us-central1 TF_VAR_zone=us-central1-a make deploy$(NC)"; \
			echo ""; \
			echo "$(GREEN)Option 2: Change machine type$(NC)"; \
			echo "  Edit $(YELLOW)variables.tf$(NC) or $(YELLOW)terraform.tfvars$(NC) and modify:"; \
			echo "    $(YELLOW)machine_type = \"e2-standard-4\"$(NC)  # or n2-standard-4, e2-standard-8, etc."; \
			echo ""; \
			echo "  Or use environment variable:"; \
			echo "    $(GREEN)TF_VAR_machine_type=e2-standard-4 make deploy$(NC)"; \
			echo ""; \
			echo "$(BLUE)Common available regions:$(NC)"; \
			echo "  - $(YELLOW)europe-west1$(NC) (Belgium) - zones: a, b, c"; \
			echo "  - $(YELLOW)europe-west4$(NC) (Netherlands) - zones: a, b, c"; \
			echo "  - $(YELLOW)us-central1$(NC) (Iowa) - zones: a, b, c"; \
			echo "  - $(YELLOW)us-east1$(NC) (South Carolina) - zones: a, b, c"; \
			echo ""; \
			echo "$(BLUE)Recommended machine types:$(NC)"; \
			echo "  - $(YELLOW)e2-standard-2$(NC) (2 vCPU, 8GB RAM) - development"; \
			echo "  - $(YELLOW)e2-standard-4$(NC) (4 vCPU, 16GB RAM) - medium workloads"; \
			echo "  - $(YELLOW)n2-standard-8$(NC) (8 vCPU, 32GB RAM) - production"; \
			echo ""; \
			echo "$(YELLOW)Check available resources in a zone:$(NC)"; \
			echo "  $(GREEN)gcloud compute machine-types list --zones=ZONE$(NC)"; \
			echo ""; \
			exit 1; \
		fi; \
		if [ $$TF_EXIT -ne 0 ] && ! echo "$$TF_OUTPUT" | grep -qiE "(does not have enough resources|unavailable.*zone|Try a different zone|Try a different VM hardware|insufficient resources)"; then \
			echo "$(YELLOW)[INFO] Syncing state after provider bug...$(NC)"; \
			terraform refresh && terraform apply -auto-approve -refresh=false; \
		fi; \
		exit $$TF_EXIT; \
	fi
	@echo ""
	@echo "$(GREEN)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                    DEPLOYMENT COMPLETE                         ║$(NC)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)[WAIT] Nodes are installing software (Rust, Solana, Anchor)...$(NC)"
	@echo "   This takes ~8-10 minutes."
	@echo ""
	@echo "$(BLUE)While you wait, you can:$(NC)"
	@echo "  1. View progress:  $(GREEN)make logs$(NC)"
	@echo "  2. View status:    $(GREEN)make status$(NC)"
	@echo ""
	@echo "$(BLUE)When finished (8-10 min):$(NC)"
	@echo "  1. Verify:         $(GREEN)make smoke-test$(NC)"
	@echo "  2. Connect:        $(GREEN)make ssh$(NC)"
	@echo ""

#==============================================================================
# DESTRUCTION (WITH CONFIRMATION)
#==============================================================================

destroy:
	@echo ""
	@echo "$(RED)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(RED)║                    WARNING                                     ║$(NC)"
	@echo "$(RED)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)This will DELETE all infrastructure:$(NC)"
	@echo "  - Solana nodes"
	@echo "  - VPC and subnets"
	@echo "  - Firewall rules"
	@echo "  - Disks (500GB per node)"
	@echo ""
	@echo "$(RED)This action CANNOT be undone.$(NC)"
	@echo ""
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo ""; \
		echo "Destroying infrastructure..."; \
		terraform destroy -auto-approve; \
		echo ""; \
		@echo "[OK] Infrastructure removed"; \
		echo ""; \
	else \
		echo ""; \
		echo "Cancelled. Nothing was deleted."; \
		echo ""; \
	fi

#==============================================================================
# MONITORING AND ACCESS
#==============================================================================

status:
	@echo ""
	@echo "$(BLUE)Solana nodes status:$(NC)"
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	gcloud compute instances list --filter="name~solana-dev-node" $$PROJECT_ARG \
		--format="table(name,status,zone,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" || \
		(echo "$(YELLOW)No nodes found or gcloud failed (see error above).$(NC)" && \
		 [ -z "$(GCP_PROJECT)" ] && echo "$(YELLOW)Tip: add project_id in terraform.tfvars or set GCP_PROJECT=your-project$(NC)" || \
		 echo "Project: $(GCP_PROJECT). If nodes exist in console, run: $(GREEN)gcloud config set project $(GCP_PROJECT)$(NC) then make status")
	@echo ""

#------------------------------------------------------------------------------
# STOP / START (stop/start without deleting)
#------------------------------------------------------------------------------

stop:
	@echo ""
	@echo "$(YELLOW)Stopping node(s)...$(NC)"
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	if [ -n "$(NODE)" ]; then \
		echo "  Stopping $(NODE) in $(ZONE)"; \
		gcloud compute instances stop $(NODE) --zone=$(ZONE) $$PROJECT_ARG --quiet >/dev/null 2>&1 && \
			echo "$(GREEN)[OK] $(NODE) stopped$(NC)" || \
			(echo "$(RED)[ERROR] Could not stop $(NODE)$(NC)" && \
			 echo "  Check: make status"); \
	else \
		COUNT=0; \
		for name in $$(gcloud compute instances list --filter="name~solana-dev-node" --format="value(name)" $$PROJECT_ARG 2>/dev/null); do \
			[ -z "$$name" ] && continue; \
			echo "  Stopping $$name ($(ZONE))"; \
			gcloud compute instances stop $$name --zone=$(ZONE) $$PROJECT_ARG --quiet >/dev/null 2>&1 && \
				echo "    $(GREEN)[OK]$$(NC)" || echo "    $(RED)[ERROR]$$(NC)"; \
			COUNT=$$((COUNT+1)); \
		done; \
		if [ $$COUNT -eq 0 ]; then \
			echo "$(YELLOW)No nodes deployed.$(NC)"; \
		else \
			echo ""; \
			echo "$(GREEN)[OK] Done$(NC)"; \
		fi; \
	fi
	@echo ""

start:
	@echo ""
	@echo "$(YELLOW)Starting node(s)...$(NC)"
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	if [ -n "$(NODE)" ]; then \
		echo "  Starting $(NODE) in $(ZONE)"; \
		gcloud compute instances start $(NODE) --zone=$(ZONE) $$PROJECT_ARG --quiet >/dev/null 2>&1 && \
			echo "$(GREEN)[OK] $(NODE) started$(NC)" || \
			(echo "$(RED)[ERROR] Could not start $(NODE)$(NC)" && \
			 echo "  Check: make status"); \
	else \
		COUNT=0; \
		for name in $$(gcloud compute instances list --filter="name~solana-dev-node" --format="value(name)" $$PROJECT_ARG 2>/dev/null); do \
			[ -z "$$name" ] && continue; \
			echo "  Starting $$name ($(ZONE))"; \
			gcloud compute instances start $$name --zone=$(ZONE) $$PROJECT_ARG --quiet >/dev/null 2>&1 && \
				echo "    $(GREEN)[OK]$$(NC)" || echo "    $(RED)[ERROR]$$(NC)"; \
			COUNT=$$((COUNT+1)); \
		done; \
		if [ $$COUNT -eq 0 ]; then \
			echo "$(YELLOW)No nodes deployed.$(NC)"; \
		else \
			echo ""; \
			echo "$(GREEN)[OK] Done$(NC)"; \
		fi; \
	fi
	@echo ""

costs:
	@echo ""
	@echo "$(BLUE)Actual cost breakdown for Solana nodes:$(NC)"
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	echo "$(YELLOW)Compute Instances (REAL USAGE):$(NC)"; \
	gcloud compute instances list --filter="name~solana-dev-node" $$PROJECT_ARG \
		--format="table(name,machineType,zone,status,creationTimestamp)" 2>/dev/null || \
		echo "  No instances found"; \
	echo ""; \
	echo "$(YELLOW)Actual hourly cost based on uptime:$(NC)"; \
	gcloud compute instances list --filter="name~solana-dev-node" $$PROJECT_ARG \
		--format="table(name,creationTimestamp)" 2>/dev/null | \
		tail -n +2 | while read line; do \
			INSTANCE=$$(echo $$line | awk '{print $$1}'); \
			CREATED=$$(echo $$line | awk '{print $$2}'); \
			if [ -n "$$CREATED" ] && [ "$$CREATED" != "CREATION_TIMESTAMP" ]; then \
				DATE_PART=$$(echo $$CREATED | cut -dT -f1); \
				TIME_PART=$$(echo $$CREATED | cut -dT -f2 | cut -d. -f1 | cut -d- -f1); \
				CLEAN_DATE="$${DATE_PART} $${TIME_PART}"; \
				CREATED_TS=$$(date -d "$$CLEAN_DATE" +%s 2>/dev/null); \
				NOW_TS=$$(date +%s); \
				HOURS=$$(echo "($$NOW_TS - $$CREATED_TS) / 3600" | bc 2>/dev/null || echo "0"); \
				COST=$$(echo "$$HOURS * 0.13" | bc 2>/dev/null || echo "0.13"); \
				echo "  $$INSTANCE: $$HOURS hours × $0.13 = $$COST USD"; \
			fi; \
		done
	@echo ""
	@echo "$(YELLOW)Total actual cost so far:$(NC)"
	@echo "  Storage: 17 USD (estimated monthly)"
	@echo "  Compute: See individual costs above"
	@echo "  Note: Based on e2-standard-2 at $0.13/hour"
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	echo "$(YELLOW)Storage costs (actual):$(NC)"; \
	gcloud compute disks list --filter="name~solana-dev-node" $$PROJECT_ARG \
		--format="table(name,sizeGb,type)" 2>/dev/null || \
		echo "  No disks found"
	@echo ""

logs:
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	FIRST_NODE=$$(gcloud compute instances list --filter="name~solana-dev-node" --format="value(name)" --limit=1 $$PROJECT_ARG 2>/dev/null | head -1); \
	if [ -n "$(NODE)" ]; then \
		LOG_NODE="$(NODE)"; \
	elif [ -n "$$FIRST_NODE" ]; then \
		LOG_NODE="$$FIRST_NODE"; \
	else \
		LOG_NODE=""; \
	fi; \
	if [ -z "$$LOG_NODE" ]; then \
		echo "$(RED)[ERROR] No nodes deployed or could not resolve node$(NC)"; \
		echo "  Check: $(GREEN)make status$(NC)"; \
		echo "  Or specify node: $(GREEN)make logs NODE=solana-dev-node-alpha$(NC)"; \
		exit 1; \
	fi; \
	echo "$(BLUE)Installation logs for $(YELLOW)$$LOG_NODE$(NC)..."; \
	echo "   (Ctrl+C to exit)"; \
	echo ""; \
	gcloud compute ssh $$LOG_NODE --zone=$(ZONE) $$PROJECT_ARG --tunnel-through-iap -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		gcloud compute ssh $$LOG_NODE --zone=$(ZONE) $$PROJECT_ARG -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		(echo "$(RED)[ERROR] Could not connect to node $$LOG_NODE$(NC)" && \
		 echo "  Check node is running: $(GREEN)make status$(NC)" && \
		 echo "  If stopped: $(GREEN)make start$(NC)" && \
		 echo "  Default zone: $(ZONE). Try: make logs ZONE=your-zone" && \
		 exit 1)

smoke-test:
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	SSH_CMD="gcloud compute ssh --zone=$(ZONE) $$PROJECT_ARG"; \
	TIMEOUT=90; \
	run_ssh() { $$SSH_CMD "$$1" --tunnel-through-iap --command="$$2"; }; \
	if command -v timeout >/dev/null 2>&1; then run_ssh() { timeout $$TIMEOUT $$SSH_CMD "$$1" --tunnel-through-iap --command="$$2"; }; fi; \
	if [ -n "$(TEAM)" ]; then \
		SMOKE_NODE="solana-dev-node-$(TEAM)"; \
		echo "$(BLUE)Running smoke test on team $(YELLOW)$(TEAM)$(NC) ($$SMOKE_NODE)...$(NC)"; \
		echo ""; \
		run_ssh $$SMOKE_NODE "sudo -u ubuntu /home/ubuntu/run-smoke-test.sh" || \
			run_ssh $$SMOKE_NODE "/home/ubuntu/run-smoke-test.sh" || \
			(echo "$(RED)[ERROR] Could not run smoke test (timeout or script failed)$(NC)" && echo "Run manually: make ssh TEAM=$(TEAM), then /home/ubuntu/run-smoke-test.sh" && exit 1); \
	elif [ -n "$(NODE)" ]; then \
		echo "$(BLUE)Running smoke test on node $(YELLOW)$(NODE)$(NC)...$(NC)"; \
		echo ""; \
		run_ssh $(NODE) "sudo -u ubuntu /home/ubuntu/run-smoke-test.sh" || \
			run_ssh $(NODE) "/home/ubuntu/run-smoke-test.sh" || \
			(echo "$(RED)[ERROR] Could not run smoke test (timeout or script failed)$(NC)" && echo "Run manually: make ssh NODE=$(NODE), then /home/ubuntu/run-smoke-test.sh" && exit 1); \
	else \
		echo "$(BLUE)Running smoke test on ALL nodes...$(NC)"; \
		echo ""; \
		LIST=$$(gcloud compute instances list --filter="name~solana-dev-node" --format="value(name)" $$PROJECT_ARG 2>/dev/null); \
		if [ -z "$$LIST" ]; then \
			echo "$(RED)[ERROR] No nodes found$(NC). Run: make status"; \
			exit 1; \
		fi; \
		for node in $$LIST; do \
			echo "$(YELLOW)=== $$node ===$(NC)"; \
			run_ssh $$node "sudo -u ubuntu /home/ubuntu/run-smoke-test.sh" || \
				run_ssh $$node "/home/ubuntu/run-smoke-test.sh" || \
				echo "  $(RED)[ERROR] Smoke test failed on $$node (timeout or script error)$(NC)"; \
			echo ""; \
		done; \
		echo "$(GREEN)All smoke tests completed.$(NC)"; \
	fi
	@echo ""

ssh:
	@echo ""
	@PROJECT_ARG=""; [ -n "$(GCP_PROJECT)" ] && PROJECT_ARG="--project=$(GCP_PROJECT)"; \
	if [ -z "$(TEAM)" ] && [ -z "$(NODE)" ]; then \
		FIRST_NODE=$$(gcloud compute instances list --filter="name~solana-dev-node" --format="value(name)" --limit=1 $$PROJECT_ARG 2>/dev/null | head -1); \
		if [ -z "$$FIRST_NODE" ]; then \
			echo "$(RED)[ERROR] No nodes deployed$(NC)"; \
			echo "  Run: $(GREEN)make status$(NC)"; \
			exit 1; \
		fi; \
		echo "$(BLUE)Connecting to first node: $(YELLOW)$$FIRST_NODE$(NC)..."; \
		echo ""; \
		gcloud compute ssh $$FIRST_NODE --zone=$(ZONE) $$PROJECT_ARG --tunnel-through-iap 2>/dev/null || \
			gcloud compute ssh $$FIRST_NODE --zone=$(ZONE) $$PROJECT_ARG 2>/dev/null || \
			(echo "$(RED)[ERROR] Could not connect$(NC)" && echo "  Check: make status" && exit 1); \
	elif [ -n "$(TEAM)" ]; then \
		NODE_NAME="solana-dev-node-$(TEAM)"; \
		echo "$(BLUE)Connecting to $(YELLOW)$$NODE_NAME$(NC)..."; \
		echo ""; \
		gcloud compute ssh $$NODE_NAME --zone=$(ZONE) $$PROJECT_ARG --tunnel-through-iap 2>/dev/null || \
			gcloud compute ssh $$NODE_NAME --zone=$(ZONE) $$PROJECT_ARG 2>/dev/null || \
			(echo "$(RED)[ERROR] Could not connect to team node '$(TEAM)'$(NC)" && \
			 echo "$(YELLOW)Available teams:$(NC)"; \
			 terraform output nodes 2>/dev/null | grep "name" | cut -d'"' -f4 | sed 's/solana-dev-node-//' || echo "  No teams found"; \
			 echo ""; \
			 echo "$(YELLOW)Usage examples:$(NC)"; \
			 echo "  make ssh TEAM=alpha"; \
			 echo "  make ssh TEAM=beta"); \
	elif echo "$(NODE)" | grep -qE '^[0-9]+$$'; then \
		NODE_NAME=$$(terraform output nodes 2>/dev/null | grep -A 5 "\"$(NODE)\"" | grep "name" | cut -d'"' -f4 || echo ""); \
		if [ -n "$$NODE_NAME" ]; then \
			echo "$(BLUE)Connecting to $(YELLOW)$$NODE_NAME$(NC)..."; \
			echo ""; \
			gcloud compute ssh $$NODE_NAME --zone=$(ZONE) $$PROJECT_ARG --tunnel-through-iap 2>/dev/null || \
				gcloud compute ssh $$NODE_NAME --zone=$(ZONE) $$PROJECT_ARG 2>/dev/null || \
				(echo "$(RED)[ERROR] Could not connect to node$(NC)" && \
				 echo "Verify node exists: $(GREEN)make status$(NC)"); \
		else \
			echo "$(RED)[ERROR] Node index $(NODE) not found$(NC)"; \
			echo "$(YELLOW)Available nodes:$(NC)"; \
			terraform output nodes 2>/dev/null | grep -E "name|ip" | sed 's/^[[:space:]]*/  /' || echo "  No nodes deployed"; \
			echo ""; \
			echo "$(YELLOW)Usage examples:$(NC)"; \
			echo "  make ssh NODE=0"; \
			echo "  make ssh NODE=1"; \
			echo "  make ssh TEAM=alpha"; \
			echo "  make ssh TEAM=beta"; \
		fi; \
	else \
		if [ -n "$$(terraform output nodes 2>/dev/null | grep -A 10 "$(NODE)" | grep "name")" ]; then \
			echo "$(BLUE)Connecting to $(YELLOW)$(NODE)$(NC)..."; \
			echo ""; \
			gcloud compute ssh $(NODE) --zone=$(ZONE) $$PROJECT_ARG --tunnel-through-iap 2>/dev/null || \
				gcloud compute ssh $(NODE) --zone=$(ZONE) $$PROJECT_ARG 2>/dev/null || \
				(echo "$(RED)[ERROR] Could not connect to node$(NC)" && \
				 echo "Verify node exists: $(GREEN)make status$(NC)"); \
		else \
			echo "$(RED)[ERROR] Node '$(NODE)' not found$(NC)"; \
			echo "$(YELLOW)Available nodes:$(NC)"; \
			terraform output nodes 2>/dev/null | grep -E "name|ip" | sed 's/^[[:space:]]*/  /' || echo "  No nodes deployed"; \
			echo ""; \
			echo "$(YELLOW)Usage examples:$(NC)"; \
			echo "  make ssh TEAM=alpha"; \
			echo "  make ssh TEAM=beta"; \
			echo "  make ssh NODE=0"; \
			echo "  make ssh NODE=1"; \
			echo "  make ssh NODE=solana-dev-node-alpha"; \
		fi; \
	fi

#==============================================================================
# ACCESS CONTROL
#==============================================================================

access:
	@echo ""
	@echo "$(BLUE)Team Configuration Management:$(NC)"
	@echo ""
	@if [ ! -f "config/access.yaml" ]; then \
		echo "$(YELLOW)[INFO] No access.yaml found. Creating template...$(NC)"; \
		echo ""; \
		echo "# Team Configuration for Solana Nodes" > config/access.yaml; \
		echo "teams:" >> config/access.yaml; \
		echo "  alpha:" >> config/access.yaml; \
		echo "    users:" >> config/access.yaml; \
		echo "      - \"dev1@company.com\"" >> config/access.yaml; \
		echo "      - \"dev2@company.com\"" >> config/access.yaml; \
		echo "  beta:" >> config/access.yaml; \
		echo "    users:" >> config/access.yaml; \
		echo "      - \"dev3@company.com\"" >> config/access.yaml; \
		echo "      - \"dev4@company.com\"" >> config/access.yaml; \
		echo ""; \
		echo "$(GREEN)[OK] Template created in config/access.yaml$(NC)"; \
		echo "Edit the file and run 'make plan' to see changes."; \
	else \
		echo "$(GREEN)Current team configuration:$(NC)"; \
		echo ""; \
		if command -v yq >/dev/null 2>&1; then \
			echo "Teams and nodes:"; \
			yq e '.teams | to_entries | .[] | "Team: \(.key) | Node: solana-dev-node-\(.key) | Users: \(.value.users | length) users"' config/access.yaml 2>/dev/null || echo "  Could not parse YAML"; \
			echo ""; \
			echo "Users per team:"; \
			yq e '.teams | to_entries | .[] | .value.users[] | "  - \(.)"' config/access.yaml 2>/dev/null; \
			echo ""; \
			echo "Total nodes to deploy: $$(yq e '.teams | length' config/access.yaml 2>/dev/null || echo "1")"; \
		else \
			echo "  Install 'yq' for better formatting or view config/access.yaml directly"; \
		fi; \
		echo ""; \
		echo "$(YELLOW)To apply changes:$(NC)"; \
		echo "  1. Edit config/access.yaml"; \
		echo "  2. Run: $(GREEN)make plan$(NC)"; \
		echo "  3. Run: $(GREEN)make deploy$(NC)"; \
	fi
	@echo ""

#==============================================================================
# CLEANUP
#==============================================================================

clean:
	@echo ""
	@echo "$(BLUE)Cleaning Terraform temporary files...$(NC)"
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@echo "$(GREEN)[OK] Cleanup complete$(NC)"
	@echo ""
	@echo "$(YELLOW)Note:$(NC) This only removes local files."
	@echo "To remove infrastructure in GCP: $(GREEN)make destroy$(NC)"
	@echo ""