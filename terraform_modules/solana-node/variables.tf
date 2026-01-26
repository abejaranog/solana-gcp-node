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

variable "network_name" {
  description = "VPC name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet CIDR"
  type        = string
}

variable "node_name" {
  description = "Node name"
  type        = string
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
