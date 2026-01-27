# Makefile - Solana GCP Node Blueprint
# Step-by-step guide for users without infrastructure experience

.PHONY: help install init check deploy plan destroy ssh logs smoke-test status clean

# Variables (you can override: make ssh NODE=solana-dev-node-01)
ZONE ?= europe-southwest1-a
NODE ?= solana-dev-node-00
TERRAFORM_VERSION ?= 1.8.5

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
	@echo "  4. $(YELLOW)make deploy$(NC)     - Deploy your Solana node (~10 min)"
	@echo ""
	@echo "$(GREEN)MONITORING:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make status$(NC)       - View status of your nodes"
	@echo "  $(YELLOW)make logs$(NC)         - View installation progress in real-time"
	@echo "  $(YELLOW)make smoke-test$(NC)   - Verify everything works correctly"
	@echo ""
	@echo "$(GREEN)ACCESS:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make ssh$(NC)          - Connect to node via SSH"
	@echo "  $(YELLOW)make ssh NODE=solana-dev-node-01$(NC)  - Connect to specific node"
	@echo ""
	@echo "$(GREEN)CLEANUP:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make destroy$(NC)      - Remove all infrastructure (asks for confirmation)"
	@echo "  $(YELLOW)make clean$(NC)        - Clean Terraform temporary files"
	@echo ""
	@echo "$(BLUE)TIPS:$(NC)"
	@echo "  - If it's your first time, run: make check && make init && make deploy"
	@echo "  - Node takes ~8-10 minutes to be ready after deploy"
	@echo "  - Use 'make logs' to view installation progress"
	@echo "  - Remember to run 'make destroy' when done to avoid costs"
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
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "$(YELLOW)[WARNING] Variable TF_VAR_project_id not configured$(NC)"; \
		echo ""; \
		echo "Configure it with your GCP project ID:"; \
		echo "  $(GREEN)export TF_VAR_project_id=\"your-gcp-project\"$(NC)"; \
		echo ""; \
		echo "To view your projects: $(GREEN)gcloud projects list$(NC)"; \
		echo ""; \
		exit 1; \
	fi
	@echo "$(GREEN)[OK] Project configured:$(NC) $$TF_VAR_project_id"
	@echo ""
	@echo "$(BLUE)Configuring Application Default Credentials...$(NC)"
	@gcloud auth application-default login --quiet 2>/dev/null || \
		(echo "$(YELLOW)Please authenticate with Application Default Credentials:$(NC)" && \
		 gcloud auth application-default login)
	@echo "$(GREEN)[OK] ADC configured$(NC)"
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
	@echo "$(BLUE)║                  DEPLOYING SOLANA NODE                         ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "$(RED)[ERROR] TF_VAR_project_id not configured$(NC)"; \
		echo ""; \
		echo "Run first: $(GREEN)make init$(NC)"; \
		echo ""; \
		exit 1; \
	fi
	@echo "$(YELLOW)Project:$(NC) $$TF_VAR_project_id"
	@echo "$(YELLOW)Nodes to create:$(NC) $${TF_VAR_node_count:-1}"
	@echo ""
	@echo "$(BLUE)Terraform is creating infrastructure...$(NC)"
	@terraform apply -auto-approve
	@echo ""
	@echo "$(GREEN)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                    DEPLOYMENT COMPLETE                         ║$(NC)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)[WAIT] Node is installing software (Rust, Solana, Anchor)...$(NC)"
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
	@gcloud compute instances list --filter="name~solana-dev-node" \
		--format="table(name,status,zone,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" 2>/dev/null || \
		(echo "$(YELLOW)No nodes deployed yet.$(NC)" && \
		 echo "Run: $(GREEN)make deploy$(NC)")
	@echo ""

logs:
	@echo ""
	@echo "$(BLUE)Installation logs for node $(YELLOW)$(NODE)$(NC)..."
	@echo "   (Press Ctrl+C to exit)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		(echo "$(RED)[ERROR] Could not connect to node$(NC)" && \
		 echo "Verify it exists: $(GREEN)make status$(NC)")

smoke-test:
	@echo ""
	@echo "$(BLUE)Running smoke test on $(YELLOW)$(NODE)$(NC)...$(NC)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap -- "cd /home/ubuntu && ./run-smoke-test.sh" 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) -- "cd /home/ubuntu && ./run-smoke-test.sh" 2>/dev/null || \
		(echo "$(RED)[ERROR] Could not run test$(NC)" && \
		 echo "Verify node is ready: $(GREEN)make logs$(NC)")
	@echo ""

ssh:
	@echo ""
	@echo "$(BLUE)Connecting to $(YELLOW)$(NODE)$(NC)...$(NC)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) 2>/dev/null || \
		(echo "$(RED)[ERROR] Could not connect$(NC)" && \
		 echo "Verify node exists: $(GREEN)make status$(NC)")

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