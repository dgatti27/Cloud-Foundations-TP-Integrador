"""Grupo 1 — carga en schema bronce (antes: base CRUDA).

Escribe:
  bronce.ingest_batch
  bronce.erp_clientes / erp_productos / erp_ventas

Usa credencial dw/rds-etl (etl_writer).
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from etl.config import rds_etl_conn
from etl.db import connect

DDL_PATH = Path(__file__).resolve().parent.parent / "sql" / "bronce_erp_ddl.sql"

_CLIENTES_COLS = [
    "id_cliente", "codigo", "nombre", "apellido", "email", "telefono",
    "documento", "tipo_doc", "direccion", "ciudad", "provincia", "codigo_postal",
    "pais", "segmento", "tipo_cliente", "fecha_alta", "activo",
    "limite_credito", "vendedor_id", "updated_at", "batch_id",
]
_PRODUCTOS_COLS = [
    "id_producto", "sku", "ean", "nombre", "descripcion", "marca", "rubro",
    "familia", "subfamilia", "precio_lista", "costo", "stock", "unidad",
    "peso_kg", "activo", "fecha_alta", "proveedor_codigo", "alicuota_iva",
    "updated_at", "batch_id",
]
_VENTAS_COLS = [
    "id_venta", "nro_orden", "linea_nro", "id_cliente", "id_producto",
    "fecha_venta", "cantidad", "precio_unitario", "descuento", "importe_bruto",
    "importe_neto", "impuesto", "costo", "moneda", "canal", "metodo_pago",
    "sucursal", "vendedor_id", "estado", "created_at", "batch_id",
]


def ensure_bronce_erp_ddl() -> None:
    """Paso 3 del lab-extra: crea tablas ERP en bronce si no existen."""
    sql = DDL_PATH.read_text(encoding="utf-8")
    conn = connect(rds_etl_conn())
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()
        print("[load->bronce] DDL erp_* aplicado (IF NOT EXISTS)")
    finally:
        conn.close()


def _upsert(conn, table: str, cols: list[str], rows: list[dict[str, Any]], pk: str) -> int:
    if not rows:
        return 0
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    updates = ", ".join(f"{c}=EXCLUDED.{c}" for c in cols if c != pk)
    sql = (
        f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) "
        f"ON CONFLICT ({pk}) DO UPDATE SET {updates}"
    )
    values = []
    for r in rows:
        values.append(tuple(r.get(c) for c in cols))
    with conn.cursor() as cur:
        cur.executemany(sql, values)
    return len(values)


def load_to_cruda(records: list[dict[str, Any]], origen: str) -> int:
    """Compat API vieja: espera lista normalize_records (payload). No usar en lab-extra."""
    print(
        f"[load->cruda] API legacy origen={origen} filas={len(records)} "
        "(lab-extra usa load_erp_to_bronce)"
    )
    return len(records)


def load_erp_to_bronce(
    tables: dict[str, list[dict[str, Any]]],
    origen: str = "erp",
) -> int:
    """UPSERT clientes/productos/ventas en bronce + registra ingest_batch."""
    ensure_bronce_erp_ddl()
    conn = connect(rds_etl_conn())
    total = 0
    try:
        with conn.cursor() as cur:
            n = sum(len(tables.get(k, [])) for k in ("clientes", "productos", "ventas"))
            cur.execute(
                "INSERT INTO bronce.ingest_batch (origen, row_count, status) "
                "VALUES (%s, %s, %s) RETURNING batch_id",
                (origen, n, "loaded"),
            )
            batch_id = cur.fetchone()[0]

        for rows in tables.values():
            for r in rows:
                r["batch_id"] = batch_id

        total += _upsert(conn, "bronce.erp_clientes", _CLIENTES_COLS, tables.get("clientes", []), "id_cliente")
        total += _upsert(conn, "bronce.erp_productos", _PRODUCTOS_COLS, tables.get("productos", []), "id_producto")
        total += _upsert(conn, "bronce.erp_ventas", _VENTAS_COLS, tables.get("ventas", []), "id_venta")
        conn.commit()
        print(f"[load->bronce] batch_id={batch_id} filas_upsert={total}")
        return total
    finally:
        conn.close()
