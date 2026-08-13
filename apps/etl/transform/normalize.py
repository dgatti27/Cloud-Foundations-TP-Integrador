"""Transformaciones grupo 1: limpieza ligera antes de landing en bronce.

No modela el DW todavía — eso es grupo 2 (`to_gold.py`). Aquí:
  - castea fechas a ISO string/date
  - normaliza strings (strip)
  - agrega metadato origen
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any


def _jsonable(v: Any) -> Any:
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


def normalize_records(records: list[dict[str, Any]], origen: str) -> list[dict[str, Any]]:
    """Formato uniforme genérico (payload + origen). Usado por orígenes no-ERP."""
    out = []
    for r in records:
        cleaned = {k: _jsonable(v) for k, v in r.items()}
        out.append({"origen": origen, "payload": cleaned})
    return out


def normalize_erp_table(records: list[dict[str, Any]], tabla: str) -> list[dict[str, Any]]:
    """Limpia filas ERP manteniendo columnas (para INSERT columnar en bronce)."""
    out: list[dict[str, Any]] = []
    for r in records:
        row = {}
        for k, v in r.items():
            if isinstance(v, str):
                v = v.strip()
            row[k] = v
        row["_tabla"] = tabla
        row["_origen"] = "erp"
        out.append(row)
    print(f"[transform normalize_erp] tabla={tabla} filas={len(out)}")
    return out


def normalize_erp_bundle(
    tables: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    return {name: normalize_erp_table(rows, name) for name, rows in tables.items()}
