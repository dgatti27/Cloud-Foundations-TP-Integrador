"""Configuración de conexiones del ETL.

Prioridad de credenciales
-------------------------
1) Variable de entorno ORIGEN_<X>_CONN / DW_*_CONN (DSN completo) — local rápido
2) Secrets Manager vía SECRETS_ENDPOINT (MiniStack :4567 host / :4566 en Docker)
3) Placeholders (solo para fallar con mensaje claro)

En el TP:
  dw/erp      → Postgres ERP (compose postgres-erp)
  dw/rds-etl  → etl_writer sobre RDS MiniStack (schemas bronce + gold)
"""
from __future__ import annotations

import json
import os
from typing import Any


def _sm_client():
    import boto3

    endpoint = os.environ.get("SECRETS_ENDPOINT")
    kwargs: dict[str, Any] = {
        "region_name": os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        "aws_access_key_id": os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        "aws_secret_access_key": os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    }
    if endpoint:
        kwargs["endpoint_url"] = endpoint
    return boto3.client("secretsmanager", **kwargs)


def from_secrets(secret_name: str) -> dict:
    """Lee JSON de Secrets Manager (MiniStack en Hobby, AWS en real)."""
    client = _sm_client()
    raw = client.get_secret_value(SecretId=secret_name)["SecretString"]
    return json.loads(raw)


def source_conn(origen: str) -> dict:
    """Dict de conexión para un origen (erp, erp-foxpro, …).

    Env: ORIGEN_ERP_CONN = postgresql://user:pass@host:5432/db
    Secret: dw/erp o dw/<origen>
    """
    env_key = "ORIGEN_" + origen.replace("-", "_").upper() + "_CONN"
    if os.environ.get(env_key):
        return {"dsn": os.environ[env_key]}

    secret_name = os.environ.get("ORIGEN_SECRET") or f"dw/{origen.split('-')[0]}"
    # erp-foxpro → dw/erp; override explícito con ORIGEN_SECRET
    if origen.startswith("erp"):
        secret_name = os.environ.get("ERP_SECRET", os.environ.get("ORIGEN_SECRET", "dw/erp"))

    if os.environ.get("USE_SECRETS_MANAGER") == "1" or os.environ.get("SECRETS_ENDPOINT"):
        return from_secrets(secret_name)

    return {"host": f"{origen}.internal", "user": "etl", "password": "CHANGE_ME"}


def rds_etl_conn() -> dict:
    """Credencial etl_writer para escribir bronce / gold."""
    if os.environ.get("DW_CRUDA_CONN"):
        return {"dsn": os.environ["DW_CRUDA_CONN"]}
    if os.environ.get("DW_DW_CONN") and not os.environ.get("SECRETS_ENDPOINT"):
        # DSN único local hacia dw
        return {"dsn": os.environ["DW_DW_CONN"]}

    secret = os.environ.get("RDS_ETL_SECRET", "dw/rds-etl")
    if os.environ.get("USE_SECRETS_MANAGER") == "1" or os.environ.get("SECRETS_ENDPOINT"):
        data = from_secrets(secret)
        # Desde Airflow/host el endpoint del secret es IP Docker interna;
        # override a host.docker.internal:15432 (Compose / host).
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


def cruda_dsn() -> str:
    """DSN hacia capa cruda (= bronce)."""
    return os.environ.get(
        "DW_CRUDA_CONN",
        "postgresql://etl_writer:CHANGE_ME@localhost:15432/dw",
    )


def dw_dsn() -> str:
    """DSN hacia gold/DW."""
    return os.environ.get(
        "DW_DW_CONN",
        "postgresql://etl_writer:CHANGE_ME@localhost:15432/dw",
    )
