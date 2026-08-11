#!/bin/bash
# Lab 10 — Crea un AWS Budget mensual con alertas al 80% actual y 100% forecasted.
#
# Requisitos:
#   - AWS CLI v2 configurada (para AWS real)
#   - Editar notify.json con tu mail antes de correr esto
#
# Uso:
#   ./create-budget.sh               → contra AWS real
#   LOCALSTACK=1 ./create-budget.sh  → contra LocalStack (community=falla, Pro=modela)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# ── Endpoint y account según entorno ─────────────────────────────────────────

ENDPOINT_ARG=""
if [[ "${LOCALSTACK:-0}" == "1" ]]; then
  echo "Modo LocalStack. Nota: AWS Budgets es Pro-only en LocalStack."
  echo "En Community devuelve 'API not implemented'. La demo modela el flujo."
  echo ""
  ENDPOINT_ARG="--endpoint-url=http://localhost:4566"
  ACCOUNT_ID="000000000000"
  export AWS_ACCESS_KEY_ID=test
  export AWS_SECRET_ACCESS_KEY=test
  export AWS_DEFAULT_REGION=us-east-1
else
  # AWS real — Budgets es un servicio global pero la API expone us-east-1
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")"
  if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
    echo "ERROR: no puedo obtener AWS account ID. ¿aws sts get-caller-identity funciona?" >&2
    exit 1
  fi
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
fi

echo "Account ID: $ACCOUNT_ID"
echo "Endpoint:   ${ENDPOINT_ARG:-AWS real}"
echo ""

# ── Validaciones antes de tocar la API ───────────────────────────────────────

if grep -q "you@example.com" notify.json; then
  echo "ERROR: editá notify.json y reemplazá 'you@example.com' con tu mail." >&2
  echo "       Sino la alerta no llega a nadie." >&2
  exit 1
fi

python3 -m json.tool budget.json > /dev/null || { echo "budget.json inválido"; exit 1; }
python3 -m json.tool notify.json > /dev/null || { echo "notify.json inválido"; exit 1; }

# ── Crear el budget ──────────────────────────────────────────────────────────

echo "Creando budget..."
aws $ENDPOINT_ARG budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget "file://budget.json" \
  --notifications-with-subscribers "file://notify.json"

echo ""
echo "✓ Budget creado. Verificar:"
echo "  aws $ENDPOINT_ARG budgets describe-budget --account-id $ACCOUNT_ID --budget-name tp-integrador-monthly-budget"
