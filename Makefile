# Makefile - Solana GCP Node Blueprint
# Guía paso a paso para usuarios sin experiencia en infraestructura

.PHONY: help init check deploy plan destroy ssh logs smoke-test status clean

# Variables (puedes sobrescribirlas: make ssh NODE=solana-dev-node-01)
ZONE ?= europe-southwest1-a
NODE ?= solana-dev-node-00

# Colores para mensajes
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

#==============================================================================
# AYUDA - Empieza aquí si es tu primera vez
#==============================================================================

help:
	@echo ""
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║          SOLANA GCP NODE - GUÍA PARA PRINCIPIANTES            ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(GREEN)🚀 PRIMEROS PASOS (ejecuta en orden):$(NC)"
	@echo ""
	@echo "  1. $(YELLOW)make check$(NC)      - Verifica que tienes todo instalado"
	@echo "  2. $(YELLOW)make init$(NC)       - Configura tu proyecto GCP"
	@echo "  3. $(YELLOW)make plan$(NC)       - Previsualiza qué se va a crear (opcional)"
	@echo "  4. $(YELLOW)make deploy$(NC)     - Despliega tu nodo Solana (~10 min)"
	@echo ""
	@echo "$(GREEN)📊 MONITOREO:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make status$(NC)       - Ver estado de tus nodos"
	@echo "  $(YELLOW)make logs$(NC)         - Ver progreso de instalación en tiempo real"
	@echo "  $(YELLOW)make smoke-test$(NC)   - Verificar que todo funciona correctamente"
	@echo ""
	@echo "$(GREEN)🔧 ACCESO:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make ssh$(NC)          - Conectar al nodo por SSH"
	@echo "  $(YELLOW)make ssh NODE=solana-dev-node-01$(NC)  - Conectar a nodo específico"
	@echo ""
	@echo "$(GREEN)🗑️  LIMPIEZA:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make destroy$(NC)      - Eliminar toda la infraestructura (pide confirmación)"
	@echo "  $(YELLOW)make clean$(NC)        - Limpiar archivos temporales de Terraform"
	@echo ""
	@echo "$(BLUE)💡 TIPS:$(NC)"
	@echo "  - Si es tu primera vez, ejecuta: make check && make init && make deploy"
	@echo "  - El nodo tarda ~8-10 minutos en estar listo después del deploy"
	@echo "  - Usa 'make logs' para ver el progreso de instalación"
	@echo "  - Recuerda hacer 'make destroy' cuando termines para no gastar dinero"
	@echo ""

#==============================================================================
# VERIFICACIÓN DE PRERREQUISITOS
#==============================================================================

check:
	@echo ""
	@echo "$(BLUE)🔍 Verificando prerrequisitos...$(NC)"
	@echo ""
	@command -v terraform >/dev/null 2>&1 && \
		echo "$(GREEN)✓ Terraform instalado:$(NC) $$(terraform version | head -n1)" || \
		(echo "$(RED)✗ Terraform NO encontrado$(NC)" && \
		 echo "  Instala desde: https://www.terraform.io/downloads" && exit 1)
	@command -v gcloud >/dev/null 2>&1 && \
		echo "$(GREEN)✓ gcloud CLI instalado:$(NC) $$(gcloud version | head -n1)" || \
		(echo "$(RED)✗ gcloud CLI NO encontrado$(NC)" && \
		 echo "  Instala desde: https://cloud.google.com/sdk/docs/install" && exit 1)
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1 && \
		echo "$(GREEN)✓ gcloud autenticado:$(NC) $$(gcloud auth list --filter=status:ACTIVE --format='value(account)')" || \
		(echo "$(RED)✗ gcloud NO autenticado$(NC)" && \
		 echo "  Ejecuta: gcloud auth login" && exit 1)
	@echo ""
	@echo "$(GREEN)✅ Todos los prerrequisitos están OK$(NC)"
	@echo ""

#==============================================================================
# INICIALIZACIÓN DEL PROYECTO
#==============================================================================

init: check
	@echo ""
	@echo "$(BLUE)🔧 Configurando proyecto...$(NC)"
	@echo ""
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "$(YELLOW)⚠️  Variable TF_VAR_project_id no configurada$(NC)"; \
		echo ""; \
		echo "Configúrala con tu ID de proyecto GCP:"; \
		echo "  $(GREEN)export TF_VAR_project_id=\"tu-proyecto-gcp\"$(NC)"; \
		echo ""; \
		echo "Para ver tus proyectos: $(GREEN)gcloud projects list$(NC)"; \
		echo ""; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Proyecto configurado:$(NC) $$TF_VAR_project_id"
	@echo ""
	@echo "$(BLUE)Inicializando Terraform...$(NC)"
	@terraform init -upgrade
	@echo ""
	@echo "$(GREEN)✅ Inicialización completa$(NC)"
	@echo ""
	@echo "$(YELLOW)Siguiente paso:$(NC) make plan  (para ver qué se va a crear)"
	@echo "            o: make deploy (para desplegar directamente)"
	@echo ""

#==============================================================================
# PLANIFICACIÓN (PREVISUALIZACIÓN)
#==============================================================================

plan:
	@echo ""
	@echo "$(BLUE)� Previsualizando cambios...$(NC)"
	@echo ""
	@echo "Esto te muestra QUÉ se va a crear sin crear nada todavía."
	@echo ""
	@terraform plan
	@echo ""
	@echo "$(YELLOW)Si todo se ve bien, ejecuta:$(NC) make deploy"
	@echo ""

