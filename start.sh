#!/bin/bash
# Démarre le backend breach-sim.
#
# Variables d'environnement :
#   ONNX_DIR   — chemin vers les modèles ONNX (défaut : ./onnx)
#   PORT       — port d'écoute (défaut : 8888)
#
# Première utilisation :
#   1. Placer les modèles ONNX dans ./onnx/opnsense, ./onnx/wireguard, ./onnx/crowdsec
#      OU les télécharger : bash scripts/download_models.sh
#   2. Builder le frontend : cd frontend && npm install && npm run build
#   3. Lancer : ./start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${SCRIPT_DIR}/.venv"
ONNX_DIR="${ONNX_DIR:-${SCRIPT_DIR}/onnx}"
PORT="${PORT:-8888}"

# Créer le venv si absent
if [ ! -f "${VENV}/bin/activate" ]; then
  echo "📦 Création du venv Python..."
  if ! python3 -m venv "${VENV}" 2>/dev/null; then
    PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    echo "❌ venv non disponible. Installe le paquet manquant :"
    echo "   sudo apt install python${PYVER}-venv"
    exit 1
  fi
fi

source "${VENV}/bin/activate"

# Installer les dépendances
pip install -q -r "${SCRIPT_DIR}/backend/requirements.txt"

# Vérifier les modèles
for agent in opnsense wireguard crowdsec; do
  if [ ! -f "${ONNX_DIR}/${agent}/model.onnx" ]; then
    echo "⚠️  Modèle manquant : ${ONNX_DIR}/${agent}/model.onnx"
    echo "   Télécharge-les : bash scripts/download_models.sh"
    exit 1
  fi
done

export ONNX_DIR="${ONNX_DIR}"

echo "🚀 breach-sim démarré sur http://localhost:${PORT}"
echo "   Modèles ONNX : ${ONNX_DIR}"

cd "${SCRIPT_DIR}"
uvicorn backend.main:app --host 0.0.0.0 --port "${PORT}" --workers 1
