"""Extractor ERP → filas crudas (lab-extra-tp).

Históricamente el origen era FoxPro/DBF. En el TP local el origen es el
Postgres `postgres-erp` (tablas Clientes / Productos / Ventas). La firma
`extract_erp` se mantiene para no romper imports; el host sale de `dw/erp`.
"""
from __future__ import annotations

from typing import Any

from etl.config import source_conn
from etl.db import connect, fetch_dicts

# Tablas del seed erp/seed_erp.sql (quoted identifiers)
ERP_TABLES = {
    "clientes": 'SELECT * FROM "Clientes" ORDER BY id_cliente',
    "productos": 'SELECT * FROM "Productos" ORDER BY id_producto',
    "ventas": 'SELECT * FROM "Ventas" ORDER BY id_venta',
}


def extract_erp(tabla: str = "ventas", **_) -> list[dict[str, Any]]:
    """Lee una tabla del ERP. `tabla` ∈ clientes | productos | ventas."""
    key = tabla.lower().strip()
    if key not in ERP_TABLES:
        raise ValueError(f"Tabla ERP desconocida: {tabla}. Usá: {list(ERP_TABLES)}")

    conn_cfg = source_conn("erp")
    conn = connect(conn_cfg)
    try:
        rows = fetch_dicts(conn, ERP_TABLES[key])
        print(f"[extract erp] tabla={key} filas={len(rows)} host={conn_cfg.get('host', conn_cfg.get('dsn'))}")
        return rows
    finally:
        conn.close()


def extract_erp_all(**_) -> dict[str, list[dict[str, Any]]]:
    """Extrae las tres tablas en un solo dict (pipeline grupo 1)."""
    return {name: extract_erp(name) for name in ERP_TABLES}
