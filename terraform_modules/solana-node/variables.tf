variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "zone" {
  description = "GCP zone"
  type        = string
}

variable "node_count" {
  description = "Number of nodes to create"
  type        = number
  default     = 1
}

variable "access_config" {
  description = "Access configuration from main.tf"
  type = object({
    teams = map(object({
      users = list(string)
    }))
    services = map(object({
      enabled = bool
      description = string
    }))
    settings = map(string)
  })
  default = {
    teams = {}
    services = {}
    settings = {}
  }
}

variable "machine_type" {
  description = "Machine type"
  type        = string
}

variable "enable_iap_ssh" {
  description = "Enable SSH via IAP"
  type        = bool
}

variable "allowed_ssh_cidrs" {
  description = "Allowed CIDRs for SSH when IAP is disabled"
  type        = list(string)
}
