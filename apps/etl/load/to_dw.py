"""Grupo 2 — carga dimensional en schema gold (Modelo_DW)."""
from __future__ import annotations

from typing import Any

from etl.config import rds_etl_conn
from etl.db import connect

# (tabla, pk, columnas)
_SPECS: list[tuple[str, str, list[str]]] = [
    ("gold.dim_geografia", "geografia_sk", [
        "geografia_sk", "pais", "provincia", "ciudad", "codigo_postal",
    ]),
    ("gold.dim_categoria", "categoria_sk", [
        "categoria_sk", "categoria_bk", "rubro", "familia", "subfamilia",
    ]),
    ("gold.dim_fecha", "fecha_sk", [
        "fecha_sk", "fecha", "anio", "trimestre", "mes", "nombre_mes",
        "dia", "dia_semana", "semana_anio", "es_finde", "es_feriado",
    ]),
    ("gold.dim_canal", "canal_sk", [
        "canal_sk", "canal_bk", "nombre", "tipo",
    ]),
    ("gold.dim_metodo_pago", "metodo_pago_sk", [
        "metodo_pago_sk", "tipo", "tarjeta", "cuotas",
    ]),
    ("gold.dim_moneda", "moneda_sk", [
        "moneda_sk", "iso", "simbolo", "tipo_cambio_ref",
    ]),
    ("gold.dim_cliente", "cliente_sk", [
        "cliente_sk", "cliente_bk", "id_unificado", "nombre", "email",
        "segmento", "tipo", "geografia_sk", "canal_origen", "fecha_alta",
        "fecha_desde", "fecha_hasta", "es_vigente", "hash_diff",
    ]),
    ("gold.dim_producto", "producto_sk", [
        "producto_sk", "producto_bk", "ean", "nombre", "marca",
        "categoria_sk", "precio_lista", "estado", "fecha_desde",
        "fecha_hasta", "es_vigente", "hash_diff",
    ]),
    ("gold.fact_venta_linea", "venta_sk", [
        "venta_sk", "fecha_sk", "cliente_sk", "producto_sk", "canal_sk",
        "metodo_pago_sk", "geografia_sk", "moneda_sk", "nro_orden",
        "linea_nro", "cantidad", "precio_unitario", "descuento",
        "importe_bruto", "importe_neto", "impuesto", "costo",
        "margen_bruto", "batch_id", "fecha_carga",
    ]),
]


def _upsert(conn, table: str, pk: str, cols: list[str], rows: list[dict[str, Any]]) -> int:
    if not rows:
        return 0
    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(f'"{c}"' for c in cols)
    updates = ", ".join(f'"{c}"=EXCLUDED."{c}"' for c in cols if c != pk)
    sql = (
        f'INSERT INTO {table} ({col_list}) VALUES ({placeholders}) '
        f'ON CONFLICT ("{pk}") DO UPDATE SET {updates}'
    )
    values = [tuple(r.get(c) for c in cols) for r in rows]
    with conn.cursor() as cur:
        cur.executemany(sql, values)
    return len(values)


def load_to_dw() -> int:
    """Compat: sin datos en memoria — no-op con mensaje."""
    print("[load->dw] usá load_gold_bundle(transformed) desde el DAG grupo 2")
    return 0


def load_gold_bundle(bundle: dict[str, list[dict[str, Any]]]) -> int:
    """UPSERT de todas las piezas transformadas hacia gold.*."""
    conn = connect(rds_etl_conn())
    total = 0
    try:
        key_map = {
            "gold.dim_geografia": "dim_geografia",
            "gold.dim_categoria": "dim_categoria",
            "gold.dim_fecha": "dim_fecha",
            "gold.dim_canal": "dim_canal",
            "gold.dim_metodo_pago": "dim_metodo_pago",
            "gold.dim_moneda": "dim_moneda",
            "gold.dim_cliente": "dim_cliente",
            "gold.dim_producto": "dim_producto",
            "gold.fact_venta_linea": "fact_venta_linea",
        }
        for table, pk, cols in _SPECS:
            rows = bundle.get(key_map[table], [])
            n = _upsert(conn, table, pk, cols, rows)
            total += n
            print(f"  [load->gold] {table}: {n}")
        conn.commit()
        print(f"[load->gold] total upserts={total}")
        return total
    finally:
        conn.close()
