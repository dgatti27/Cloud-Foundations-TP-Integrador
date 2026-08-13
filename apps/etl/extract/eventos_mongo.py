"""Extractor de la base de Eventos (MongoDB). Conexion por host, no por API."""
from __future__ import annotations

from typing import Any

from etl.config import source_conn


def extract_eventos(coleccion: str = "events", **_) -> list[dict[str, Any]]:
    conn = source_conn("eventos-mongo")
    # TODO: leer la coleccion de eventos con pymongo.
    print(f"[extract eventos-mongo] coleccion={coleccion}")
    return []
