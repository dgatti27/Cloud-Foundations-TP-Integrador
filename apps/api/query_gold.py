"""Consulta segura a schema gold (solo SELECT).

Usado por:
  - Lambda handler — runtime en LocalStack
  - Tests locales / alb-standin fallback

Parámetros de la API (GET):
  table      → nombre de tabla en gold (sin schema)
  columns    → lista separada por comas, o *
  condition  → predicado simple: col=valor | col!=valor | col>valor | col LIKE valor
               (sin ';', sin subqueries; valores parametrizados)

Defensa en profundidad:
  1) Allowlist GOLD_TABLES (nunca bronce)
  2) Identificadores validados por regex
  3) Condition parseada a placeholder %s (no concatena el valor crudo)
  4) Credencial api_reader (secret dw/rds-api) — SQL ya sin INSERT/UPDATE
"""

from __future__ import annotations

import json
import os
import re
from typing import Any

# ---------------------------------------------------------------------------
# Allowlist de tablas gold (Modelo_DW / seed RDS)
# Si no está acá → ValueError → handler responde 400. Nunca acepta bronce.*
# ---------------------------------------------------------------------------
GOLD_TABLES = frozenset(
    {
        "bridge_producto_competidor",
        "dim_campania",
        "dim_canal",
        "dim_categoria",
        "dim_cliente",
        "dim_competidor",
        "dim_dispositivo",
        "dim_fecha",
        "dim_geografia",
        "dim_hora",
        "dim_metodo_pago",
        "dim_moneda",
        "dim_pagina",
        "dim_producto",
        "fact_precio_competencia",
        "fact_venta_devolucion",
        "fact_venta_linea",
        "fact_web_evento",
        "fact_web_sesion",
    }
)

# Identificador SQL seguro (nombre de columna/tabla simple)
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# Condition: col OP valor  (OP = = != <> >= <= > < LIKE ILIKE)
_COND = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(=|!=|<>|>=|<=|>|<|LIKE|ILIKE)\s*(.+?)\s*$",
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Secrets Manager — credencial de la API
# En Lambda: SECRETS_ENDPOINT=http://host.docker.internal:4567 (MiniStack).
# Lee dw/rds-api → username/password/host/port/dbname (api_reader).
# ---------------------------------------------------------------------------
def _sm_client():
    """Cliente boto3 secretsmanager (MiniStack en Hobby; AWS real en prod)."""
    import boto3

    endpoint = os.environ.get("SECRETS_ENDPOINT")
    kwargs: dict[str, Any] = {
        "region_name": os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        "aws_access_key_id": os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        "aws_secret_access_key": os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    }
    if endpoint:
        kwargs["endpoint_url"] = endpoint
    return boto3.client("secretsmanager", **kwargs)


def rds_api_conn() -> dict[str, Any]:
    """Obtiene JSON del secret dw/rds-api; permite override de host/port (Hobby Docker)."""
    secret_name = os.environ.get("API_SECRET", "dw/rds-api")
    data = json.loads(
        _sm_client().get_secret_value(SecretId=secret_name)["SecretString"]
    )
    # Desde el container Lambda, el hostname interno de MiniStack no resuelve:
    # el demo setea RDS_HOST_OVERRIDE=host.docker.internal y puerto publicado.
    data["host"] = os.environ.get("RDS_HOST_OVERRIDE", data.get("host"))
    data["port"] = int(os.environ.get("RDS_PORT_OVERRIDE", data.get("port", 5432)))
    return data


# ---------------------------------------------------------------------------
# Conexión Postgres
# pg8000 = driver puro Python (entra fácil en el zip de Lambda en Windows).
# ---------------------------------------------------------------------------
def _connect(cfg: dict[str, Any]):
    """Abre conexión DB-API con usuario api_reader (o el del secret)."""
    import pg8000.dbapi

    return pg8000.dbapi.connect(
        user=cfg.get("username") or cfg.get("user"),
        password=cfg["password"],
        host=cfg["host"],
        port=int(cfg.get("port", 5432)),
        database=cfg.get("dbname") or cfg.get("database"),
    )


