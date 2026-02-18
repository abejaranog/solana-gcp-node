# APIs
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iap" {
  count              = var.enable_iap_ssh ? 1 : 0
  project            = var.project_id
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# Networking
resource "google_compute_network" "solana_vpc" {
  project                 = var.project_id
  name                    = "solana-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "solana_subnet" {
  project       = var.project_id
  name          = "solana-subnet"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.solana_vpc.id
  region        = var.region
}

# Firewall
resource "google_compute_firewall" "ssh" {
  project = var.project_id
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
  project = var.project_id
  name    = "solana-rpc"
  network = google_compute_network.solana_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8899"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["solana-node"]
}

resource "google_compute_firewall" "solana_gossip" {
  project = var.project_id
  name    = "solana-gossip"
  network = google_compute_network.solana_vpc.name

  allow {
    protocol = "udp"
    ports    = ["8000-8020"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["solana-node"]
}

# Data source for Project Info
data "google_project" "project" {
  project_id = var.project_id
}

# Access Control Logic
locals {
  # Use passed access_config instead of reading file
  access_config = var.access_config
  
  # Filter teams with users only
  valid_teams = {
    for team_key, team_config in local.access_config.teams : 
      team_key => team_config 
      if length(team_config.users) > 0
  }
  
  # Calculate node count from valid teams configuration
  calculated_node_count = length(local.valid_teams) > 0 ? length(local.valid_teams) : var.node_count
  
  # Create user permissions from valid teams only (hardcoded permissions)
  user_permissions = flatten([
    for team_key, team_config in local.valid_teams : [
      for user in team_config.users : {
        email      = user
        team_key   = team_key
        node_name  = "solana-dev-node-${team_key}"
      }
    ]
  ])

  # Organization Detection Logic
  # Detecta si el proyecto tiene una ID de organización válida
  org_id = try(data.google_project.project.org_id, null)
  has_organization = local.org_id != null && local.org_id != ""
}

# 1. IAM: Project Viewer
resource "google_project_iam_member" "user_access" {
  for_each = local.access_config.teams != null ? {
    for perm in local.user_permissions : perm.email => perm
  } : {}
  
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "user:${each.value.email}"
  

}

# 2. IAM: IAP Tunnel Access
resource "google_project_iam_member" "user_iap_access" {
  for_each = local.access_config.teams != null ? {
    for perm in local.user_permissions : "${perm.email}-iap" => perm
  } : {}
  
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${each.value.email}"

}

# 3. IAM: Service Account User (NUEVO y OBLIGATORIO)
# Necesario para que OS Login pueda 'impersonalizar' a la VM
resource "google_project_iam_member" "user_sa_user" {
  for_each = local.access_config.teams != null ? {
    for perm in local.user_permissions : "${perm.email}-sa-user" => perm
  } : {}

  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "user:${each.value.email}"
  
  condition {
    title       = "restrict-sa-${each.value.node_name}"
    description = "Allow using Service Account only on assigned team node"
    expression  = "resource.name.endsWith('${each.value.node_name}')"
  }

}

# 4. IAM: OS Login (Standard)
# Se aplica siempre a nivel de proyecto
resource "google_project_iam_member" "user_oslogin" {
  for_each = local.access_config.teams != null ? {
    for perm in local.user_permissions : "${perm.email}-oslogin" => perm
  } : {}
  
  project = var.project_id
  role    = "roles/compute.osLogin" 
  member  = "user:${each.value.email}"
  condition {
    title       = "restrict-oslogin-${each.value.node_name}"
    description = "Allow OS Login only to assigned team node"
    expression  = "resource.name.endsWith('${each.value.node_name}')"
  }

}

# 5. IAM: OS Login External User (Organization Level)
# Solo se aplica si detectamos que EXISTE una organización
resource "google_organization_iam_member" "user_oslogin_external" {
  for_each = (local.access_config.teams != null && local.has_organization) ? {
    for perm in local.user_permissions : "${perm.email}-oslogin-external" => perm
  } : {}
  
  org_id = local.org_id
  role   = "roles/compute.osLoginExternalUser"
  member = "user:${each.value.email}"

}

# Solana Node Instances
resource "google_compute_instance" "solana_node" {
  count = local.calculated_node_count
  
  name = length(local.valid_teams) > 0 ? "solana-dev-node-${keys(local.valid_teams)[count.index]}" : "solana-dev-node-${format("%02d", count.index)}"
  
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.solana_subnet.name
    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
    # Pass configuration to startup script
    config = jsonencode({
      teams    = local.access_config.teams
      services = local.access_config.services
      settings = local.access_config.settings
    })
  }

 
  # Use modular startup script
  metadata_startup_script = fileexists("${path.root}/scripts/setup-modular.sh") ? file("${path.root}/scripts/setup-modular.sh") : file("${path.root}/scripts/setup-solana.sh")

  tags = ["solana-node"]

  labels = {
    environment = "development"
    project     = "solana-node"
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }
}