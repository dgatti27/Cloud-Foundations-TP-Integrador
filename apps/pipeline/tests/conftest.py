"""Fixtures y path para importar el paquete `pipeline` sin instalarlo."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

# apps/ en PYTHONPATH → `from pipeline...`
_APPS = Path(__file__).resolve().parents[2]
if str(_APPS) not in sys.path:
    sys.path.insert(0, str(_APPS))

#Fixtures para mockear datos de prueba.
@pytest.fixture
def mock_cliente() -> dict:
    return {
        "id_cliente": 1,
        "codigo": "C001",
        "nombre": " Ana ",
        "apellido": "García",
        "email": "ana@mail.com",
        "segmento": "retail",
        "tipo_cliente": "B2C",
        "pais": "Argentina",
        "provincia": "CABA",
        "ciudad": "CABA",
        "fecha_alta": "2023-01-10",
    }

#Fixture para mockear datos de prueba de producto.
@pytest.fixture
def mock_producto() -> dict:
    return {
        "id_producto": 10,
        "sku": "SKU-001",
        "ean": "7790001000001",
        "nombre": " Notebook ",
        "marca": "TechBrand",
        "rubro": "Electrónica",
        "familia": "Computación",
        "precio_lista": 1000.0,
        "activo": True,
        "fecha_alta": "2023-01-01",
    }

#Fixture para mockear datos de prueba de venta.
@pytest.fixture
def mock_venta() -> dict:
    return {
        "id_venta": 100,
        "nro_orden": "OV-1001",
        "linea_nro": 1,
        "id_cliente": 1,
        "id_producto": 10,
        "fecha_venta": "2024-06-01",
        "cantidad": 1,
        "precio_unitario": 1000.0,
        "descuento": 0,
        "importe_bruto": 1000.0,
        "importe_neto": 826.45,
        "impuesto": 173.55,
        "costo": 700.0,
        "moneda": "ARS",
        "canal": "web",
        "metodo_pago": "tarjeta",
        "batch_id": 1,
    }

#Fixture para mockear datos de prueba de bundle ERP.
@pytest.fixture
def mock_erp_bundle(mock_cliente, mock_producto, mock_venta) -> dict:
    return {
        "clientes": [mock_cliente],
        "productos": [mock_producto],
        "ventas": [mock_venta],
    }
