"""
Demo de host: prepara el origen ERP para el camino B (sin correr el ETL).

Qué hace (en orden)
-------------------
1) `docker compose up -d postgres-erp` y espera `pg_isready`.
2) Cuenta filas en Clientes / Productos / Ventas; si faltan, aplica
   `erp/seed_erp.sql`.
3) Crea o actualiza el secret `dw/erp` en MiniStack (para que Airflow
   pueda resolver la conexión del extractor).
4) Imprime el siguiente comando: `python labs/ecs/ecs.py --skip-infra --erp`

Qué NO hace
-----------
No escribe bronce ni gold. Eso lo orquestan los DAGs
`etl_erp_to_bronce` y `etl_bronce_to_gold`.

Uso
---
    python apps/pipeline/pipeline_demo.py
    python apps/pipeline/pipeline_demo.py --skip-secret
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Constantes de entorno local del TP
# ---------------------------------------------------------------------------
ETL_DIR = Path(__file__).resolve().parent  # apps/pipeline/
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
ENDPOINT_MS = os.environ.get("MINISTACK_ENDPOINT", "http://localhost:4567")
ORIGEN_SECRET = "dw/erp"

# Credenciales dummy del emulador (MiniStack / LocalStack-like)
_CREDS = dict(
    region_name=REGION,
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
)

# Payload que guardamos en Secrets Manager: hostname Docker de Compose.
# Desde contenedores Airflow, `postgres-erp` resuelve por red interna.
ERP_PAYLOAD = {
    "host": "postgres-erp",
    "port": 5432,
    "dbname": "erp",
    "username": "postgres",
    "password": "postgres",
    "engine": "postgres",
}


def _run(cmd: list[str], check: bool = True, input_text: str | None = None) -> subprocess.CompletedProcess:
    """Ejecuta un comando de shell y lo imprime (para seguir el demo)."""
    print(f"  $ {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        check=check,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        input=input_text,
    )


# ---------------------------------------------------------------------------
# Paso 1 — origen Postgres ERP
# ---------------------------------------------------------------------------
def step_erp_up() -> None:
    """Levanta el contenedor, espera ready y verifica/aplica el seed."""
    print("1. Postgres ERP (origen)")
    _run(["docker", "compose", "up", "-d", "postgres-erp"], check=True)

    # Espera hasta ~30s a que Postgres acepte conexiones
    for _ in range(30):
        r = _run(
            ["docker", "exec", "postgres-erp", "pg_isready", "-U", "postgres", "-d", "erp"],
            check=False,
        )
        if r.returncode == 0:
            print("  ✓ postgres-erp ready")
            break
    else:
        raise SystemExit("postgres-erp no quedó ready")

    # Conteos por tabla (identifiers quoted: mayúsculas del seed)
    sql = (
        'SELECT \'Clientes\' t, count(*) FROM "Clientes" '
        'UNION ALL SELECT \'Productos\', count(*) FROM "Productos" '
        'UNION ALL SELECT \'Ventas\', count(*) FROM "Ventas";'
    )
    r = _run(
        ["docker", "exec", "-i", "postgres-erp", "psql", "-U", "postgres", "-d", "erp", "-c", sql],
        check=False,
    )
    # Si las tablas no existen aún, aplicamos el seed a mano
    if r.returncode != 0:
        seed = (ETL_DIR / "erp" / "seed_erp.sql").read_text(encoding="utf-8")
        print("  · aplicando seed_erp.sql…")
        _run(
            ["docker", "exec", "-i", "postgres-erp", "psql", "-U", "postgres", "-d", "erp"],
            check=True,
            input_text=seed,
        )
        r = _run(
            ["docker", "exec", "-i", "postgres-erp", "psql", "-U", "postgres", "-d", "erp", "-c", sql],
            check=True,
        )
    print(r.stdout)


# ---------------------------------------------------------------------------
# Paso 2 — secret dw/erp en MiniStack
# ---------------------------------------------------------------------------
def step_secret() -> None:
    """Crea el secret o lo actualiza si ya existía (idempotente)."""
    print("2. Secret dw/erp (MiniStack)")
    sm = boto3.client("secretsmanager", endpoint_url=ENDPOINT_MS, **_CREDS)
    body = json.dumps(ERP_PAYLOAD)
    try:
        sm.create_secret(Name=ORIGEN_SECRET, Description="ERP origen", SecretString=body)
        print(f"  ✓ {ORIGEN_SECRET} creado")
    except ClientError as e:
        code = e.response["Error"].get("Code", "")
        if "AlreadyExists" in code or "already exists" in str(e).lower():
            sm.put_secret_value(SecretId=ORIGEN_SECRET, SecretString=body)
            print(f"  ✓ {ORIGEN_SECRET} actualizado")
        else:
            raise
    name = sm.describe_secret(SecretId=ORIGEN_SECRET)["Name"]
    print(f"  · Name={name} (host=postgres-erp para Airflow en red Docker)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(description="ERP + paquete pipeline/")
    parser.add_argument(
        "--skip-secret",
        action="store_true",
        help="Solo levanta ERP; no toca Secrets Manager",
    )
    args = parser.parse_args()

    print("=== origen ERP + paquete pipeline/ ===\n")
    print(f"  MiniStack: {ENDPOINT_MS}\n")

    step_erp_up()
    if not args.skip_secret:
        step_secret()

    print("\n3. Siguiente (orquestación Airflow):")
    print("     python labs/ecs/ecs.py --skip-infra --erp")

    print("\n=== ETL demo OK ===")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(e.stdout or "", file=sys.stderr)
        print(e.stderr or "", file=sys.stderr)
        sys.exit(e.returncode or 1)
    except KeyboardInterrupt:
        sys.exit(130)
