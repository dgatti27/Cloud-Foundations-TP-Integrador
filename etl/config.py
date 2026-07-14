"""Configuracion de conexiones del ETL.

En AWS: las credenciales de cada origen y de RDS salen de Secrets Manager
(dw/erp-foxpro, dw/ecommerce-mongo, dw/eventos-mongo, dw/scraping, dw/rds-dw).
En local (Docker): se leen de variables de entorno (DW_CRUDA_CONN, DW_DW_CONN,
y ORIGEN_*_CONN). Este modulo abstrae de donde vienen.
"""
from __future__ import annotations

import json
import os


def _from_secrets(secret_name: str) -> dict:
    """Lee un secreto de AWS Secrets Manager. Se usa en AWS real."""
    import boto3  # import diferido: no hace falta en local

    client = boto3.client("secretsmanager")
    resp = client.get_secret_value(SecretId=secret_name)
    return json.loads(resp["SecretString"])


def source_conn(origen: str) -> dict:
    """Devuelve dict de conexion para un origen.

    Prioridad: variable de entorno ORIGEN_<ORIGEN>_CONN (local) ->
    Secrets Manager dw/<origen> (AWS).
    """
    env_key = "ORIGEN_" + origen.replace("-", "_").upper() + "_CONN"
    if os.environ.get(env_key):
        return {"dsn": os.environ[env_key]}
    if os.environ.get("USE_SECRETS_MANAGER") == "1":
        return _from_secrets(f"dw/{origen}")
    # Placeholder local: completar con tus datos reales.
    return {"host": f"{origen}.internal", "user": "etl", "password": "CHANGE_ME"}


def cruda_dsn() -> str:
    return os.environ.get("DW_CRUDA_CONN", "postgresql://postgres:postgres@postgres:5432/cruda")


def dw_dsn() -> str:
    return os.environ.get("DW_DW_CONN", "postgresql://postgres:postgres@postgres:5432/dw")
