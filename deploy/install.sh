#!/bin/bash
# install.sh — Installation complète de breach-sim en service systemd.
#
# Usage (en root, une seule fois) :
#   bash deploy/install.sh
#
# Ce script :
#   1. Crée le venv Python et installe les dépendances
#   2. Télécharge les modèles ONNX si absents
#   3. Installe et active le service systemd
#
# Prérequis : frontend déjà buildé (cd frontend && npm install && npm run build)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VENV="${ROOT_DIR}/.venv"
SERVICE_SRC="${SCRIPT_DIR}/breach-sim.service"
SERVICE_DEST="/etc/systemd/system/breach-sim.service"

echo ""
echo "══════════════════════════════════════════════"
echo "  breach-sim — Installation service systemd"
echo "══════════════════════════════════════════════"
echo ""

# ── 1. Venv + dépendances ──────────────────────────────────────────────────────
echo "── Python venv ──────────────────────────────"
if [ ! -f "${VENV}/bin/activate" ]; then
  echo "  Création du venv..."
  python3 -m venv "${VENV}"
fi
source "${VENV}/bin/activate"
echo "  Installation des dépendances..."
pip install -q -r "${ROOT_DIR}/backend/requirements.txt"
echo "  ✓ Dépendances installées"

# ── 2. Modèles ONNX ───────────────────────────────────────────────────────────
echo ""
echo "── Modèles ONNX ─────────────────────────────"
ALL_OK=true
for agent in opnsense wireguard crowdsec; do
  if [ ! -f "${ROOT_DIR}/onnx/${agent}/model.onnx" ]; then
    ALL_OK=false
    break
  fi
done

if $ALL_OK; then
  echo "  ✓ Modèles déjà présents"
else
  echo "  Téléchargement des modèles (peut prendre plusieurs minutes)..."
  bash "${ROOT_DIR}/scripts/download_models.sh"
fi

# ── 3. Service systemd ────────────────────────────────────────────────────────
echo ""
echo "── Service systemd ──────────────────────────"
cp "${SERVICE_SRC}" "${SERVICE_DEST}"
systemctl daemon-reload
systemctl enable breach-sim
systemctl restart breach-sim
sleep 2
systemctl is-active --quiet breach-sim \
  && echo "  ✓ breach-sim actif" \
  || { echo "  ✗ Échec démarrage — voir : journalctl -u breach-sim -n 30"; exit 1; }

echo ""
echo "══════════════════════════════════════════════"
echo "  ✓ Installé et démarré sur http://127.0.0.1:8888"
echo ""
echo "  → Exposer via Caddy : voir deploy/Caddyfile.snippet"
echo "  → Logs : journalctl -u breach-sim -f"
echo "  → Statut : systemctl status breach-sim"
echo "══════════════════════════════════════════════"
echo ""
