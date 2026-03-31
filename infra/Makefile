TF      := tofu
LAB     ?= classic
INSTANCE ?= 1
LAB_DIR  := labs/$(LAB)
TFVARS   := $(LAB_DIR)/terraform.tfvars

.PHONY: help lab-init lab-up lab-down lab-show

help: ## Afficher l'aide
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

lab-init: ## Initialiser Terraform (LAB=classic|k8s INSTANCE=1)
	@test -f $(TFVARS) || { echo "ERROR: $(TFVARS) manquant. Copier terraform.tfvars.example."; exit 1; }
	$(TF) -chdir=$(LAB_DIR) init

lab-up: lab-init ## Créer le lab (LAB=classic|k8s INSTANCE=1)
	$(TF) -chdir=$(LAB_DIR) apply -auto-approve \
		-var="instance_id=$(INSTANCE)"

lab-plan: ## Plan sans appliquer
	$(TF) -chdir=$(LAB_DIR) plan \
		-var="instance_id=$(INSTANCE)"

lab-down: ## Détruire le lab
	$(TF) -chdir=$(LAB_DIR) destroy -auto-approve \
		-var="instance_id=$(INSTANCE)"

lab-show: ## Afficher les outputs (IPs, URLs)
	$(TF) -chdir=$(LAB_DIR) output lab_summary

# Raccourcis multi-instances
lab1-up:   ## Lab classic instance 1
	$(MAKE) lab-up LAB=classic INSTANCE=1

lab2-up:   ## Lab classic instance 2
	$(MAKE) lab-up LAB=classic INSTANCE=2

k8s-up:    ## Lab k8s instance 1
	$(MAKE) lab-up LAB=k8s INSTANCE=1
