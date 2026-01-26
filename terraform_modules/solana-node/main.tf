resource "google_compute_instance" "solana_node" {
  name         = var.node_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 500
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = var.subnet_name
    access_config {
      # Ephemeral public IP
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = file("${path.root}/scripts/setup-solana.sh")

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
