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

# === APIs ===

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iap" {
  count              = var.enable_iap_ssh ? 1 : 0
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# === NETWORKING ===

resource "google_compute_network" "solana_vpc" {
  name                    = "solana-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "solana_subnet" {
  name          = "solana-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.solana_vpc.id
  region        = var.region
}

# === FIREWALL ===

resource "google_compute_firewall" "ssh" {
  name    = "solana-ssh"
  network = google_compute_network.solana_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.enable_iap_ssh ? ["35.235.240.0/20"] : var.allowed_ssh_cidrs
  target_tags   = ["solana-node"]
}

resource "google_compute_firewall" "solana_rpc" {
  name    = "solana-rpc"
  network = google_compute_network.solana_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8899", "8900"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["solana-node"]
}

resource "google_compute_firewall" "solana_gossip" {
  name    = "solana-gossip"
  network = google_compute_network.solana_vpc.name

  allow {
    protocol = "udp"
    ports    = ["8000-8020"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["solana-node"]
}

# === SOLANA NODES ===

module "solana_nodes" {
  source   = "./terraform_modules/solana-node"
  for_each = toset([for i in range(var.node_count) : format("%02d", i)])

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  network_name = google_compute_network.solana_vpc.name
  subnet_name  = google_compute_subnetwork.solana_subnet.name
  subnet_cidr  = "10.0.0.0/24"

  node_name    = "solana-dev-node-${each.key}"
  machine_type = var.machine_type

  enable_iap_ssh    = var.enable_iap_ssh
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
}