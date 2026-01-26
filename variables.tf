variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-southwest1" # Madrid (Ideal for Superteam Spain)
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-southwest1-a"
}

variable "machine_type" {
  description = "Machine type (Solana requires at least 64GB RAM for full validator, 16GB for dev)"
  type        = string
  default     = "n2-standard-16" # 16 vCPU, 64GB RAM
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