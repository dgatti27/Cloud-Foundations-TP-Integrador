"""Extractor del ERP (tablas FoxPro). Conexion por host, no por API."""
from __future__ import annotations

from typing import Any

from etl.config import source_conn


def extract_erp(tabla: str = "ventas", **_) -> list[dict[str, Any]]:
    conn = source_conn("erp-foxpro")
    # TODO: conectar a las tablas FoxPro/DBF por host (ej. lib dbf o un ODBC
    # Visual FoxPro) usando `conn` y devolver filas como list[dict].
    print(f"[extract erp-foxpro] tabla={tabla} host={conn.get('host', conn.get('dsn'))}")
    return []
