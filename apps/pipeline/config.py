"""Configuración de conexiones del ETL.

Prioridad de credenciales (de más local a más “cloud”)
----------------------------------------------------
1) Variable de entorno con DSN completo (`ORIGEN_*_CONN`, `DW_*_CONN`)
   → útil para pruebas rápidas en el host sin Secrets Manager.
2) Secrets Manager vía `SECRETS_ENDPOINT`
   → MiniStack en Hobby (`http://localhost:4567` desde host;
     endpoint interno Docker desde Airflow).
3) Placeholders (`CHANGE_ME`) si no hay nada configurado
   → fallan al conectar, pero el mensaje es claro.

Secrets del TP
--------------
  dw/erp      → Postgres origen (`postgres-erp` en Compose).
  dw/rds-etl  → usuario `etl_writer` sobre RDS MiniStack (bronce + gold).
"""
from __future__ import annotations

import json
import os
from typing import Any


# ---------------------------------------------------------------------------
# Cliente Secrets Manager (boto3)
# ---------------------------------------------------------------------------
def _sm_client():
    """Construye el client de Secrets Manager apuntando a MiniStack o AWS.
    - Credenciales `test`/`test` son las del emulador local del TP.
    """
    import boto3
    
    #Obtiene el endpoint de Secrets Manager desde las variables de entorno.
    endpoint = os.environ.get("SECRETS_ENDPOINT")
    args: dict[str, Any] = {
        "region_name": os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        "aws_access_key_id": os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        "aws_secret_access_key": os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    }
    if endpoint:
        args["endpoint_url"] = endpoint
    return boto3.client("secretsmanager", **args)


def from_secrets(secret_name: str) -> dict:
    """Lee el JSON de un secret y lo parsea a dict.

    Ej. `dw/erp` → {host, port, dbname, username, password, ...}
    """
    client = _sm_client()
    raw = client.get_secret_value(SecretId=secret_name)["SecretString"]
    return json.loads(raw)


# ---------------------------------------------------------------------------
# Conexión a ORÍGENES (grupo 1: ERP)
# ---------------------------------------------------------------------------
def source_conn(origen: str) -> dict:
    """Devuelve un dict usable por `pipeline.db.connect` para un origen.

    Resolución:
      1) Env `ORIGEN_<ORIGEN>_CONN` (DSN) si está seteada.
      2) Secret `dw/erp` (o override) si hay Secrets Manager / endpoint.
      3) Placeholder host `*.internal` (solo para fallar con mensaje claro).

    Nota: `erp-foxpro` es alias histórico; en el TP el origen es Postgres.
    """
    env_key = "ORIGEN_" + origen.replace("-", "_").upper() + "_CONN"
    if os.environ.get(env_key):
        return {"dsn": os.environ[env_key]}

    secret_name = os.environ.get("ORIGEN_SECRET") or f"dw/{origen.split('-')[0]}"
    # erp / erp-foxpro → siempre secret dw/erp salvo override explícito
    if origen.startswith("erp"):
        secret_name = os.environ.get("ERP_SECRET", os.environ.get("ORIGEN_SECRET", "dw/erp"))

    if os.environ.get("USE_SECRETS_MANAGER") == "1" or os.environ.get("SECRETS_ENDPOINT"):
        return from_secrets(secret_name)

    return {"host": f"{origen}.internal", "user": "etl", "password": "CHANGE_ME"}


# ---------------------------------------------------------------------------
# Conexión a RDS del DW (schemas bronce + gold)
# ---------------------------------------------------------------------------
def rds_etl_conn() -> dict:
    """Credencial `etl_writer` para escribir bronce / gold.

    Overrides útiles en Compose:
      RDS_HOST_OVERRIDE / RDS_PORT_OVERRIDE
      → desde el host: localhost:15432
      → desde Airflow: host.docker.internal:15432 (según compose)
    """
    if os.environ.get("DW_CRUDA_CONN"):
        return {"dsn": os.environ["DW_CRUDA_CONN"]}
    if os.environ.get("DW_DW_CONN") and not os.environ.get("SECRETS_ENDPOINT"):
        # Un solo DSN local hacia la base `dw`
        return {"dsn": os.environ["DW_DW_CONN"]}

    secret = os.environ.get("RDS_ETL_SECRET", "dw/rds-etl")
    if os.environ.get("USE_SECRETS_MANAGER") == "1" or os.environ.get("SECRETS_ENDPOINT"):
        data = from_secrets(secret)
        # El secret puede traer IP interna Docker; override para llegar desde host/Airflow
        data["host"] = os.environ.get("RDS_HOST_OVERRIDE", data.get("host"))
        data["port"] = int(os.environ.get("RDS_PORT_OVERRIDE", data.get("port", 5432)))
        return data

    return {
        "host": os.environ.get("RDS_HOST_OVERRIDE", "localhost"),
        "port": int(os.environ.get("RDS_PORT_OVERRIDE", "15432")),
        "dbname": "dw",
        "username": "etl_writer",
        "password": "CHANGE_ME",
    }


# ---------------------------------------------------------------------------
# DSNs de conveniencia (API legacy / scripts)
# ---------------------------------------------------------------------------
def cruda_dsn() -> str:
    """DSN string hacia la capa cruda (= schema bronce en la misma DB `dw`)."""
    return os.environ.get(
        "DW_CRUDA_CONN",
        "postgresql://etl_writer:CHANGE_ME@localhost:15432/dw",
    )


def dw_dsn() -> str:
    """DSN string hacia gold/DW (misma instancia RDS en el TP)."""
    return os.environ.get(
        "DW_DW_CONN",
        "postgresql://etl_writer:CHANGE_ME@localhost:15432/dw",
    )
