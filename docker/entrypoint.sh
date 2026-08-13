#!/usr/bin/env bash
# Entrypoint de la imagen tp-integrador-iac.
# Espera backends locales y ejecuta el flujo IaC (o un comando libre).
set -euo pipefail

ROOT="${WORKSPACE:-/workspace}"
cd "$ROOT"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
export MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"

# Dentro de Compose: DNS de servicios. Fuera de la red: override a localhost.
export LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localstack-integrador:4566}"
export MINISTACK_ENDPOINT="${MINISTACK_ENDPOINT:-http://ministack-integrador:4566}"
export MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://s3-soporte:9000}"

export TF_VAR_localstack_endpoint="${TF_VAR_localstack_endpoint:-$LOCALSTACK_ENDPOINT}"
export TF_VAR_ministack_endpoint="${TF_VAR_ministack_endpoint:-$MINISTACK_ENDPOINT}"
export TF_VAR_minio_endpoint="${TF_VAR_minio_endpoint:-$MINIO_ENDPOINT}"
export TF_VAR_repo_root="${TF_VAR_repo_root:-..}"

wait_http() {
  local url="$1"
  local name="$2"
  local n="${3:-60}"
  echo "→ esperando $name ($url)…"
  for _ in $(seq 1 "$n"); do
    if curl -sf "$url" >/dev/null 2>&1; then
      echo "  ✓ $name listo"
      return 0
    fi
    sleep 2
  done
  echo "✗ timeout esperando $name" >&2
  return 1
}

wait_backends() {
  wait_http "${LOCALSTACK_ENDPOINT}/_localstack/health" "LocalStack" 90 || \
    wait_http "${LOCALSTACK_ENDPOINT}/" "LocalStack" 30
  wait_http "${MINISTACK_ENDPOINT}/" "MiniStack" 90
  wait_http "${MINIO_ENDPOINT}/minio/health/live" "MinIO" 60 || \
    wait_http "${MINIO_ENDPOINT}/" "MinIO" 30
}

cmd="${1:-apply}"
shift || true

tofu_infra() {
  cd "$ROOT/infra"
  tofu init -upgrade
  exec tofu "$@"
}

case "$cmd" in
  apply)
    wait_backends
    tofu_infra apply -auto-approve "$@"
    ;;
  apply-reconcile)
    wait_backends
    tofu_infra apply -auto-approve "$@"
    ;;
  plan)
    wait_backends
    tofu_infra plan "$@"
    ;;
  destroy)
    wait_backends
    tofu_infra destroy -auto-approve "$@"
    ;;
  init)
    wait_backends
    cd "$ROOT/infra" && exec tofu init -upgrade
    ;;
  tofu)
    wait_backends
    cd "$ROOT/infra" && exec tofu "$@"
    ;;
  shell|bash)
    exec bash ${1+"$@"}
    ;;
  wait)
    wait_backends
    echo "backends OK"
    ;;
  help|-h|--help)
    cat <<'EOF'
Uso: docker compose --profile iac run --rm tp-iac <comando>

  apply             tofu init + apply -auto-approve (default)
  apply-reconcile   igual que apply
  plan              tofu init + plan
  destroy           tofu destroy -auto-approve
  init              solo tofu init en infra/
  tofu <args…>      pasa args a tofu (cwd=infra/)
  shell             bash interactivo en /workspace
  wait              solo healthcheck de backends

Variables: LOCALSTACK_ENDPOINT, MINISTACK_ENDPOINT, MINIO_ENDPOINT,
           TF_VAR_*, AWS_*, MINIO_ROOT_USER/PASSWORD
EOF
    ;;
  *)
    exec "$cmd" "$@"
    ;;
esac
