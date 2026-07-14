"""Transformaciones comunes: limpieza y normalizacion a un esquema uniforme."""
from __future__ import annotations

from typing import Any


def normalize_records(records: list[dict[str, Any]], origen: str) -> list[dict[str, Any]]:
    """Normaliza los registros crudos a un formato uniforme para el DW.

    TODO: mapear campos de cada origen a un esquema comun, castear tipos,
    resolver fechas/monedas, deduplicar.
    """
    out = []
    for r in records:
        out.append({"origen": origen, "payload": r})
    return out
