#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OK=0
WARN=0

pass() { echo "OK   $1"; OK=$((OK+1)); }
warn() { echo "WARN $1"; WARN=$((WARN+1)); }

echo "== cloud-foundations-lab checks =="
echo

# Compose
docker compose config >/dev/null 2>&1 && pass "compose config valido" || warn "compose config invalido"

# Python syntax
for script in \
  scripts/process_events.py \
  scripts/upload_to_object_storage.py \
  scripts/load_postgres.py \
  scripts/query_analytics.py \
  scripts/produce_sqs.py \
  scripts/consume_sqs.py \
  scripts/produce_kafka.py \
  scripts/consume_kafka.py; do
  python3 -m py_compile "$script" 2>/dev/null \
    && pass "$script sintaxis ok" \
    || warn "$script error de sintaxis"
done

# Servicios corriendo
if docker compose ps --services --filter status=running 2>/dev/null | grep -q postgres; then
  docker exec cloud-foundations-postgres pg_isready -U postgres -q && pass "postgres responde" || warn "postgres no responde"
else
  warn "postgres no esta corriendo"
fi

if docker compose ps --services --filter status=running 2>/dev/null | grep -q minio; then
  curl -sf http://localhost:9000/minio/health/live >/dev/null && pass "minio responde" || warn "minio no responde"
else
  warn "minio no esta corriendo"
fi

if docker compose ps --services --filter status=running 2>/dev/null | grep -q redis; then
  docker exec cloud-foundations-redis redis-cli ping 2>/dev/null | grep -q PONG && pass "redis responde" || warn "redis no responde"
else
  warn "redis no esta corriendo"
fi

if docker compose ps --services --filter status=running 2>/dev/null | grep -q localstack; then
  curl -sf http://localhost:4566/_localstack/health >/dev/null && pass "localstack responde" || warn "localstack no responde"
else
  warn "localstack no esta corriendo (se usa en clase 12+)"
fi

# Archivos procesados
[ -f data/processed/signups.json ] && pass "data/processed/signups.json existe" || warn "signups.json no existe; ejecuta: python scripts/process_events.py"
[ -f data/processed/sales_by_country.csv ] && pass "data/processed/sales_by_country.csv existe" || warn "sales_by_country.csv no existe; ver labs/02-storage.md"

# Documentacion
[ -f docs/architecture.md ] && pass "docs/architecture.md existe" || warn "docs/architecture.md no existe; ejecuta bootstrap.sh"
[ -f docs/decisions.md ] && pass "docs/decisions.md existe" || warn "docs/decisions.md no existe; ejecuta bootstrap.sh"

# IaC
if command -v terraform >/dev/null 2>&1; then
  (cd infra/terraform && terraform fmt -check -diff >/dev/null 2>&1 && terraform validate >/dev/null 2>&1) && pass "terraform fmt+validate ok" || warn "terraform fmt o validate fallo; ejecuta: cd infra/terraform && terraform fmt && terraform validate"
elif command -v tofu >/dev/null 2>&1; then
  (cd infra/terraform && tofu fmt -check -diff >/dev/null 2>&1 && tofu validate >/dev/null 2>&1) && pass "opentofu fmt+validate ok" || warn "opentofu fmt o validate fallo"
else
  warn "terraform/opentofu no instalado; se omite validacion IaC"
fi

echo
echo "Resultado: ${OK} OK / ${WARN} WARN"
