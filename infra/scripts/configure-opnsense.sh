#!/usr/bin/env bash
# configure-opnsense.sh — Configuration initiale OPNsense via API REST
#
# Usage : INSTANCE=1 bash configure-opnsense.sh
#
# Prérequis :
#   - OPNsense booté avec vtnet0=WAN (DHCP) et vtnet1=LAN (192.168.1.1 défaut)
#   - API accessible sur le WAN (activer via console : System > Settings > Administration)
#   - Ou configurer manuellement la LAN IP via la console OPNsense (option 2)
#
# Séquence manuelle alternative (console virsh) :
#   virsh console breach-${INSTANCE}-opnsense
#   → Option 2 : Set interface(s) IP address
#   → Interface : vtnet1 (LAN)
#   → IPv4 : 192.168.${10+INSTANCE}.1
#   → Subnet : 24
#   → Valider (pas de gateway, pas de DHCP libvirt)

set -euo pipefail

INSTANCE="${INSTANCE:-1}"
LAN_BASE="192.168.$((10 + INSTANCE))"
LAN_IP="${LAN_BASE}.1"
WAN_DOMAIN="breach-${INSTANCE}-wan"

echo "==> Lab breach-sim instance ${INSTANCE}"
echo "==> LAN cible : ${LAN_IP}/24"
echo ""

# Récupérer l'IP WAN OPNsense depuis les leases libvirt
WAN_IP=$(virsh net-dhcp-leases "${WAN_DOMAIN}" 2>/dev/null \
  | grep -i "opnsense" | awk '{print $5}' | cut -d/ -f1 | head -1)

if [ -z "${WAN_IP}" ]; then
  echo "ERROR: OPNsense n'a pas de lease DHCP sur ${WAN_DOMAIN}"
  echo "Vérifier : virsh console breach-${INSTANCE}-opnsense"
  exit 1
fi

echo "==> OPNsense WAN IP : ${WAN_IP}"
echo ""
echo "Configuration manuelle requise (UFS2 write non disponible sur ce kernel) :"
echo ""
echo "  virsh console breach-${INSTANCE}-opnsense"
echo "  [Entrée pour afficher le menu]"
echo "  → 2) Set interface(s) IP address"
echo "  → Enter the number of the interface to configure: 2 (vtnet1 LAN)"
echo "  → Configure IPv4 address vtnet1 interface via DHCP? n"
echo "  → Enter the new LAN IPv4 address: ${LAN_IP}"
echo "  → Enter the new LAN IPv4 subnet bit count: 24"
echo "  → For a LAN, press <ENTER> for none"
echo "  → Do you want to enable the DHCP server on LAN? y"
echo "  → Enter the start address of the IPv4 client address range: ${LAN_BASE}.10"
echo "  → Enter the end address: ${LAN_BASE}.99"
echo ""
echo "Après configuration, OPNsense sera accessible sur :"
echo "  https://${LAN_IP}  (depuis une VM sur le LAN)"
echo "  API : https://${LAN_IP}/api"
