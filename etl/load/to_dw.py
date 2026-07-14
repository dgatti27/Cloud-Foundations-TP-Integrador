"""Grupo 2 de ETL: lee la CRUDA, transforma y carga el Datawarehouse."""
from __future__ import annotations

from etl.config import cruda_dsn, dw_dsn


def load_to_dw() -> int:
    src, dst = cruda_dsn(), dw_dsn()
    # TODO: SELECT de raw_ventas en CRUDA -> UPSERT en dim_origen / fact_ventas del DW.
    print(f"[load->dw] {src.split('@')[-1]} -> {dst.split('@')[-1]}")
    return 0
