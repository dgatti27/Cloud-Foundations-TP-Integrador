"""Paquete `pipeline.load` — escritura en RDS (bronce y gold).

Fachada pública:
  ensure_bronce_erp_ddl / load_erp_to_bronce  → grupo 1
  load_gold_bundle                            → grupo 2
  load_to_cruda / load_to_dw                  → stubs de compat
"""
from .to_cruda import ensure_bronce_erp_ddl, load_erp_to_bronce, load_to_cruda
from .to_dw import load_gold_bundle, load_to_dw

__all__ = [
    "ensure_bronce_erp_ddl",
    "load_erp_to_bronce",
    "load_to_cruda",
    "load_gold_bundle",
    "load_to_dw",
]
