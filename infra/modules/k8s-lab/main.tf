# ── module/k8s-lab ────────────────────────────────────────────────────────────
#
# Lab Kubernetes (k3s) pour scénarios d'attaque cloud-native.
#
# Topologie :
#   k3s-cp       — control plane (192.168.{10+id}.30)
#   k3s-worker1  — worker (192.168.{10+id}.31)
#   k3s-worker2  — worker (192.168.{10+id}.32)
#
# Bootstrap cloud-init :
#   cp        → installe k3s server, exporte kubeconfig
#   workers   → installe k3s agent (rejoignent le CP via token)
#
# Le token k3s est généré par Terraform et injecté dans les deux workers.
# Le kubeconfig est récupérable via SSH depuis breach-sim.
#
# Scénarios d'attaque possibles (déclenchés depuis "infected") :
#   - RBAC lateral move   : ServiceAccount avec droits trop larges
#   - Container escape    : pod privileged + hostPath mount
#   - NetworkPolicy bypass: pod sans label de sélection
#   - API server abuse    : kubectl depuis pod avec token monté

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  lan_prefix = split("/", var.lan_cidr)[1]
  gateway    = cidrhost(var.lan_cidr, 1)
  cp_ip      = cidrhost(var.lan_cidr, 30)
  k3s_version = "v1.32.3+k3s1"

  workers = {
    worker1 = { ip = cidrhost(var.lan_cidr, 31), vcpu = 2, memory = 2048 }
    worker2 = { ip = cidrhost(var.lan_cidr, 32), vcpu = 2, memory = 2048 }
  }
}

# Token k3s généré une fois par instance
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# ── Image de base Debian (partagée avec classic-lab) ─────────────────────────
# On suppose que le module classic-lab a déjà uploadé debian-base.qcow2.
# Si ce module est utilisé seul, on vérifie et uploade si absent.

resource "terraform_data" "debian_base" {
  input = var.debian_image_url

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE="${var.image_cache_dir}"
      mkdir -p "$CACHE"
      BASE="$CACHE/debian-base.qcow2"
      if [ ! -f "$BASE" ]; then
        echo "==> Téléchargement image Debian cloud..."
        curl -fSL "${var.debian_image_url}" -o "$BASE"
      fi
      VIRSH="virsh -c ${var.libvirt_uri}"
      if ! $VIRSH vol-info --pool ${var.libvirt_pool} debian-base.qcow2 >/dev/null 2>&1; then
        echo "==> Upload image Debian dans le pool libvirt..."
        $VIRSH vol-create-as ${var.libvirt_pool} debian-base.qcow2 10M --format qcow2
        $VIRSH vol-upload --pool ${var.libvirt_pool} debian-base.qcow2 "$BASE"
      fi
    EOT
  }
}

# ── Volumes disque ────────────────────────────────────────────────────────────

resource "libvirt_volume" "cp" {
  name             = "breach-${var.instance_id}-k3s-cp.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "debian-base.qcow2"
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = var.cp_disk_size

  depends_on = [terraform_data.debian_base]
}

resource "libvirt_volume" "worker" {
  for_each = local.workers

  name             = "breach-${var.instance_id}-k3s-${each.key}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "debian-base.qcow2"
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = var.worker_disk_size

  depends_on = [terraform_data.debian_base]
}

# ── Cloud-init control plane ──────────────────────────────────────────────────

resource "libvirt_cloudinit_disk" "cp" {
  name = "breach-${var.instance_id}-k3s-cp-init.iso"
  pool = var.libvirt_pool

  user_data = templatefile("${path.module}/templates/user-data-cp.yaml.tftpl", {
    hostname       = "breach${var.instance_id}-k3s-cp"
    ssh_public_key = var.ssh_public_key
    k3s_token      = random_password.k3s_token.result
    k3s_version    = local.k3s_version
    cp_ip          = local.cp_ip
    instance_id    = var.instance_id
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = local.cp_ip
    prefix  = local.lan_prefix
    gateway = local.gateway
  })
}

# ── Cloud-init workers ────────────────────────────────────────────────────────

resource "libvirt_cloudinit_disk" "worker" {
  for_each = local.workers

  name = "breach-${var.instance_id}-k3s-${each.key}-init.iso"
  pool = var.libvirt_pool

  user_data = templatefile("${path.module}/templates/user-data-worker.yaml.tftpl", {
    hostname       = "breach${var.instance_id}-k3s-${each.key}"
    ssh_public_key = var.ssh_public_key
    k3s_token      = random_password.k3s_token.result
    k3s_version    = local.k3s_version
    cp_ip          = local.cp_ip
    instance_id    = var.instance_id
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = each.value.ip
    prefix  = local.lan_prefix
    gateway = local.gateway
  })
}

# ── Domaines libvirt ──────────────────────────────────────────────────────────

resource "libvirt_domain" "cp" {
  name   = "breach-${var.instance_id}-k3s-cp"
  vcpu   = var.cp_vcpu
  memory = var.cp_memory

  cpu { mode = "host-passthrough" }

  disk { volume_id = libvirt_volume.cp.id }
  cloudinit = libvirt_cloudinit_disk.cp.id

  network_interface {
    network_id     = var.lan_network_id
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  qemu_agent = true
  autostart  = true
}

resource "libvirt_domain" "worker" {
  for_each = local.workers

  name   = "breach-${var.instance_id}-k3s-${each.key}"
  vcpu   = each.value.vcpu
  memory = each.value.memory

  cpu { mode = "host-passthrough" }

  disk { volume_id = libvirt_volume.worker[each.key].id }
  cloudinit = libvirt_cloudinit_disk.worker[each.key].id

  network_interface {
    network_id     = var.lan_network_id
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  qemu_agent = true
  autostart  = true

  # Les workers démarrent après le CP pour que l'API server soit prêt
  depends_on = [libvirt_domain.cp]
}
