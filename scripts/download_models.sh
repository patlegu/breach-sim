#!/bin/bash
# Télécharge les 3 modèles ONNX int4 depuis Hugging Face.
#
# Usage :
#   bash scripts/download_models.sh
#   ONNX_DIR=/data/onnx bash scripts/download_models.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONNX_DIR="${ONNX_DIR:-${SCRIPT_DIR}/../onnx}"
HF_USER="patlegu"

AGENTS=(
  "opnsense:opnsense-qwen25-onnx-int4"
  "wireguard:wireguard-qwen25-onnx-int4"
  "crowdsec:crowdsec-qwen25-onnx-int4"
)

# Vérifier que huggingface-cli est disponible
if ! command -v huggingface-cli &>/dev/null; then
  echo "📦 Installation de huggingface_hub..."
  pip install -q huggingface_hub
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
  huggingface-cli download "${HF_USER}/${repo}" \
    --repo-type model \
    --local-dir "${dest}"

  echo "✅ ${agent} téléchargé."
done

echo ""
echo "✅ Tous les modèles sont dans ${ONNX_DIR}"
