#!/bin/bash
# Télécharge les 3 modèles ONNX int4 depuis Hugging Face.
#
# Usage :
#   bash scripts/download_models.sh
#   ONNX_DIR=/data/onnx bash scripts/download_models.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ONNX_DIR="${ONNX_DIR:-${ROOT_DIR}/onnx}"
VENV="${ROOT_DIR}/.venv"
HF_USER="patlegu"

AGENTS=(
  "opnsense:opnsense-qwen25-onnx-int4"
  "wireguard:wireguard-qwen25-onnx-int4"
  "crowdsec:crowdsec-qwen25-onnx-int4"
)

# Résoudre python3 — préférer le venv du projet si disponible
if [ -f "${VENV}/bin/python3" ]; then
  PYTHON="${VENV}/bin/python3"
  PIP="${VENV}/bin/pip"
else
  PYTHON="python3"
  PIP="python3 -m pip"
fi

# Installer huggingface_hub si absent
if ! $PYTHON -c "import huggingface_hub" &>/dev/null 2>&1; then
  echo "📦 Installation de huggingface_hub..."
  $PIP install -q huggingface_hub
fi

mkdir -p "${ONNX_DIR}"

for entry in "${AGENTS[@]}"; do
  agent="${entry%%:*}"
  repo="${entry##*:}"
  dest="${ONNX_DIR}/${agent}"

  if [ -f "${dest}/model.onnx" ]; then
    echo "✅ ${agent} déjà présent, skip."
    continue
  fi

  echo "⬇️  Téléchargement ${HF_USER}/${repo} → ${dest}..."
  $PYTHON -m huggingface_hub download "${HF_USER}/${repo}" \
    --repo-type model \
    --local-dir "${dest}"

  echo "✅ ${agent} téléchargé."
done

echo ""
echo "✅ Tous les modèles sont dans ${ONNX_DIR}"
