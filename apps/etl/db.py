"""Helpers de conexión psycopg2 compartidos por extract/load."""
from __future__ import annotations

from typing import Any

import psycopg2
import psycopg2.extras


def connect(cfg: dict[str, Any]):
    """Abre conexión desde dict secret-style o DSN."""
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
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(r) for r in cur.fetchall()]
