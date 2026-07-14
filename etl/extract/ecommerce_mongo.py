"""Extractor del Ecommerce (MongoDB). Conexion por host, no por API."""
from __future__ import annotations

from typing import Any

from etl.config import source_conn


def extract_ecommerce(coleccion: str = "orders", **_) -> list[dict[str, Any]]:
    conn = source_conn("ecommerce-mongo")
    # TODO: from pymongo import MongoClient; client = MongoClient(conn["dsn"]) ...
    print(f"[extract ecommerce-mongo] coleccion={coleccion}")
    return []
