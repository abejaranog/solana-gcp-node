output "nodes" {
  description = "Información de todos los nodos desplegados"
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
  description = "Comandos SSH para cada nodo"
  value = {
    for k, v in module.solana_nodes : k => var.enable_iap_ssh ?
    "gcloud compute ssh ${v.instance_name} --zone=${v.instance_zone} --tunnel-through-iap" :
    "gcloud compute ssh ${v.instance_name} --zone=${v.instance_zone}"
  }
}

output "summary" {
  description = "Resumen del despliegue"
  value       = <<-EOT
    
    ========================================
    SOLANA DEV NODES - DESPLEGADOS
    ========================================
    
    Nodos desplegados: ${var.node_count}
    Modo SSH: ${var.enable_iap_ssh ? "SEGURO (IAP)" : "ABIERTO"}
    Región: ${var.region}
    
    PRÓXIMOS PASOS:
    
    1. El startup script tarda ~8-10 minutos.
       Ver progreso del primer nodo:
       $ make logs
    
    2. Ejecutar smoke test:
       $ make smoke-test
    
    3. Conectar al primer nodo:
       $ make ssh
    
    4. Ver todos los nodos:
       $ terraform output nodes
    
    ⚠️  SEGURIDAD:
    ${var.enable_iap_ssh ? "✓ SSH protegido via IAP" : "⚠ SSH ABIERTO - Solo desarrollo"}
    ⚠ RPC/WS abiertos (0.0.0.0/0) - SOLO DESARROLLO
    
  EOT
}