"""Transformaciones grupo 1: limpieza ligera antes del landing en bronce.

Qué hace / qué no hace
---------------------
SÍ: castear tipos a JSON-friendly, strip de strings, marcar metadatos.
NO: modelar dims/facts del DW — eso es grupo 2 (`to_gold.py`).

Quién lo llama
--------------
DAG `etl_erp_to_bronce` → tras `extract_erp_all` → `normalize_erp_bundle`.
"""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any


def _jsonable(v: Any) -> Any:
    """Convierte Decimal/fechas a tipos serializables (float / ISO string).

    Útil si el payload viaja por XCom o se loguea como JSON.
    """
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


def normalize_records(records: list[dict[str, Any]], origen: str) -> list[dict[str, Any]]:
    """Formato uniforme genérico: {origen, payload}.

    Pensado para orígenes no-columnar / demos viejos.
    El camino ERP actual usa `normalize_erp_*` (mantiene columnas).
    """
    out = []
    for r in records:
        cleaned = {k: _jsonable(v) for k, v in r.items()}
        out.append({"origen": origen, "payload": cleaned})
    return out


def normalize_erp_table(records: list[dict[str, Any]], tabla: str) -> list[dict[str, Any]]:
    """Limpia filas de UNA tabla ERP manteniendo el esquema columnar.

    - strip en strings
    - agrega `_tabla` y `_origen` (metadato; el load ignora cols extra
      al armar el UPSERT por lista fija de columnas)
    """
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
    """Aplica `normalize_erp_table` a cada clave del dict del extract."""
    return {name: normalize_erp_table(rows, name) for name, rows in tables.items()}
