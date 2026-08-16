"""Transformaciones grupo 1: limpieza ligera antes del landing en bronce.

Qué hace / qué no hace
---------------------
SÍ: castear tipos a JSON, strip de strings (eliminar espacios en blanco), marcar metadatos.
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
    """Convierte Decimal/fechas a float / ISO string.

    Útil si el payload viaja por XCom o se loguea como JSON.
    """
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


#Formato uniforme genérico: {origen, payload}.
#Deprecado: usar `normalize_erp_bundle` en su lugar.
def normalize_records(records: list[dict[str, Any]], origen: str) -> list[dict[str, Any]]:
    """Formato uniforme genérico: {origen, payload}.

    Pensado para orígenes no-columnar.
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
    #Inicializa una lista vacía para almacenar las filas limpias.
    out: list[dict[str, Any]] = []
    for r in records:
        row = {}
        #Itera sobre cada columna de la fila.
        for k, v in r.items():
            if isinstance(v, str):
                v = v.strip()
            #Agrega las columnas limpias a la fila.
            #k es el nombre de la columna y v es el valor de la columna.
            #row es el diccionario que contiene las columnas limpias.
            row[k] = v
        #Agrega los metadatos a la fila.
        #_tabla es el nombre de la tabla y tabla es el nombre de la tabla.
        row["_tabla"] = tabla
        #_origen es el origen de la tabla y "erp" es el origen de la tabla.
        row["_origen"] = "erp"
        out.append(row)
    print(f"[transform normalize_erp] tabla={tabla} filas={len(out)}")
    return out

#Aplica `normalize_erp_table` a cada clave del dict del extract.
def normalize_erp_bundle(
    tables: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    """Aplica `normalize_erp_table` a cada clave del dict del extract."""
    #Itera sobre cada clave del dict del extract.
    #name es el nombre de la tabla y rows es la lista de filas de la tabla.
    #normalize_erp_table es la función que limpia las filas de la tabla.
    #{name: normalize_erp_table(rows, name) for name, rows in tables.items()} es un diccionario con las tablas limpias.
    return {name: normalize_erp_table(rows, name) for name, rows in tables.items()}
