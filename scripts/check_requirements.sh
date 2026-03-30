#!/bin/bash
# check_requirements.sh — Vérifie les prérequis système pour breach-sim.
#
# Usage :
#   bash scripts/check_requirements.sh
#
# Retourne 0 si tout est OK, 1 si des prérequis manquent.

set -e

ERRORS=0
WARNINGS=0

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; WARNINGS=$((WARNINGS+1)); }
fail() { echo -e "  ${RED}✗${NC}  $1"; ERRORS=$((ERRORS+1)); }

echo ""
echo "════════════════════════════════════════"
echo "  breach-sim — vérification prérequis"
echo "════════════════════════════════════════"
echo ""

# ── Python ────────────────────────────────────────────────────────────────────
echo "── Python ──────────────────────────────"

if command -v python3 &>/dev/null; then
  PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  PYMAJ=$(echo "$PYVER" | cut -d. -f1)
  PYMIN=$(echo "$PYVER" | cut -d. -f2)
  if [ "$PYMAJ" -ge 3 ] && [ "$PYMIN" -ge 10 ]; then
    ok "python3 ${PYVER}"
  else
    fail "python3 ${PYVER} — version 3.10+ requise"
  fi
else
  fail "python3 introuvable — installer : sudo apt install python3"
fi

if command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null 2>&1; then
  ok "pip disponible"
else
  fail "pip introuvable — installer : sudo apt install python3-pip"
fi

if python3 -m venv /tmp/_breach_venv_test &>/dev/null 2>&1; then
  rm -rf /tmp/_breach_venv_test
  ok "venv disponible"
else
  rm -rf /tmp/_breach_venv_test
  PYVER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  fail "venv non fonctionnel — installer : sudo apt install python${PYVER}-venv"
fi

# ── Node.js ───────────────────────────────────────────────────────────────────
echo ""
echo "── Node.js ─────────────────────────────"

if command -v node &>/dev/null; then
  NODEVER=$(node --version | sed 's/v//')
  NODEMAJ=$(echo "$NODEVER" | cut -d. -f1)
  if [ "$NODEMAJ" -ge 18 ]; then
    ok "node ${NODEVER}"
  else
    fail "node ${NODEVER} — version 18+ requise"
  fi
else
  fail "node introuvable — installer : https://nodejs.org ou sudo apt install nodejs"
fi

if command -v npm &>/dev/null; then
  ok "npm $(npm --version)"
else
  fail "npm introuvable — installer avec Node.js"
fi

# ── Espace disque ─────────────────────────────────────────────────────────────
echo ""
echo "── Espace disque ───────────────────────"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$SCRIPT_DIR")"
AVAIL_KB=$(df -k "$TARGET_DIR" | tail -1 | awk '{print $4}')
AVAIL_GB=$(echo "scale=1; $AVAIL_KB / 1048576" | bc 2>/dev/null || echo "?")

if [ "$AVAIL_KB" -ge 12582912 ]; then   # 12 GB
  ok "espace disque disponible : ${AVAIL_GB} GB (≥ 12 GB requis)"
elif [ "$AVAIL_KB" -ge 10485760 ]; then  # 10 GB
  warn "espace disque disponible : ${AVAIL_GB} GB (12 GB recommandé, peut être juste)"
else
  fail "espace disque insuffisant : ${AVAIL_GB} GB disponibles — 12 GB requis pour les 3 modèles ONNX"
fi

# ── RAM ───────────────────────────────────────────────────────────────────────
echo ""
echo "── Mémoire RAM ─────────────────────────"

if command -v free &>/dev/null; then
  TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$TOTAL_MB" -ge 8192 ]; then
    ok "RAM totale : ${TOTAL_MB} MB (≥ 8 GB)"
  elif [ "$TOTAL_MB" -ge 4096 ]; then
    warn "RAM totale : ${TOTAL_MB} MB — 8 GB recommandé (chargement des 3 modèles simultanément peut être lent)"
  else
    fail "RAM totale : ${TOTAL_MB} MB — 8 GB minimum requis pour charger les 3 modèles ONNX"
  fi
else
  warn "impossible de vérifier la RAM (commande 'free' absente)"
fi

# ── Réseau / HuggingFace ──────────────────────────────────────────────────────
echo ""
echo "── Réseau ──────────────────────────────"

if curl -s --max-time 5 https://huggingface.co > /dev/null 2>&1; then
  ok "accès HuggingFace (téléchargement des modèles)"
else
  warn "huggingface.co inaccessible — le téléchargement des modèles nécessite un accès internet"
fi

# ── Modèles ONNX (optionnel) ──────────────────────────────────────────────────
echo ""
echo "── Modèles ONNX ────────────────────────"

ONNX_DIR="${ONNX_DIR:-${TARGET_DIR}/onnx}"
ALL_MODELS_OK=true

for agent in opnsense wireguard crowdsec; do
  if [ -f "${ONNX_DIR}/${agent}/model.onnx" ]; then
    SIZE=$(du -sh "${ONNX_DIR}/${agent}" 2>/dev/null | cut -f1)
    ok "modèle ${agent} présent (${SIZE})"
  else
    warn "modèle ${agent} absent — lancer : bash scripts/download_models.sh"
    ALL_MODELS_OK=false
  fi
done

# ── Frontend buildé (optionnel) ───────────────────────────────────────────────
echo ""
echo "── Frontend ────────────────────────────"

if [ -f "${TARGET_DIR}/backend/static/index.html" ]; then
  ok "frontend buildé (backend/static/index.html présent)"
else
  warn "frontend non buildé — lancer : cd frontend && npm install && npm run build"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "  ${GREEN}✓ Tout est prêt — lance ./start.sh${NC}"
elif [ "$ERRORS" -eq 0 ]; then
  echo -e "  ${YELLOW}⚠ ${WARNINGS} avertissement(s) — le projet peut démarrer${NC}"
  echo -e "  Lance : ${GREEN}./start.sh${NC}"
else
  echo -e "  ${RED}✗ ${ERRORS} erreur(s) bloquante(s) à corriger${NC}"
  if [ "$WARNINGS" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ ${WARNINGS} avertissement(s) supplémentaire(s)${NC}"
  fi
fi

echo "════════════════════════════════════════"
echo ""

exit $ERRORS
