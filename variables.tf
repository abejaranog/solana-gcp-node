variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "GCP region where resources will be deployed. Common options: europe-west1 (Belgium), europe-west4 (Netherlands), europe-southwest1 (Madrid), us-central1 (Iowa), us-east1 (South Carolina), us-west1 (Oregon)"
  type        = string
  default     = "europe-southwest1" # Madrid (Ideal for Superteam Spain)
  validation {
    condition = contains([
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "europe-west8", "europe-west9", "europe-west10", "europe-west12",
      "europe-central2", "europe-north1", "europe-southwest1",
      "us-central1", "us-east1", "us-east4", "us-east5", "us-west1", "us-west2", "us-west3", "us-west4",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2",
      "southamerica-east1", "southamerica-west1",
      "australia-southeast1", "australia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region. Common options: europe-west1, europe-west4, europe-southwest1, us-central1, us-east1, us-west1"
  }
}

variable "zone" {
  description = "GCP zone within the selected region. Must match the region (e.g., if region=europe-west1, zone should be europe-west1-a, europe-west1-b, or europe-west1-c)"
  type        = string
  default     = "europe-soutwhwest1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., europe-west1-b, us-central1-a, europe-southwest1-a). Ensure the zone belongs to the selected region."
  }
}

variable "machine_type" {
  description = "Machine type for Solana nodes. Recommended: e2-standard-2 (2 vCPU, 8GB RAM) for dev, e2-standard-4 (4 vCPU, 16GB RAM) for heavier workloads, n2-standard-8 (8 vCPU, 32GB RAM) or n2-standard-16 (16 vCPU, 64GB RAM) for production validators"
  type        = string
  default     = "e2-standard-2" # 2 vCPU, 8GB RAM
  validation {
    condition = can(regex("^(e2-standard|e2-highmem|e2-highcpu|n2-standard|n2-highmem|n2-highcpu|n1-standard|n1-highmem|n1-highcpu|c2-standard|c2d-standard)-[0-9]+$", var.machine_type))
    error_message = "Machine type must be a valid GCP machine type format (e.g., e2-standard-2, e2-standard-4, n2-standard-8, n2-standard-16). Common families: e2-standard (balanced), n2-standard (Intel Cascade Lake), n1-standard (Skylake)."
  }
}

variable "enable_iap_ssh" {
  description = "Enable secure SSH via IAP (true) or open SSH to internet (false). Recommended: true"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "Allowed CIDRs for SSH when enable_iap_ssh=false. Example: ['1.2.3.4/32']"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_count" {
  description = "Number of Solana nodes to deploy"
  type        = number
  default     = 1
  validation {
    condition     = var.node_count > 0 && var.node_count <= 10
    error_message = "node_count must be between 1 and 10"
  }
}