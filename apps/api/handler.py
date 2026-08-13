"""Lambda tp-gold-api — GET de solo lectura sobre schema gold.

Punto de entrada de la función (Handler = handler.lambda_handler).
No habla con RDS directo: delega en query_gold.query_gold (secret dw/rds-api).

Eventos soportados:
  1) API Gateway / ALB stand-in (HTTP):
       queryStringParameters: table, columns, condition, limit
  2) Invoke directo (JSON):
       {"table": "...", "columns": "...", "condition": "...", "limit": 50}

Respuesta HTTP: statusCode + headers + body JSON.
  200 ok | 400 validación | 500 error inesperado.
Nunca escribe en DB; usa api_reader vía query_gold.
"""

from __future__ import annotations

import json
from typing import Any

from query_gold import query_gold


# ---------------------------------------------------------------------------
# Adaptador de evento → parámetros de API
# Normaliza tres formas de entrada (ALB/API GW query, body JSON, invoke plano)
# a un dict {table, columns, condition, limit}. Acepta alias en español.
# ---------------------------------------------------------------------------
def _params_from_event(event: dict[str, Any]) -> dict[str, Any]:
    """Extrae table/columns/condition/limit del event de Lambda."""
    if not isinstance(event, dict):
        return {}
    # 1) ALB / API Gateway: query string (?table=...&columns=...)
    q = event.get("queryStringParameters") or event.get("query") or {}
    if q:
        return {
            "table": q.get("table") or q.get("tabla"),
            "columns": q.get("columns") or q.get("columnas"),
            "condition": q.get("condition") or q.get("condicion"),
            "limit": q.get("limit") or q.get("limite") or 100,
        }
    # 2) Body JSON (string o dict) — p. ej. POST o proxy
    body = event.get("body")
    if isinstance(body, str) and body.strip():
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            body = {}
    if isinstance(body, dict) and body:
        return {
            "table": body.get("table") or body.get("tabla"),
            "columns": body.get("columns") or body.get("columnas"),
            "condition": body.get("condition") or body.get("condicion"),
            "limit": body.get("limit") or body.get("limite") or 100,
        }
    # 3) Invoke directo: campos en la raíz del event
    return {
        "table": event.get("table") or event.get("tabla"),
        "columns": event.get("columns") or event.get("columnas"),
        "condition": event.get("condition") or event.get("condicion"),
        "limit": event.get("limit") or event.get("limite") or 100,
    }


# ---------------------------------------------------------------------------
# Envelope HTTP de respuesta (compatible ALB / API GW / invoke)
# body siempre string JSON; CORS abierto para Postman.
# ---------------------------------------------------------------------------
def _response(status: int, payload: dict[str, Any]) -> dict[str, Any]:
    """Arma {statusCode, headers, body} para el runtime Lambda."""
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload, default=str),
    }


# ---------------------------------------------------------------------------
# Handler (se ejecuta en CADA invocación)
# Flujo: parse event → log request (CW) → query_gold → log response → HTTP.
# print(...) → CloudWatch Logs /aws/lambda/tp-gold-api (exportable a MinIO).
# ---------------------------------------------------------------------------
def lambda_handler(event, context):  # noqa: ANN001
    """Entry point Lambda. context trae aws_request_id, timeout remaining, etc."""
    request_id = getattr(context, "aws_request_id", None)
    try:
        p = _params_from_event(event or {})
        # Audit: qué pidió el cliente (sin filas sensibles)
        print(
            json.dumps(
                {
                    "event": "gold_query_request",
                    "request_id": request_id,
                    "table": p.get("table"),
                    "columns": p.get("columns"),
                    "condition": p.get("condition"),
                    "limit": p.get("limit"),
                },
                default=str,
            )
        )
        if not p.get("table"):
            print(
                json.dumps(
                    {
                        "event": "gold_query_response",
                        "request_id": request_id,
                        "status": 400,
                        "error": "missing_table",
                    }
                )
            )
            return _response(
                400,
                {
                    "ok": False,
                    "error": "Falta 'table' (o 'tabla'). Ej: table=dim_cliente&columns=nombre,email&condition=segmento=retail",
                },
            )
        # Negocio: SELECT seguro en gold (allowlist + params en query_gold)
        result = query_gold(
            table=str(p["table"]),
            columns=p.get("columns"),
            condition=p.get("condition"),
            limit=int(p.get("limit") or 100),
        )
        print(
            json.dumps(
                {
                    "event": "gold_query_response",
                    "request_id": request_id,
                    "status": 200,
                    "table": result.get("table"),
                    "row_count": result.get("row_count"),
                    "ok": result.get("ok"),
                },
                default=str,
            )
        )
        return _response(200, result)
    except ValueError as e:
        # Validación (tabla fuera de allowlist, condition inválida, etc.)
        print(
            json.dumps(
                {
                    "event": "gold_query_response",
                    "request_id": request_id,
                    "status": 400,
                    "error": str(e),
                }
            )
        )
        return _response(400, {"ok": False, "error": str(e)})
    except Exception as e:  # noqa: BLE001 — superficie API controlada
        # No filtrar stack al cliente; sí tipificar en logs/body
        print(
            json.dumps(
                {
                    "event": "gold_query_response",
                    "request_id": request_id,
                    "status": 500,
                    "error": type(e).__name__,
                    "detail": str(e),
                }
            )
        )
        return _response(500, {"ok": False, "error": type(e).__name__, "detail": str(e)})
