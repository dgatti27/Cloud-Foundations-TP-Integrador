"""Extractor grupo 2: schema bronce (RDS) → filas en memoria.

Contexto
--------
Después del DAG grupo 1, el landing vive en:
  bronce.erp_clientes / erp_productos / erp_ventas

Este módulo las relee para alimentar `transform.to_gold`.

Credencial: `rds_etl_conn()` → secret `dw/rds-etl` (`etl_writer`).

Quién lo llama
--------------
DAG `etl_bronce_to_gold` → task extract → `extract_bronce_all()`.
"""
from __future__ import annotations

from typing import Any

from pipeline.config import rds_etl_conn
from pipeline.db import connect, fetch_dicts

# ---------------------------------------------------------------------------
# Tablas landing (DDL en sql/bronce_erp_ddl.sql)
# ---------------------------------------------------------------------------
BRONCE_TABLES = {
    "clientes": "SELECT * FROM bronce.erp_clientes ORDER BY id_cliente",
    "productos": "SELECT * FROM bronce.erp_productos ORDER BY id_producto",
    "ventas": "SELECT * FROM bronce.erp_ventas ORDER BY id_venta",
}


def extract_bronce(tabla: str = "ventas", **_) -> list[dict[str, Any]]:
    """Lee UNA tabla de bronce.erp_* como lista de dicts."""
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
    """Extrae las tres tablas bronce (entrada de `transform_to_gold`)."""
    return {name: extract_bronce(name) for name in BRONCE_TABLES}
