"""Tests unitarios — load (stubs + UPSERT con conexión mock)."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from pipeline.load.to_cruda import load_erp_to_bronce, load_to_cruda
from pipeline.load.to_dw import load_gold_bundle, load_to_dw

#Test para verificar que no se escribe en la base de datos cuando se carga a cruda.
def test_load_to_cruda_legacy_no_escribe_db():
    n = load_to_cruda([{"origen": "demo", "payload": {"x": 1}}], "demo")
    assert n == 1

#Test para verificar que no se hace nada cuando se carga a dw.
def test_load_to_dw_legacy_noop():
    assert load_to_dw() == 0

#Test para verificar que se hace un upsert cuando se carga a bronce.
@patch("pipeline.load.to_cruda.connect")
@patch("pipeline.load.to_cruda.rds_etl_conn")
@patch("pipeline.load.to_cruda.DDL_PATH")
def test_load_erp_to_bronce_upsert_mock(mock_ddl_path, mock_rds, mock_connect):
    mock_ddl_path.read_text.return_value = "SELECT 1"
    mock_rds.return_value = {"dsn": "postgresql://x"}
    conn = MagicMock()
    cur = MagicMock()
    cur.fetchone.return_value = (42,)  # batch_id
    conn.cursor.return_value.__enter__.return_value = cur
    mock_connect.return_value = conn

    # clean bundle sin metadatos extra problemáticos
    tables = {
        "clientes": [
            {
                "id_cliente": 1,
                "codigo": "C001",
                "nombre": "Ana",
                "apellido": "G",
                "email": None,
                "telefono": None,
                "documento": None,
                "tipo_doc": None,
                "direccion": None,
                "ciudad": None,
                "provincia": None,
                "codigo_postal": None,
                "pais": None,
                "segmento": None,
                "tipo_cliente": None,
                "fecha_alta": None,
                "activo": True,
                "limite_credito": None,
                "vendedor_id": None,
                "updated_at": None,
            }
        ],
        "productos": [],
        "ventas": [],
    }

    total = load_erp_to_bronce(tables, origen="erp")
    assert total == 1
    conn.commit.assert_called()
    conn.close.assert_called()

#Test para verificar que se carga a dw correctamente. 
@patch("pipeline.load.to_dw.connect")
@patch("pipeline.load.to_dw.rds_etl_conn")
def test_load_gold_bundle_mock(mock_rds, mock_connect, mock_cliente, mock_producto, mock_venta):
    #Importamos transform_to_gold para mockearlo.
    from pipeline.transform.to_gold import transform_to_gold

    mock_rds.return_value = {"dsn": "postgresql://x"}
    conn = MagicMock()
    cur = MagicMock()
    conn.cursor.return_value.__enter__.return_value = cur
    mock_connect.return_value = conn

    bundle = transform_to_gold([mock_cliente], [mock_producto], [mock_venta])
    total = load_gold_bundle(bundle)

    assert total > 0
    conn.commit.assert_called_once()
    conn.close.assert_called_once()