# ---------------------------------------------------------------------------
# Parsers de columns / condition (anti-inyección)
# columns: solo identificadores o * → lista o None (*).
# condition: un solo predicado; valor sale como parámetro bind (%s).
# ---------------------------------------------------------------------------
def _parse_columns(columns: str | list[str] | None) -> list[str] | None:
    """None/* → todas las columnas; CSV → lista validada."""
    if columns is None or columns == "" or columns == "*":
        return None
    if isinstance(columns, list):
        parts = columns
    else:
        parts = [c.strip() for c in str(columns).split(",") if c.strip()]
    for p in parts:
        if not _IDENT.match(p):
            raise ValueError(f"Columna inválida: {p}")
    return parts


def _parse_condition(condition: str | None) -> tuple[str | None, list[Any]]:
    """Devuelve (fragmento WHERE con %s, [valor]) o (None, [])."""
    if not condition or not str(condition).strip():
        return None, []
    raw = str(condition).strip()
    # Bloqueo grueso de SQL multi-statement / comentarios
    if ";" in raw or "--" in raw or "/*" in raw:
        raise ValueError("condition contiene tokens prohibidos")
    m = _COND.match(raw)
    if not m:
        raise ValueError(
            "condition debe ser: col=valor | col!=valor | col>valor | col LIKE valor"
        )
    col, op, val = m.group(1), m.group(2).upper(), m.group(3).strip()
    if op == "<>":
        op = "!="
    # Quitar comillas envolventes del valor literales
    if (val.startswith("'") and val.endswith("'")) or (
        val.startswith('"') and val.endswith('"')
    ):
        val = val[1:-1]
    return f'"{col}" {op} %s', [val]


# ---------------------------------------------------------------------------
# Construcción del SELECT
# Valida tabla en allowlist, arma SQL + params. limit capped a 500.
# ---------------------------------------------------------------------------
def build_select(
    table: str,
    columns: str | list[str] | None = None,
    condition: str | None = None,
    limit: int = 100,
) -> tuple[str, list[Any]]:
    """Retorna (sql, params) listo para cursor.execute. No abre conexión."""
    table = (table or "").strip()
    if table.startswith("gold."):
        table = table.split(".", 1)[1]
    if table not in GOLD_TABLES:
        raise ValueError(
            f"Tabla no permitida en gold: {table}. Allowlist: {sorted(GOLD_TABLES)[:5]}…"
        )
    cols = _parse_columns(columns)
    col_sql = ", ".join(f'"{c}"' for c in cols) if cols else "*"
    where_sql, params = _parse_condition(condition)
    limit = max(1, min(int(limit or 100), 500))
    sql = f'SELECT {col_sql} FROM gold."{table}"'
    if where_sql:
        sql += f" WHERE {where_sql}"
    sql += f" LIMIT {limit}"
    return sql, params


# ---------------------------------------------------------------------------
# API pública: ejecutar la consulta y devolver payload JSON-friendly
# Abre conexión, fetch, serializa fechas/bytes, cierra siempre (finally).
# ---------------------------------------------------------------------------
def query_gold(
    table: str,
    columns: str | list[str] | None = None,
    condition: str | None = None,
    limit: int = 100,
) -> dict[str, Any]:
    """SELECT en gold.<table>. Retorna {ok, table, row_count, sql_preview, rows}."""
    sql, params = build_select(table, columns, condition, limit)
    cfg = rds_api_conn()
    conn = _connect(cfg)
    try:
        cur = conn.cursor()
        cur.execute(sql, params)
        colnames = [d[0] for d in cur.description] if cur.description else []
        rows = cur.fetchall()
        data = [dict(zip(colnames, row)) for row in rows]
        # JSON-serializable: datetime → isoformat, bytes → str
        for item in data:
            for k, v in list(item.items()):
                if hasattr(v, "isoformat"):
                    item[k] = v.isoformat()
                elif isinstance(v, (bytes, bytearray)):
                    item[k] = v.decode("utf-8", errors="replace")
        cur.close()
        return {
            "ok": True,
            "table": f"gold.{table}",
            "row_count": len(data),
            "sql_preview": sql,
            "rows": data,
        }
    finally:
        conn.close()
