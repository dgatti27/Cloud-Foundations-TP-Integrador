"""Paquete `pipeline.transform` — limpieza (grupo 1) y modelado gold (grupo 2).

Fachada pública:
  normalize_records / normalize_erp_*  → antes de escribir bronce
  transform_to_gold                    → antes de escribir gold
"""
from .normalize import normalize_erp_bundle, normalize_erp_table, normalize_records
from .to_gold import transform_to_gold

__all__ = [
    "normalize_records",
    "normalize_erp_table",
    "normalize_erp_bundle",
    "transform_to_gold",
]
