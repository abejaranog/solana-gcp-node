output "nodes" {
  description = "Information about all deployed nodes"
  value = {
    for k, v in module.solana_nodes : k => {
      name = v.instance_name
      ip   = v.instance_ip
      zone = v.instance_zone
      rpc  = "http://${v.instance_ip}:8899"
      ws   = "ws://${v.instance_ip}:8900"
    }
  }
}

output "ssh_commands" {
  description = "SSH commands for each node"
  value = {
    for k, v in module.solana_nodes : k => var.enable_iap_ssh ? 
      "gcloud compute ssh ${v.instance_name} --zone=${v.instance_zone} --tunnel-through-iap" : 
      "gcloud compute ssh ${v.instance_name} --zone=${v.instance_zone}"
  }
}

output "summary" {
  description = "Deployment summary"
  value       = <<-EOT
    
    ========================================
    SOLANA DEV NODES - DEPLOYED
    ========================================
    
    Nodes deployed: ${var.node_count}
    SSH Mode: ${var.enable_iap_ssh ? "SECURE (IAP)" : "OPEN"}
    Region: ${var.region}
    
    NEXT STEPS:
    
    1. Startup script takes ~8-10 minutes.
       View first node progress:
       $ make logs
    
    2. Run smoke test:
       $ make smoke-test
    
    3. Connect to first node:
       $ make ssh
    
    4. View all nodes:
       $ terraform output nodes
    
    SECURITY:
    ${var.enable_iap_ssh ? "[SECURE] SSH protected via IAP" : "[WARNING] SSH OPEN - Development only"}
    [WARNING] RPC/WS open (0.0.0.0/0) - DEVELOPMENT ONLY
    
  EOT
}