#==============================================================================
# DESPLIEGUE
#==============================================================================

deploy:
	@echo ""
	@echo "$(BLUE)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║                  DESPLEGANDO NODO SOLANA                       ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@if [ -z "$$TF_VAR_project_id" ]; then \
		echo "$(RED)✗ Error: TF_VAR_project_id no configurado$(NC)"; \
		echo ""; \
		echo "Ejecuta primero: $(GREEN)make init$(NC)"; \
		echo ""; \
		exit 1; \
	fi
	@echo "$(YELLOW)Proyecto:$(NC) $$TF_VAR_project_id"
	@echo "$(YELLOW)Nodos a crear:$(NC) $${TF_VAR_node_count:-1}"
	@echo ""
	@echo "$(BLUE)Terraform está creando la infraestructura...$(NC)"
	@terraform apply -auto-approve
	@echo ""
	@echo "$(GREEN)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║                    ✅ DESPLIEGUE COMPLETO                       ║$(NC)"
	@echo "$(GREEN)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)⏳ El nodo está instalando software (Rust, Solana, Anchor)...$(NC)"
	@echo "   Esto tarda ~8-10 minutos."
	@echo ""
	@echo "$(BLUE)Mientras esperas, puedes:$(NC)"
	@echo "  1. Ver el progreso:  $(GREEN)make logs$(NC)"
	@echo "  2. Ver el estado:    $(GREEN)make status$(NC)"
	@echo ""
	@echo "$(BLUE)Cuando termine (8-10 min):$(NC)"
	@echo "  1. Verificar:        $(GREEN)make smoke-test$(NC)"
	@echo "  2. Conectar:         $(GREEN)make ssh$(NC)"
	@echo ""

#==============================================================================
# DESTRUCCIÓN (CON CONFIRMACIÓN)
#==============================================================================

destroy:
	@echo ""
	@echo "$(RED)╔════════════════════════════════════════════════════════════════╗$(NC)"
	@echo "$(RED)║                    ⚠️  ADVERTENCIA                             ║$(NC)"
	@echo "$(RED)╚════════════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Esto va a ELIMINAR toda la infraestructura:$(NC)"
	@echo "  - Nodos Solana"
	@echo "  - VPC y subnets"
	@echo "  - Reglas de firewall"
	@echo "  - Discos (500GB por nodo)"
	@echo ""
	@echo "$(RED)Esta acción NO se puede deshacer.$(NC)"
	@echo ""
	@read -p "¿Estás seguro? Escribe 'si' para confirmar: " confirm; \
	if [ "$$confirm" = "si" ]; then \
		echo ""; \
		echo "$(YELLOW)Destruyendo infraestructura...$(NC)"; \
		terraform destroy -auto-approve; \
		echo ""; \
		echo "$(GREEN)✅ Infraestructura eliminada$(NC)"; \
		echo ""; \
	else \
		echo ""; \
		echo "$(BLUE)Cancelado. No se eliminó nada.$(NC)"; \
		echo ""; \
	fi

#==============================================================================
# MONITOREO Y ACCESO
#==============================================================================

status:
	@echo ""
	@echo "$(BLUE)📊 Estado de los nodos Solana:$(NC)"
	@echo ""
	@gcloud compute instances list --filter="name~solana-dev-node" \
		--format="table(name,status,zone,networkInterfaces[0].accessConfigs[0].natIP:label=IP_EXTERNA)" 2>/dev/null || \
		(echo "$(YELLOW)No hay nodos desplegados todavía.$(NC)" && \
		 echo "Ejecuta: $(GREEN)make deploy$(NC)")
	@echo ""

logs:
	@echo ""
	@echo "$(BLUE)📜 Logs de instalación del nodo $(YELLOW)$(NODE)$(NC)..."
	@echo "   (Presiona Ctrl+C para salir)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) -- tail -f /var/log/solana-setup.log 2>/dev/null || \
		(echo "$(RED)✗ No se pudo conectar al nodo$(NC)" && \
		 echo "Verifica que existe: $(GREEN)make status$(NC)")

smoke-test:
	@echo ""
	@echo "$(BLUE)🧪 Ejecutando smoke test en $(YELLOW)$(NODE)$(NC)...$(NC)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap -- ./run-smoke-test.sh 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) -- ./run-smoke-test.sh 2>/dev/null || \
		(echo "$(RED)✗ No se pudo ejecutar el test$(NC)" && \
		 echo "Verifica que el nodo esté listo: $(GREEN)make logs$(NC)")
	@echo ""

ssh:
	@echo ""
	@echo "$(BLUE)🔐 Conectando a $(YELLOW)$(NODE)$(NC)...$(NC)"
	@echo ""
	@gcloud compute ssh $(NODE) --zone=$(ZONE) --tunnel-through-iap 2>/dev/null || \
		gcloud compute ssh $(NODE) --zone=$(ZONE) 2>/dev/null || \
		(echo "$(RED)✗ No se pudo conectar$(NC)" && \
		 echo "Verifica que el nodo existe: $(GREEN)make status$(NC)")

#==============================================================================
# LIMPIEZA
#==============================================================================

clean:
	@echo ""
	@echo "$(BLUE)🧹 Limpiando archivos temporales de Terraform...$(NC)"
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@echo "$(GREEN)✅ Limpieza completa$(NC)"
	@echo ""
	@echo "$(YELLOW)Nota:$(NC) Esto solo elimina archivos locales."
	@echo "Para eliminar la infraestructura en GCP: $(GREEN)make destroy$(NC)"
	@echo ""