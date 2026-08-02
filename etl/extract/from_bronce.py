"""Extractor grupo 2: lee staging estructurado desde schema bronce (RDS)."""
from __future__ import annotations

from typing import Any

from etl.config import rds_etl_conn
from etl.db import connect, fetch_dicts

BRONCE_TABLES = {
    "clientes": "SELECT * FROM bronce.erp_clientes ORDER BY id_cliente",
    "productos": "SELECT * FROM bronce.erp_productos ORDER BY id_producto",
    "ventas": "SELECT * FROM bronce.erp_ventas ORDER BY id_venta",
}


def extract_bronce(tabla: str = "ventas", **_) -> list[dict[str, Any]]:
    key = tabla.lower().strip()
    if key not in BRONCE_TABLES:
        raise ValueError(f"Tabla bronce desconocida: {tabla}. Usá: {list(BRONCE_TABLES)}")

    conn = connect(rds_etl_conn())
    try:
        rows = fetch_dicts(conn, BRONCE_TABLES[key])
        print(f"[extract bronce] tabla={key} filas={len(rows)}")
        return rows
    finally:
        conn.close()


def extract_bronce_all(**_) -> dict[str, list[dict[str, Any]]]:
    return {name: extract_bronce(name) for name in BRONCE_TABLES}
