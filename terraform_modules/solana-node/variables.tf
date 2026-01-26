variable "project_id" {
  description = "ID del proyecto de Google Cloud"
  type        = string
}

variable "region" {
  description = "Región de GCP"
  type        = string
}

variable "zone" {
  description = "Zona de GCP"
  type        = string
}

variable "network_name" {
  description = "Nombre de la VPC"
  type        = string
}

variable "subnet_name" {
  description = "Nombre de la subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR de la subnet"
  type        = string
}

variable "node_name" {
  description = "Nombre del nodo"
  type        = string
}

variable "machine_type" {
  description = "Tipo de máquina"
  type        = string
}

variable "enable_iap_ssh" {
  description = "Habilitar SSH via IAP"
  type        = bool
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs permitidos para SSH cuando IAP está deshabilitado"
  type        = list(string)
}
