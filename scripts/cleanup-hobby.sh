#!/usr/bin/env bash
# Baja la infra Hobby y limpia volúmenes de emuladores para evitar ghosts
# (secrets soft-deleted, IAM/S3 huérfanos, RDS MiniStack con schema viejo).
#
# Uso (desde la raíz del repo):
#   ./scripts/cleanup-hobby.sh
#   ./scripts/cleanup-hobby.sh --yes
#   ./scripts/cleanup-hobby.sh --skip-destroy --yes
#   ./scripts/cleanup-hobby.sh --full --yes
#
# No borra .env ni terraform.tfstate a propósito (destroy ya vacía el state).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_DESTROY=0
FULL=0
YES=0

usage() {
  cat <<'EOF'
Usage: cleanup-hobby.sh [--yes] [--skip-destroy] [--full]

  --yes            no pedir confirmación
  --skip-destroy   solo Docker/volúmenes (sin tofu destroy)
  --full           también borra postgres/redis/pgadmin volumes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --skip-destroy) SKIP_DESTROY=1 ;;
    --full) FULL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "flag desconocida: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

step() { printf '\n==> %s\n' "$1"; }
ok() { printf '  OK %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; }

if [[ "$YES" -ne 1 ]]; then
  cat <<EOF
Cleanup Hobby — esto va a:
  $([[ "$SKIP_DESTROY" -eq 0 ]] && echo '· tofu destroy (recursos IaC)' || echo '· (sin tofu destroy)')
  · docker compose down
  · borrar sidecars ministack-rds-*
  · borrar volúmenes: localstack-data, ministack-data, minio-data, ministack-rds-*-data
$([[ "$FULL" -eq 1 ]] && echo '  · --full: también postgres-*, redis-data, pgadmin-data')

EOF
  read -r -p "Continuar? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES|s|S|si|SI) ;;
    *) echo "Cancelado."; exit 0 ;;
  esac
fi

unset LOCALSTACK_AUTH_TOKEN || true
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# ── 1) OpenTofu destroy ─────────────────────────────────────────────────────
if [[ "$SKIP_DESTROY" -eq 0 ]]; then
  step "tofu destroy"
  destroyed=0
  if docker images -q tp-integrador-iac 2>/dev/null | grep -q .; then
    echo "  vía imagen toolbox (tp-iac)…"
    if docker compose --profile iac run --rm tp-iac destroy; then
      destroyed=1
      ok "destroy (toolbox)"
    else
      warn "destroy toolbox falló; se sigue con limpieza Docker"
    fi
  elif command -v tofu >/dev/null 2>&1; then
    echo "  vía tofu en el host…"
    if (cd infra && tofu destroy -auto-approve); then
      destroyed=1
      ok "destroy (host)"
    else
      warn "tofu destroy falló"
    fi
  else
    warn "Sin toolbox ni tofu en PATH — se omite destroy"
  fi
  if [[ "$destroyed" -eq 0 ]]; then
    warn "Si quedan recursos en emuladores, el wipe de volúmenes los limpia igual."
  fi
fi

# ── 2) Compose down ─────────────────────────────────────────────────────────
step "docker compose down"
docker compose down --remove-orphans
ok "compose down"

# ── 3) Sidecars RDS MiniStack ───────────────────────────────────────────────
step "contenedores ministack-rds-*"
mapfile -t rds_ids < <(docker ps -aq --filter "name=ministack-rds" 2>/dev/null || true)
if ((${#rds_ids[@]} > 0)); then
  docker rm -f "${rds_ids[@]}"
  ok "eliminados: ${#rds_ids[@]}"
else
  ok "ninguno"
fi

# ── 4) Volúmenes ────────────────────────────────────────────────────────────
step "volúmenes emuladores"
PROJECT="cloud-foundations-tp-integrador"
vols=(
  "${PROJECT}_localstack-data"
  "${PROJECT}_ministack-data"
  "${PROJECT}_minio-data"
)
if [[ "$FULL" -eq 1 ]]; then
  vols+=(
    "${PROJECT}_postgres-data-bronce"
    "${PROJECT}_postgres-data-dw"
    "${PROJECT}_postgres-data-erp"
    "${PROJECT}_redis-data"
    "${PROJECT}_pgadmin-data"
  )
fi

while IFS= read -r v; do
  [[ -n "$v" ]] || continue
  vols+=("$v")
done < <(docker volume ls -q 2>/dev/null | grep -E 'ministack-rds' || true)

# unique
mapfile -t vols < <(printf '%s\n' "${vols[@]}" | awk 'NF && !seen[$0]++')

for v in "${vols[@]}"; do
  if docker volume inspect "$v" >/dev/null 2>&1; then
    if docker volume rm "$v" >/dev/null 2>&1; then
      ok "rm $v"
    else
      warn "no se pudo borrar $v (¿en uso?)"
    fi
  else
    echo "  - $v (no existe)"
  fi
done

cat <<'EOF'

Cleanup listo.
Próximo arranque limpio:
  docker compose up -d
  docker compose --profile iac run --rm tp-iac apply
  # o: cd infra && tofu apply

EOF
