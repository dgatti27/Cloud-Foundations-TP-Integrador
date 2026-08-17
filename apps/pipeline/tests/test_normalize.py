"""Tests unitarios — transform/normalize (datos mock, sin DB)."""
from __future__ import annotations

from datetime import date
from decimal import Decimal

from pipeline.transform.normalize import (
    normalize_erp_bundle,
    normalize_erp_table,
    normalize_records,
)

#Test para verificar que se envuelve el payload y se convierten los tipos de datos correctamente.
def test_normalize_records_envuelve_payload_y_castea_tipos():
    raw = [{"id": 1, "monto": Decimal("10.5"), "fecha": date(2024, 6, 1)}]
    out = normalize_records(raw, "demo")

    assert len(out) == 1
    assert out[0]["origen"] == "demo"
    assert out[0]["payload"]["monto"] == 10.5
    assert out[0]["payload"]["fecha"] == "2024-06-01"

#Test para verificar que se quitan los y metadatos correctamente.
def test_normalize_erp_table_strip_y_metadatos(mock_cliente):
    rows = normalize_erp_table([mock_cliente], "clientes")

    assert len(rows) == 1
    assert rows[0]["nombre"] == "Ana"  # strip
    assert rows[0]["_tabla"] == "clientes"
    assert rows[0]["_origen"] == "erp"
    assert rows[0]["id_cliente"] == 1


#Test para verificar que se normalizan todas las tablas correctamente.
def test_normalize_erp_bundle_todas_las_tablas(mock_erp_bundle):
    clean = normalize_erp_bundle(mock_erp_bundle)

    assert set(clean) == {"clientes", "productos", "ventas"}
    assert clean["productos"][0]["nombre"] == "Notebook"
    assert clean["ventas"][0]["_tabla"] == "ventas"
