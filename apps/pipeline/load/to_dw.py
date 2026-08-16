"""Grupo 2 — carga dimensional en schema `gold`.

Escribe (en orden de `_SPECS` (es la lista de tablas gold a cargar y cómo cargarlas. Cada elemento es una tupla))
--------------------------------
  gold.dim_fecha / dim_canal / dim_metodo_pago / dim_moneda
  gold.dim_cliente / dim_producto
  gold.fact_venta_linea

Las tablas gold las crea el seed RDS (`data/rds/seed_tp.sql`).
Este módulo solo hace UPSERT de filas ya transformadas.

Quién lo llama
--------------
DAG `etl_bronce_to_gold` → `load_gold_bundle(bundle)`.
"""
from __future__ import annotations

from typing import Any

from pipeline.config import rds_etl_conn
from pipeline.db import connect

# ---------------------------------------------------------------------------
# Especificación de carga: (tabla, primary key, columnas)
# Orden: dims de apoyo → maestros → fact (respeta FKs lógicas).
# Las tablas gold las crea el seed RDS (`data/rds/seed_tp.sql`).
# Harcodeadas porque son pocas y se conocen de antemano. Si no, con un sqlAlchemy se podría obtener automáticamente.
# ---------------------------------------------------------------------------
_SPECS: list[tuple[str, str, list[str]]] = [
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
        "segmento", "tipo", "pais", "provincia", "ciudad", "canal_origen",
        "fecha_alta", "fecha_desde", "fecha_hasta", "es_vigente", "hash_diff",
    ]),
    ("gold.dim_producto", "producto_sk", [
        "producto_sk", "producto_bk", "ean", "nombre", "marca",
        "rubro", "familia", "precio_lista", "estado", "fecha_desde",
        "fecha_hasta", "es_vigente", "hash_diff",
    ]),
    ("gold.fact_venta_linea", "venta_sk", [
        "venta_sk", "fecha_sk", "cliente_sk", "producto_sk", "canal_sk",
        "metodo_pago_sk", "moneda_sk", "nro_orden", "linea_nro",
        "cantidad", "precio_unitario", "descuento", "importe_bruto",
        "importe_neto", "impuesto", "costo", "margen_bruto",
        "batch_id", "fecha_carga",
    ]),
]


#UPSERT de una tabla gold.*.
def _upsert(conn, table: str, pk: str, cols: list[str], rows: list[dict[str, Any]]) -> int:
    """INSERT … ON CONFLICT (pk) DO UPDATE sobre una tabla gold.*."""
    if not rows:
        return 0
    placeholders = ", ".join(["%s"] * len(cols))
    # Identifiers quoted: columnas gold pueden ser case-sensitive según seed
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

#Compat: sin datos en memoria — no-op con mensaje.
def load_to_dw() -> int:
    """Compat: sin datos en memoria — no-op con mensaje."""
    print("[load->dw] usá load_gold_bundle(transformed) desde el DAG grupo 2")
    return 0

#UPSERT de todas las piezas del dict que devolvió `transform_to_gold`.
def load_gold_bundle(bundle: dict[str, list[dict[str, Any]]]) -> int:
    """UPSERT de todas las piezas del dict que devolvió `transform_to_gold`.

    `bundle` usa claves cortas (`dim_fecha`, …);
    `_SPECS` usa nombres calificados `gold.dim_fecha` → se mapean en `key_map`.
    """
    #Conecta a la base de datos.
    conn = connect(rds_etl_conn())
    total = 0
    try:
        #Mapeo de nombres de tablas.
        key_map = {
            "gold.dim_fecha": "dim_fecha",
            "gold.dim_canal": "dim_canal",
            "gold.dim_metodo_pago": "dim_metodo_pago",
            "gold.dim_moneda": "dim_moneda",
            "gold.dim_cliente": "dim_cliente",
            "gold.dim_producto": "dim_producto",
            "gold.fact_venta_linea": "fact_venta_linea",
        }
        #Itera sobre cada tabla en _SPECS.
        for table, pk, cols in _SPECS:
            #Obtiene las filas de la tabla.
            rows = bundle.get(key_map[table], [])
            #UPSERT de la tabla.
            n = _upsert(conn, table, pk, cols, rows)
            #Suma el número de filas upsertadas.
            total += n
            print(f"  [load->gold] {table}: {n}")
        #Confirma la transacción.
        conn.commit()
        #Imprime el total de upserts.
        print(f"[load->gold] total upserts={total}")
        return total
    finally:
        conn.close()
