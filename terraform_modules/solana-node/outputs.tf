output "instances" {
  description = "All deployed instances"
  value = {
    for i, instance in google_compute_instance.solana_node : i => {
      name = instance.name
      ip   = instance.network_interface[0].access_config[0].nat_ip
      zone = instance.zone
      rpc  = "http://${instance.network_interface[0].access_config[0].nat_ip}:8899"
      ws   = "ws://${instance.network_interface[0].access_config[0].nat_ip}:8900"
    }
  }
}

output "instance_name" {
  description = "Instance name (single instance for compatibility)"
  value       = google_compute_instance.solana_node[0].name
}

output "instance_ip" {
  description = "Instance public IP (single instance for compatibility)"
  value       = google_compute_instance.solana_node[0].network_interface[0].access_config[0].nat_ip
}

output "instance_zone" {
  description = "Instance zone (single instance for compatibility)"
  value       = google_compute_instance.solana_node[0].zone
}
