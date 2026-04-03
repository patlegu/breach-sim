# ── module/korrig-nat ──────────────────────────────────────────────────────────
#
# Gère les règles iptables sur l'hyperviseur korrig pour router le trafic
# internet entrant vers OPNsense (WAN bridge virbr2), qui le redistribue
# ensuite vers T-Pot dans la DMZ.
#
# Architecture :
#   Internet → enp41s0 → DNAT → OPNsense WAN (virbr2) → NAT OPNsense → T-Pot DMZ
#
# Idempotence : chaque règle est vérifiée avant insertion (-C) pour éviter
# les doublons. netfilter-persistent est appelé pour persister les règles.
#
# Destroy : les règles sont supprimées et netfilter-persistent est relancé.
# Pattern terraform_data : triggers_replace est accessible via self.triggers_replace
# dans les destroy provisioners, ce qui permet de passer le script dynamiquement.

terraform {
  required_providers {}
}

locals {
  ports = var.tpot_ports

  install_script = <<-EOT
    set -euo pipefail

    OPNSENSE="${var.opnsense_wan_ip}"
    WAN_BR=$(virsh -c ${var.libvirt_uri} net-info breach-${var.instance_id}-wan \
      | awk '/Bridge:/{print $2}')
    PUB="${var.public_iface}"

    # ── DNAT : trafic entrant public → OPNsense WAN ────────────────────────────
    %{~ for port in local.ports }
    if ! iptables -t nat -C PREROUTING -i "$PUB" -p tcp --dport ${port} \
        -j DNAT --to-destination "$OPNSENSE:${port}" 2>/dev/null; then
      iptables -t nat -A PREROUTING -i "$PUB" -p tcp --dport ${port} \
        -j DNAT --to-destination "$OPNSENSE:${port}"
      echo "DNAT ${port} -> $OPNSENSE ajoutée"
    fi
    %{~ endfor }

    # ── FORWARD enp41s0 → virbr2 (avant règles LIBVIRT_FWI) ───────────────────
    %{~ for port in local.ports }
    if ! iptables -C FORWARD -i "$PUB" -o "$WAN_BR" -p tcp --dport ${port} \
        -m state --state NEW,ESTABLISHED -j ACCEPT 2>/dev/null; then
      iptables -I FORWARD 1 -i "$PUB" -o "$WAN_BR" -p tcp --dport ${port} \
        -m state --state NEW,ESTABLISHED -j ACCEPT
      echo "FORWARD ${port} $PUB->$WAN_BR ajoutée"
    fi
    %{~ endfor }

    # Pas de MASQUERADE sur virbr2 : conntrack Linux gère le retour du DNAT
    # automatiquement. Un MASQUERADE ici écraserait l'IP source réelle de
    # l'attaquant avant qu'OPNsense la voie → T-Pot verrait 10.0.1.1 au lieu
    # de l'IP publique.

    # Supprimer l'éventuelle règle MASQUERADE résiduelle
    while iptables -t nat -C POSTROUTING -o "$WAN_BR" -j MASQUERADE 2>/dev/null; do
      iptables -t nat -D POSTROUTING -o "$WAN_BR" -j MASQUERADE
      echo "MASQUERADE $WAN_BR supprimée (préservation IP source attaquant)"
    done

    # ── Supprimer les anciennes règles DNAT direct vers T-Pot DMZ (virbr3) ─────
    %{~ for port in local.ports }
    while iptables -t nat -C PREROUTING -i "$PUB" -p tcp --dport ${port} \
        -j DNAT --to-destination 192.168.1.50:${port} 2>/dev/null; do
      iptables -t nat -D PREROUTING -i "$PUB" -p tcp --dport ${port} \
        -j DNAT --to-destination 192.168.1.50:${port}
      echo "Ancienne DNAT virbr3 port ${port} supprimée"
    done
    %{~ endfor }
    while iptables -t nat -C POSTROUTING -d 192.168.1.50/32 -o virbr3 \
        -j MASQUERADE 2>/dev/null; do
      iptables -t nat -D POSTROUTING -d 192.168.1.50/32 -o virbr3 -j MASQUERADE
      echo "Ancienne MASQUERADE virbr3 supprimée"
    done

    # ── Persistance ────────────────────────────────────────────────────────────
    netfilter-persistent save
    echo "==> korrig-nat : règles iptables appliquées et persistées."
  EOT

  # Script destroy — stocké dans triggers_replace pour être accessible via self.*
  destroy_script = <<-EOT
    set -euo pipefail

    OPNSENSE="${var.opnsense_wan_ip}"
    WAN_BR=$(virsh -c ${var.libvirt_uri} net-info breach-${var.instance_id}-wan \
      2>/dev/null | awk '/Bridge:/{print $2}')
    PUB="${var.public_iface}"

    %{~ for port in local.ports }
    iptables -t nat -D PREROUTING -i "$PUB" -p tcp --dport ${port} \
      -j DNAT --to-destination "$OPNSENSE:${port}" 2>/dev/null || true
    iptables -D FORWARD -i "$PUB" -o "$WAN_BR" -p tcp --dport ${port} \
      -m state --state NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
    %{~ endfor }

    iptables -t nat -D POSTROUTING -o "$WAN_BR" -j MASQUERADE 2>/dev/null || true  # no-op si déjà absente

    netfilter-persistent save
    echo "==> korrig-nat : règles iptables supprimées."
  EOT
}

# ── Apply : installe/met à jour les règles iptables ──────────────────────────

resource "terraform_data" "korrig_nat_apply" {
  triggers_replace = sha256(local.install_script)

  provisioner "local-exec" {
    command = local.install_script
  }
}

# ── Destroy : supprime les règles iptables ────────────────────────────────────
# triggers_replace = destroy_script → accessible via self.triggers_replace au destroy.

resource "terraform_data" "korrig_nat_destroy" {
  triggers_replace = local.destroy_script

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers_replace
  }

  depends_on = [terraform_data.korrig_nat_apply]
}
