output "instance_name" {
  description = "Instance name"
  value       = google_compute_instance.solana_node.name
}

output "instance_ip" {
  description = "Instance public IP"
  value       = google_compute_instance.solana_node.network_interface.0.access_config.0.nat_ip
}

output "instance_zone" {
  description = "Instance zone"
  value       = google_compute_instance.solana_node.zone
}
