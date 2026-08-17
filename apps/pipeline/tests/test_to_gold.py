"""Tests unitarios — transform/to_gold (datos mock, sin DB)."""
from __future__ import annotations

from pipeline.transform.to_gold import transform_to_gold

#Test para verificar que se transforman todas las tablas correctamente.
def test_transform_to_gold_bundle_vacio():
    bundle = transform_to_gold([], [], [])
    assert set(bundle) == {
        "dim_fecha",
        "dim_canal",
        "dim_metodo_pago",
        "dim_moneda",
        "dim_cliente",
        "dim_producto",
        "fact_venta_linea",
    }
    assert bundle["fact_venta_linea"] == []

#Test para verificar que se transforman todas las tablas correctamente.
def test_transform_to_gold_mapea_dims_y_fact(mock_cliente, mock_producto, mock_venta):
    bundle = transform_to_gold([mock_cliente], [mock_producto], [mock_venta])

    assert len(bundle["dim_cliente"]) == 1
    assert bundle["dim_cliente"][0]["cliente_sk"] == 1
    assert bundle["dim_cliente"][0]["nombre"] == "Ana  García"  # to_gold no hace strip

    assert len(bundle["dim_producto"]) == 1
    assert bundle["dim_producto"][0]["producto_bk"] == "SKU-001"

    assert len(bundle["fact_venta_linea"]) == 1
    fact = bundle["fact_venta_linea"][0]
    assert fact["venta_sk"] == 100
    assert fact["fecha_sk"] == 20240601
    assert fact["cliente_sk"] == 1
    assert fact["producto_sk"] == 10
    assert fact["margen_bruto"] == 300.0  # 1000 - 700

    assert any(d["fecha_sk"] == 20240601 for d in bundle["dim_fecha"])
    assert any(d["canal_bk"] == "web" for d in bundle["dim_canal"])
    assert any(d["tipo"] == "tarjeta" for d in bundle["dim_metodo_pago"])
    assert any(d["iso"] == "ARS" for d in bundle["dim_moneda"])
