#!/usr/bin/env bash
# Detecta el puerto host de MiniStack RDS y lo escribe en .env y terraform.tfvars.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RECREATE_AIRFLOW=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --recreate-airflow) RECREATE_AIRFLOW=true; shift ;;
    *) echo "Uso: $0 [--recreate-airflow]"; exit 1 ;;
  esac
done

PORTS="$(docker ps --filter name=ministack-rds --format '{{.Ports}}' | head -n1 || true)"
if [[ -z "$PORTS" ]]; then
  echo "No hay contenedor ministack-rds-* en ejecución. Corré 'tofu apply' primero." >&2
  exit 1
fi

PORT="$(echo "$PORTS" | sed -nE 's/.*0\.0\.0\.0:([0-9]+)->5432.*/\1/p')"
if [[ -z "$PORT" ]]; then
  PORT="$(echo "$PORTS" | sed -nE 's/.*:([0-9]+)->5432.*/\1/p')"
fi
if [[ -z "$PORT" ]]; then
  echo "No se pudo parsear el puerto desde: $PORTS" >&2
  exit 1
fi

echo "Puerto RDS detectado: $PORT"

[[ -f .env ]] || { echo "Falta .env en la raíz del repo." >&2; exit 1; }

env_changed=false
if grep -q '^RDS_PORT_OVERRIDE=' .env; then
  if ! grep -q "^RDS_PORT_OVERRIDE=${PORT}$" .env; then
    sed -i.bak "s/^RDS_PORT_OVERRIDE=.*/RDS_PORT_OVERRIDE=${PORT}/" .env
    rm -f .env.bak
    env_changed=true
    echo "  OK .env → RDS_PORT_OVERRIDE=${PORT}"
  else
    echo "  .env ya tenía RDS_PORT_OVERRIDE=${PORT}"
  fi
else
  printf '\nRDS_PORT_OVERRIDE=%s\n' "$PORT" >> .env
  env_changed=true
  echo "  OK .env → RDS_PORT_OVERRIDE=${PORT}"
fi

tfvars="infra/terraform.tfvars"
tfvars_changed=false
if [[ -f "$tfvars" ]] && grep -q '^rds_port_override' "$tfvars"; then
  if ! grep -q "^rds_port_override = ${PORT}$" "$tfvars"; then
    sed -i.bak "s/^rds_port_override = .*/rds_port_override = ${PORT}/" "$tfvars"
    rm -f "${tfvars}.bak"
    tfvars_changed=true
    echo "  OK ${tfvars} → rds_port_override = ${PORT}"
  else
    echo "  terraform.tfvars ya tenía rds_port_override = ${PORT}"
  fi
else
  echo "rds_port_override = ${PORT}" >> "$tfvars"
  tfvars_changed=true
  echo "  OK ${tfvars} → rds_port_override = ${PORT}"
fi

if [[ "$env_changed" == true || "$tfvars_changed" == true ]]; then
  echo ""
  echo "Siguiente (si Airflow/Lambda ya estaban levantados):"
  echo "  docker compose up -d --force-recreate airflow-scheduler airflow-webserver"
  echo "  docker compose --profile iac run --rm tp-iac apply"
fi

if [[ "$RECREATE_AIRFLOW" == true ]]; then
  echo ""
  echo "Recreando Airflow..."
  docker compose up -d --force-recreate airflow-scheduler airflow-webserver
  echo "  OK Airflow recreado"
fi
