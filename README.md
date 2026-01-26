# Solana GCP Node Blueprint

**Infrastructure-as-Code para desplegar nodos de desarrollo Solana en Google Cloud Platform.**

Este blueprint resuelve ese problema: de 2+ horas de setup manual a **10 minutos automatizados**.

---

## Por qué este proyecto existe

**Problema:** Configurar un nodo Solana no es solo `apt install solana`. Requiere kernel tuning específico (UDP buffers, file descriptors), toolchain completo (Rust, Anchor, Node.js), y conocimiento de las particularidades del protocolo.

**Solución:** Terraform modular + startup script idempotente que aplica las optimizaciones correctas desde el primer boot.

**Impacto:**
- **Developer Tooling:** Reduce fricción de onboarding a Solana
- **Censorship Resistance:** Facilita diversificación geográfica (incluye región Madrid)
- **Reproducibilidad:** Infraestructura versionada, auditable

---

## Arquitectura

```
.
├── main.tf                          # Orquestador: VPC, firewall, módulos
├── variables.tf                     # Configuración centralizada
├── outputs.tf                       # Endpoints y comandos útiles
├── terraform_modules/
│   └── solana-node/                 # Módulo reutilizable
│       ├── main.tf                  # Definición de instancia
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    └── setup-solana.sh              # Startup script (kernel + software)
```

**Decisiones de diseño:**

1. **Modularización:** El módulo `solana-node` es reutilizable. Puedes desplegar N nodos cambiando `node_count`.

2. **Default Service Account:** Uso la SA por defecto de GCE en lugar de crear una custom. Razón: simplicidad > over-engineering. Para dev nodes, los permisos por defecto son suficientes.

3. **Dual SSH Mode:** IAP (seguro) vs directo (rápido). El primero es default, el segundo existe para troubleshooting o entornos donde IAP no está disponible.

4. **Startup Script Idempotente:** Todo el tuning se aplica en boot. Si la instancia se recrea, el entorno es idéntico.

---

## Especificaciones Técnicas

| Componente | Configuración | Justificación |
|------------|---------------|---------------|
| **Compute** | `n2-standard-16` (16 vCPU, 64GB RAM) | Mínimo para test-validator sin lag |
| **Storage** | 500GB SSD (`pd-ssd`) | IOPS consistente para ledger I/O |
| **OS** | Ubuntu 22.04 LTS | Soporte largo + compatibilidad Solana |
| **Región** | `europe-southwest1` (Madrid) | Diversificación geográfica EU |

### Kernel Tuning (crítico para Solana)

```bash
net.core.rmem_max=134217728          # UDP RX buffer: 128MB
net.core.wmem_max=134217728          # UDP TX buffer: 128MB
vm.max_map_count=1000000             # Memory maps para ledger
nofile=1000000                       # File descriptors
```

**Por qué:** El protocolo Solana usa UDP para gossip/TPU. Buffers pequeños = packet loss = degradación de red.

### Stack Completo

- **Rust** (stable): Compilador para programas Solana
- **Solana CLI** (stable): Herramientas de línea de comandos
- **Anchor Framework** (latest): Framework de desarrollo más usado
- **Node.js 20 LTS + Yarn**: Para tests de integración
- **Utilidades:** jq (JSON parsing), fio (disk benchmarking)

---

## Prerrequisitos

Necesitas tres cosas:

1. **Proyecto GCP activo** con billing habilitado
2. **gcloud CLI** autenticado:
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```
3. **Terraform** >= 1.8.5

Las APIs necesarias (Compute Engine, IAP) se habilitan automáticamente.

**Versiones fijadas:**
- Terraform: `>= 1.8.5` (compatible con versiones superiores)
- Google Provider: `~> 7.16` (7.16.x, patches automáticos, sin breaking changes)

---

## Inicio Rápido

### Primera vez (flujo guiado paso a paso)

El Makefile te guía en todo el proceso. Si nunca has usado Terraform o GCP, simplemente ejecuta:

```bash
git clone https://github.com/TU_USUARIO/solana-gcp-node
cd solana-gcp-node

