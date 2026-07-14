"""Extractor del repositorio de scraping. Conexion por host, no por API."""
from __future__ import annotations

from typing import Any

from etl.config import source_conn


def extract_scraping(dataset: str = "precios", **_) -> list[dict[str, Any]]:
    conn = source_conn("scraping")
    # TODO: leer los archivos/tabla del repo de scraping por host.
    print(f"[extract scraping] dataset={dataset}")
    return []
