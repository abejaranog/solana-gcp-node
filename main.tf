# Solana GCP Node - Hackathon Deployment
# All resources in module, main.tf just calls it

terraform {
  required_version = ">= 1.8.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.16"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Access configuration
locals {
  access_config = fileexists("${path.root}/config/access.yaml") ? yamldecode(file("${path.root}/config/access.yaml")) : {
    teams = {}
    services = {}
    settings = {}
  }
}

# Deploy Solana nodes (single module call)
module "solana_nodes" {
  source = "./terraform_modules/solana-node"
  
  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  node_count   = var.node_count  # Fallback if no teams
  
  machine_type     = var.machine_type
  enable_iap_ssh   = var.enable_iap_ssh
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  
  # Pass access config to module
  access_config = local.access_config
}
