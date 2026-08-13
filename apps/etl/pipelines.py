"""Pipelines listos para invocar desde DAGs Airflow."""
from __future__ import annotations

from etl.extract.erp_foxpro import extract_erp_all
from etl.extract.from_bronce import extract_bronce_all
from etl.load.to_cruda import ensure_bronce_erp_ddl, load_erp_to_bronce
from etl.load.to_dw import load_gold_bundle
from etl.transform.normalize import normalize_erp_bundle
from etl.transform.to_gold import transform_to_gold


def run_erp_to_bronce(**_) -> int:
    """Grupo 1: ERP Postgres → bronce.erp_*."""
    ensure_bronce_erp_ddl()
    raw = extract_erp_all()
    clean = normalize_erp_bundle(raw)
    return load_erp_to_bronce(clean, origen="erp")


def run_bronce_to_gold(**_) -> int:
    """Grupo 2: bronce.erp_* → gold dims + fact_venta_linea."""
    raw = extract_bronce_all()
    bundle = transform_to_gold(
        clientes=raw["clientes"],
        productos=raw["productos"],
        ventas=raw["ventas"],
    )
    return load_gold_bundle(bundle)