# Ver ayuda completa
make help

# Paso 1: Verificar que tienes todo instalado
make check

# Paso 2: Configurar tu proyecto GCP
export TF_VAR_project_id="your-gcp-project"
make init

# Paso 3: Desplegar (crea VPC, firewall, nodo Solana)
make deploy
```

**¿Qué se crea?**
- VPC dedicada (`10.0.0.0/24`)
- Firewall rules (SSH via IAP, RPC/WS abiertos)
- 1 nodo Solana con 64GB RAM, 500GB SSD

**Tiempo:** ~2 minutos infraestructura + ~8-10 minutos instalación de software

### Monitorear el progreso

Mientras el nodo se configura:

```bash
# Ver logs de instalación en tiempo real
make logs

# Ver estado del nodo
make status
```

### Verificar que todo funciona

```bash
make smoke-test
```

Esto valida:
- ✓ Rust, Solana CLI, Anchor instalados
- ✓ Kernel tuning aplicado (UDP buffers, file limits)
- ✓ `solana-test-validator` arranca y responde
- ✓ Airdrop funciona

### Conectar al nodo

```bash
make ssh
```

Usa IAP tunnel (seguro, zero-config).

---

## Configuración Avanzada

### Desplegar múltiples nodos

```bash
export TF_VAR_node_count=3
make deploy
```

Los nodos se nombran `solana-dev-node-00`, `solana-dev-node-01`, etc.

Ver todos los nodos:

```bash
terraform output nodes
```

Conectar a un nodo específico:

```bash
make ssh NODE=solana-dev-node-02
```

### SSH abierto (desarrollo rápido)

Si IAP te genera fricción (debugging, CI/CD, etc.), puedes usar SSH directo:

```bash
export TF_VAR_enable_iap_ssh=false
make deploy
```

**Advertencia:** Esto expone puerto 22 a internet. Solo para desarrollo temporal.

Para restringir a tu IP:

```bash
export TF_VAR_enable_iap_ssh=false
export TF_VAR_allowed_ssh_cidrs='["203.0.113.42/32"]'
make deploy
```

### Cambiar región/máquina

```bash
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"
export TF_VAR_machine_type="n2-standard-8"  # 8 vCPU, 32GB RAM
make deploy
```

---

## Comandos Disponibles

### Primeros Pasos
| Comando | Descripción |
|---------|-------------|
| `make help` | Muestra ayuda completa con guía paso a paso |
| `make check` | Verifica prerrequisitos (Terraform, gcloud) |
| `make init` | Configura proyecto GCP e inicializa Terraform |
| `make plan` | Previsualiza cambios sin aplicarlos |
| `make deploy` | Despliega infraestructura completa |

### Monitoreo
| Comando | Descripción |
|---------|-------------|
| `make status` | Lista todos los nodos con estado e IPs |
| `make logs` | Ver logs de instalación en tiempo real |
| `make smoke-test` | Ejecuta validación end-to-end |

### Acceso
| Comando | Descripción |
|---------|-------------|
| `make ssh` | Conecta al primer nodo |
| `make ssh NODE=solana-dev-node-01` | Conecta a nodo específico |

### Limpieza
| Comando | Descripción |
|---------|-------------|
| `make destroy` | Elimina toda la infraestructura (pide confirmación) |
| `make clean` | Limpia archivos temporales de Terraform |

---

## Seguridad

### Modelo de amenazas

Este blueprint está diseñado para **entornos de desarrollo**, no producción. Asunciones:

- **Nodos efímeros:** Se crean/destruyen frecuentemente
- **Sin datos sensibles:** No hay claves privadas de mainnet
- **Red pública:** RPC/WS necesitan ser accesibles desde internet para desarrollo

### SSH: Dos modos

| Modo | Configuración | Cuándo usarlo |
|------|---------------|---------------|
| **IAP (default)** | `enable_iap_ssh=true` | Desarrollo normal, demos, ambientes compartidos |
| **Directo** | `enable_iap_ssh=false` | Debugging, CI/CD, troubleshooting |

**IAP (Identity-Aware Proxy):**
- Puerto 22 **no expuesto** a internet
- Requiere autenticación GCP
- `gcloud compute ssh` maneja el tunnel automáticamente
- Zero-config para el usuario

**SSH directo:**
- Puerto 22 abierto (configurable via `allowed_ssh_cidrs`)
- Útil cuando IAP no está disponible
- **Solo para desarrollo temporal**

### RPC/WebSocket

Puertos 8899/8900 están abiertos a `0.0.0.0/0` en ambos modos. Esto es intencional para facilitar desarrollo.

**Para producción:** Usa Cloud Armor, VPC peering, o VPN.

### Service Account

Uso la **default compute service account** en lugar de crear una custom. Razones:

1. **Simplicidad:** Menos recursos que gestionar
2. **Permisos suficientes:** Para dev nodes, los permisos por defecto cubren todo (Compute, Logging, Monitoring)
3. **Menos fricción:** No requiere IAM bindings adicionales

Si necesitas permisos custom, modifica `terraform_modules/solana-node/main.tf`.

---

## Smoke Test

Script de validación que ejecuta:

```bash
1. Verificar versiones (Rust, Solana, Anchor, Node)
2. Validar kernel tuning (UDP buffers >= 128MB)
3. Arrancar test-validator
4. Esperar RPC ready (max 30s)
5. Airdrop 5 SOL a keypair temporal
6. Cleanup
```

Si falla, revisa `/var/log/solana-setup.log` en la instancia.

---

## Estructura del Proyecto

```
.
├── main.tf                          # Orquestador principal
├── variables.tf                     # Configuración
├── outputs.tf                       # Info post-deploy
├── Makefile                         # Comandos helper
├── terraform_modules/
│   └── solana-node/                 # Módulo reutilizable
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── scripts/
    └── setup-solana.sh              # Startup script (175 líneas)
