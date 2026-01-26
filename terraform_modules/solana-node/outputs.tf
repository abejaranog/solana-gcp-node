output "instance_name" {
  description = "Nombre de la instancia"
  value       = google_compute_instance.solana_node.name
}

output "instance_ip" {
  description = "IP pública de la instancia"
  value       = google_compute_instance.solana_node.network_interface.0.access_config.0.nat_ip
}

output "instance_zone" {
  description = "Zona de la instancia"
  value       = google_compute_instance.solana_node.zone
}
