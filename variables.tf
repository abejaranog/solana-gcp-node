variable "project_id" {
  description = "ID del proyecto de Google Cloud"
  type        = string
}

variable "region" {
  description = "Región de GCP"
  type        = string
  default     = "europe-southwest1" # Madrid (Ideal para Superteam Spain)
}

variable "zone" {
  description = "Zona de GCP"
  type        = string
  default     = "europe-southwest1-a"
}

variable "machine_type" {
  description = "Tipo de máquina (Solana requiere al menos 64GB RAM para validador completo, 16GB para dev)"
  type        = string
  default     = "n2-standard-16" # 16 vCPU, 64GB RAM
}

variable "enable_iap_ssh" {
  description = "Habilitar SSH seguro via IAP (true) o SSH abierto a internet (false). Recomendado: true"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs permitidos para SSH cuando enable_iap_ssh=false. Ejemplo: ['1.2.3.4/32']"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_count" {
  description = "Número de nodos Solana a desplegar"
  type        = number
  default     = 1
  validation {
    condition     = var.node_count > 0 && var.node_count <= 10
    error_message = "node_count debe estar entre 1 y 10"
  }
}