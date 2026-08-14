"""Extractores del TP.

Activos en DAGs: erp (postgres-erp) y bronce (landing RDS).
"""
from .erp_foxpro import extract_erp, extract_erp_all
from .from_bronce import extract_bronce, extract_bronce_all

EXTRACTORS = {
    "erp": extract_erp,
    "erp-foxpro": extract_erp,  # alias histórico
    "bronce": extract_bronce,
}

__all__ = [
    "EXTRACTORS",
    "extract_erp",
    "extract_erp_all",
    "extract_bronce",
    "extract_bronce_all",
]