```

**Filosofía:** Modularidad sin over-engineering. El módulo `solana-node` es reutilizable pero simple.

---

## Troubleshooting

### El startup script falla

```bash
# Ver logs completos
make logs

# SSH y revisar manualmente
make ssh
tail -f /var/log/solana-setup.log
```

Causas comunes:
- Timeout descargando Rust/Solana (red lenta)
- Anchor build falla (falta memoria - usa `n2-standard-16` mínimo)

### IAP no funciona

```bash
# Verificar que la API está habilitada
gcloud services list --enabled | grep iap

# Si no, habilitar manualmente
gcloud services enable iap.googleapis.com
```

### Quiero cambiar de IAP a SSH directo (o viceversa)

```bash
export TF_VAR_enable_iap_ssh=false  # o true
terraform apply
```

Terraform actualizará solo el firewall rule.

---

## Costos Estimados

Basado en `n2-standard-16` en `europe-southwest1`:

| Recurso | Coste/hora | Coste/mes (730h) |
|---------|------------|------------------|
| Compute (n2-standard-16) | ~$0.78 | ~$569 |
| Storage (500GB SSD) | ~$0.023 | ~$17 |
| **Total** | **~$0.80** | **~$586** |

**Tip:** Usa `make destroy` cuando no estés desarrollando. Recrear el nodo tarda 10 minutos.

---

## Roadmap

- [ ] Cloud Monitoring dashboards (CPU, disk, network)
- [ ] Soporte para snapshots automáticos
- [ ] Opción de disco NVMe local (mayor IOPS)
- [ ] Multi-región (HA setup)

---

## Licencia

MIT

---

## Autor

Desarrollado por un CTO con 9 años de experiencia en infraestructura cloud y blockchain. 

Si este proyecto te ahorra tiempo, considera:
- ⭐ Star en GitHub
- � Reportar issues
- 🔧 Contribuir mejoras
