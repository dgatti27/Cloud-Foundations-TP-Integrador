"""Extractor grupo 1: ERP → datos origen en memoria.

Contexto
--------
Aunque el archivo se llama `erp_foxpro`,
el origen real en Compose es Postgres `postgres-erp` con tablas
"Clientes", "Productos", "Ventas" (ver `erp/seed_erp.sql`).
Simulando ser la base de datos orgien del ERP.

Credencial: `pipeline.config.source_conn("erp")` → secret `dw/erp`.

Quién lo llama
--------------
DAG `etl_erp_to_bronce` → task `extract_erp` → `extract_erp_all()`.
"""
from __future__ import annotations

from typing import Any

from pipeline.config import source_conn
from pipeline.db import connect, fetch_dicts

# ---------------------------------------------------------------------------
# Catálogo de tablas del origen
# Identifiers entre comillas: el seed usa mayúsculas ("Clientes", …).
# Son pocas tablas por eso se harcodea. Si no, con un sqlAlchemy se podría obtener automáticamente.
# ---------------------------------------------------------------------------
ERP_TABLES = {
    "clientes": 'SELECT * FROM "Clientes" ORDER BY id_cliente',
    "productos": 'SELECT * FROM "Productos" ORDER BY id_producto',
    "ventas": 'SELECT * FROM "Ventas" ORDER BY id_venta',
}


def extract_erp(tabla: str = "ventas", **_) -> list[dict[str, Any]]:
    """Lee UNA tabla del ERP y la devuelve como lista de dicts.

    Parámetros
    ----------
    tabla : str
        Una de: clientes | productos | ventas.
    **_ :
        Ignorado; permite que Airflow pase context args sin romper.
    """
    table = tabla.lower().strip()
    if table not in ERP_TABLES:
        raise ValueError(f"Tabla ERP desconocida: {tabla}. Usá: {list(ERP_TABLES)}")

    conn_cfg = source_conn("erp")
    conn = connect(conn_cfg)
    try:
        # Ejecuta la consulta (trae registros) y devuelve los resultados como lista de dicts (fila → valor).
        # fetch_dicts es un helper en db.py que usa psycopg2 para ejecutar la consulta y devolver los resultados como lista de dicts.
        rows = fetch_dicts(conn, ERP_TABLES[table])
        print(f"[extract erp] tabla={table} filas={len(rows)} host={conn_cfg.get('host', conn_cfg.get('dsn'))}")
        return rows
    finally:
        # Siempre cerrar: extractores no dejan conexiones abiertas al DAG
        conn.close()

#Agrupa las tres tablas en un solo dict y guarda en memoria
#Retorna un dict con las tres tablas como listas de dicts y el DAG las recibe y las pasa al XCom (mecanismo para pasar datos entre tareas de un mismo DAG)
def extract_erp_all(**_) -> dict[str, list[dict[str, Any]]]:
    """Extrae las tres tablas en un solo dict (entrada del normalize grupo 1).

    Retorno típico:
      {
        "clientes":  [ {...}, ... ],
        "productos": [ {...}, ... ],
        "ventas":    [ {...}, ... ],
      }
    """
    return {name: extract_erp(name) for name in ERP_TABLES}
