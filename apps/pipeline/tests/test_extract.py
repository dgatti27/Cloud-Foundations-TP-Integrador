"""Tests unitarios — extract (DB mockeada con unittest.mock)."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from pipeline.extract.erp_foxpro import extract_erp, extract_erp_all
from pipeline.extract.from_bronce import extract_bronce, extract_bronce_all


def test_extract_erp_tabla_desconocida():
    with pytest.raises(ValueError, match="desconocida"):
        extract_erp("inventada")


@patch("pipeline.extract.erp_foxpro.fetch_dicts")
@patch("pipeline.extract.erp_foxpro.connect")
@patch("pipeline.extract.erp_foxpro.source_conn")
def test_extract_erp_usa_secret_y_devuelve_filas(mock_src, mock_connect, mock_fetch):
    mock_src.return_value = {"host": "postgres-erp", "username": "postgres", "password": "x", "dbname": "erp"}
    mock_connect.return_value = MagicMock()
    mock_fetch.return_value = [{"id_cliente": 1, "nombre": "Ana"}]

    rows = extract_erp("clientes")

    assert rows == [{"id_cliente": 1, "nombre": "Ana"}]
    mock_src.assert_called_once_with("erp")
    mock_fetch.assert_called_once()
    mock_connect.return_value.close.assert_called_once()


@patch("pipeline.extract.erp_foxpro.extract_erp")
def test_extract_erp_all_tres_tablas(mock_one):
    mock_one.side_effect = lambda name, **_: [{"tabla": name}]
    out = extract_erp_all()
    assert set(out) == {"clientes", "productos", "ventas"}
    assert mock_one.call_count == 3


def test_extract_bronce_tabla_desconocida():
    with pytest.raises(ValueError, match="desconocida"):
        extract_bronce("xyz")


@patch("pipeline.extract.from_bronce.fetch_dicts")
@patch("pipeline.extract.from_bronce.connect")
@patch("pipeline.extract.from_bronce.rds_etl_conn")
def test_extract_bronce_mock(mock_rds, mock_connect, mock_fetch):
    mock_rds.return_value = {"host": "localhost", "port": 15432, "dbname": "dw", "username": "etl_writer", "password": "x"}
    mock_connect.return_value = MagicMock()
    mock_fetch.return_value = [{"id_venta": 1}]

    rows = extract_bronce("ventas")
    assert rows[0]["id_venta"] == 1
    mock_connect.return_value.close.assert_called_once()


@patch("pipeline.extract.from_bronce.extract_bronce")
def test_extract_bronce_all(mock_one):
    mock_one.side_effect = lambda name, **_: []
    out = extract_bronce_all()
    assert set(out) == {"clientes", "productos", "ventas"}
