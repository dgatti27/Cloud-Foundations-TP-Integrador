"""Grupo 1 de ETL: carga los datos crudos en la base CRUDA (landing)."""
from __future__ import annotations

from typing import Any

from etl.config import cruda_dsn


def load_to_cruda(records: list[dict[str, Any]], origen: str) -> int:
    dsn = cruda_dsn()
    # TODO: import psycopg2; INSERT en raw_ventas(origen, payload).
    print(f"[load->cruda] origen={origen} filas={len(records)} dsn={dsn.split('@')[-1]}")
    return len(records)
