# Makefile - Solana GCP Node Blueprint
# Step-by-step guide for users without infrastructure experience

.PHONY: help install init check deploy plan destroy ssh logs smoke-test status clean access

# Variables (you can override: make ssh NODE=solana-dev-node-01)
ZONE ?= europe-southwest1-a
NODE ?= solana-dev-node-00
TERRAFORM_VERSION ?= 1.8.5
NODE_COUNT ?= 1

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
	@echo "$(GREEN)MONITORING:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make status$(NC)       - Show deployed nodes status"
	@echo "  $(YELLOW)make logs$(NC)         - View installation logs (first node or NODE=name)"
	@echo "  $(YELLOW)make smoke-test$(NC)   - Run smoke test on all nodes or NODE=name"
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
	@echo "$(BLUE)║                  DEPLOYING SOLANA NODES                        ║$(NC)"
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
	@terraform apply -auto-approve -refresh=false || (echo "$(YELLOW)[INFO] Syncing state after provider bug...$(NC)" && terraform refresh && terraform apply -auto-approve -refresh=false)
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
	@gcloud compute instances list --filter="name~solana-dev-node" \
		--format="table(name,status,zone,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" 2>/dev/null || \
		(echo "$(YELLOW)No nodes deployed yet.$(NC)" && \
		 echo "Run: $(GREEN)make deploy$(NC)")
	@echo ""

costs:
	@echo ""
	@echo "$(BLUE)Actual cost breakdown for Solana nodes:$(NC)"
	@echo ""
	@echo "$(YELLOW)Compute Instances (REAL USAGE):$(NC)"
	@gcloud compute instances list --filter="name~solana-dev-node" \
		--format="table(name,machineType,zone,status,creationTimestamp)" 2>/dev/null || \
		echo "  No instances found"
	@echo ""
	@echo "$(YELLOW)Actual hourly cost based on uptime:$(NC)"
	@gcloud compute instances list --filter="name~solana-dev-node" \
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
	@echo "$(YELLOW)Storage costs (actual):$(NC)"
	@gcloud compute disks list --filter="name~solana-dev-node" \
		--format="table(name,sizeGb,type)" 2>/dev/null || \
		echo "  No disks found"
	@echo ""

logs:
	@echo ""
	@if [ -n "$(NODE)" ] && [ "$(NODE)" != "solana-dev-node-00" ]; then \
		echo "$(BLUE)Installation logs for node $(YELLOW)$(NODE)$(NC)...$(NC)"; \
		echo "   (Press Ctrl+C to exit)"; \
		echo ""; \
		gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap -- tail -f /var/log/solana-setup.log 2>/dev/null || \
			gcloud compute ssh $(NODE) --zone=$(ZONE) -- tail -f /var/log/solana-setup.log 2>/dev/null || \
			(echo "$(RED)[ERROR] Could not connect to node$(NC)" && \
			 echo "Verify it exists: $(GREEN)make status$(NC)"); \
	else \
		echo "$(BLUE)Installation logs for first node...$(NC)"; \
		echo "   (Press Ctrl+C to exit)"; \
		echo ""; \
		gcloud compute ssh solana-dev-node-alpha --zone=$(ZONE) --tunnel-through-iap -- tail -f /var/log/solana-setup.log 2>/dev/null || \
			echo "$(RED)[ERROR] Could not connect to first node$(NC)"; \
	fi

smoke-test:
	@echo ""
	@if [ -n "$(NODE)" ] && [ "$(NODE)" != "solana-dev-node-00" ]; then \
		echo "$(BLUE)Running smoke test on node $(YELLOW)$(NODE)$(NC)...$(NC)"; \
		echo ""; \
		gcloud compute ssh $(NODE) --zone=$(ZONE) --command="sudo /home/ubuntu/run-smoke-test.sh" 2>/dev/null || \
			(gcloud compute ssh $(NODE) --zone=$(ZONE) --command="/home/ubuntu/run-smoke-test.sh" 2>/dev/null || \
			(echo "$(RED)[ERROR] Could not run smoke test$(NC)" && \
			 echo "Verify node exists: $(GREEN)make status$(NC)")); \
	else \
		echo "$(BLUE)Running smoke test on ALL nodes...$(NC)"; \
		echo ""; \
		for node in $$(terraform output nodes 2>/dev/null | grep "name" | cut -d'"' -f4 | head -5); do \
			echo "$(YELLOW)=== $$node ===$(NC)"; \
			gcloud compute ssh $$node --zone=$(ZONE) --command="sudo /home/ubuntu/run-smoke-test.sh" 2>/dev/null || \
				(gcloud compute ssh $$node --zone=$(ZONE) --command="/home/ubuntu/run-smoke-test.sh" 2>/dev/null || \
				echo "  $(RED)[ERROR] Could not run smoke test on $$node$(NC)"); \
			echo ""; \
		done; \
		echo "$(GREEN)All smoke tests completed!$(NC)"; \
	fi
	@echo ""

ssh:
	@echo ""
	@echo "$(BLUE)Connecting to $(YELLOW)$(NODE)$(NC)...$(NC)"
	@echo ""
	@if [ -n "$(TEAM)" ]; then \
		NODE_NAME="solana-dev-node-$(TEAM)"; \
		echo "$(YELLOW)[INFO] Connecting to team node: $$NODE_NAME$(NC)"; \
		gcloud compute ssh $$NODE_NAME --zone=$(ZONE) --tunnel-through-iap 2>/dev/null || \
			gcloud compute ssh $$NODE_NAME --zone=$(ZONE) 2>/dev/null || \
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
			echo "$(YELLOW)[INFO] Resolved node $(NODE) to: $$NODE_NAME$(NC)"; \
			gcloud compute ssh $$NODE_NAME --zone=$(ZONE) --tunnel-through-iap 2>/dev/null || \
				gcloud compute ssh $$NODE_NAME --zone=$(ZONE) 2>/dev/null || \
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
			gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap 2>/dev/null || \
				gcloud compute ssh $(NODE) --zone=$(ZONE) 2>/dev/null || \
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