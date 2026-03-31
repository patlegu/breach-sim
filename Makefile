SHELL := bash
.DEFAULT_GOAL := help

# ── Variables ─────────────────────────────────────────────────────────────────

LAB      ?= classic
INSTANCE ?= 1
PORT     ?= 8888
ONNX_DIR ?= $(PWD)/onnx

.PHONY: help dev build install lab-up lab-down lab-show

help: ## Afficher l'aide
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Application ───────────────────────────────────────────────────────────────

dev: ## Démarrer l'app en mode dev (venv auto-créé)
	ONNX_DIR=$(ONNX_DIR) PORT=$(PORT) bash app/start.sh

build: ## Builder le frontend Svelte
	cd app/frontend && npm install && npm run build

models: ## Télécharger les modèles ONNX
	bash app/scripts/download_models.sh

install: ## Installer breach-sim comme service systemd (root)
	bash deploy/install.sh

# ── Infrastructure libvirt ────────────────────────────────────────────────────

lab-up: ## Créer un lab (LAB=classic|k8s INSTANCE=1)
	$(MAKE) -C infra lab-up LAB=$(LAB) INSTANCE=$(INSTANCE)

lab-down: ## Détruire un lab
	$(MAKE) -C infra lab-down LAB=$(LAB) INSTANCE=$(INSTANCE)

lab-show: ## Afficher les IPs d'un lab
	$(MAKE) -C infra lab-show LAB=$(LAB) INSTANCE=$(INSTANCE)

lab1-up: ## Lab classic instance 1
	$(MAKE) lab-up LAB=classic INSTANCE=1

lab2-up: ## Lab classic instance 2
	$(MAKE) lab-up LAB=classic INSTANCE=2

k8s-up: ## Lab k8s instance 1
	$(MAKE) lab-up LAB=k8s INSTANCE=1
