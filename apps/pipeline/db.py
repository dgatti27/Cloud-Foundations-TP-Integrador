"""Helpers de conexión PostgreSQL (psycopg2) compartidos por extract/load.

Por qué existe
--------------
`config.py` solo *resuelve* credenciales (dict o DSN).
Este módulo *abre* la conexión y ejecuta lecturas tipadas.

Usado por:
  - extract/erp_foxpro.py, extract/from_bronce.py  → `connect` + `fetch_dicts`
  - load/to_cruda.py, load/to_dw.py               → `connect` (+ cursors propios)
"""
from __future__ import annotations

from typing import Any

import psycopg2
import psycopg2.extras


def connect(cfg: dict[str, Any]):
    """Abre una conexión psycopg2 desde el dict que entrega `config`.

    Formatos aceptados:
      {"dsn": "postgresql://..."}     → DSN completo
      {host, port, dbname, username|user, password}  → estilo Secrets Manager
    """
    if cfg.get("dsn"):
        return psycopg2.connect(cfg["dsn"])
    return psycopg2.connect(
        host=cfg["host"],
        port=int(cfg.get("port", 5432)),
        dbname=cfg.get("dbname") or cfg.get("database"),
        user=cfg.get("username") or cfg.get("user"),
        password=cfg["password"],
    )


def fetch_dicts(conn, sql: str, params=None) -> list[dict[str, Any]]:
    """Ejecuta un SELECT y devuelve lista de dicts (columna → valor).

    `RealDictCursor` hace que cada fila sea un mapping, no una tupla:
    así extract/transform trabajan con nombres de columna del ERP/bronce.
    """
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()]
