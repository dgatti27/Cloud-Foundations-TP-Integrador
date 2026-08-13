"""ALB stand-in (Hobby): entrada “pública” HTTPS/HTTP → invoca Lambda en LocalStack.

En AWS real: ALB en subnets public-alb-* (sg-alb) → target Lambda en
private-compute-* (sg-api). LocalStack Hobby no incluye ELB → este servicio
Docker simula esa capa perimetral para Postman.
"""
from __future__ import annotations

import json
import os
from typing import Any

import boto3
from flask import Flask, Request, jsonify, request

app = Flask(__name__)

LS_ENDPOINT = os.environ.get("LOCALSTACK_ENDPOINT", "http://localstack-integrador:4566")
FUNCTION_NAME = os.environ.get("LAMBDA_FUNCTION_NAME", "tp-gold-api")
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")


def _lambda():
    return boto3.client(
        "lambda",
        endpoint_url=LS_ENDPOINT,
        region_name=REGION,
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    )


def _event_from_request(req: Request) -> dict[str, Any]:
    return {
        "httpMethod": req.method,
        "path": req.path,
        "queryStringParameters": {k: v for k, v in req.args.items()},
        "headers": {k: v for k, v in req.headers.items()},
        "body": req.get_data(as_text=True) or None,
        "isBase64Encoded": False,
        "requestContext": {"elb": {"targetGroupArn": "arn:aws:elasticloadbalancing:stand-in"}},
    }


@app.get("/health")
def health():
    return jsonify({"ok": True, "stand_in": "alb", "target": FUNCTION_NAME})


@app.get("/gold/query")
@app.post("/gold/query")
def gold_query():
    """Misma ruta que expondría el ALB → Lambda en el to-be."""
    event = _event_from_request(request)
    # Merge JSON body fields into queryStringParameters for GET-like handling
    if request.is_json:
        body = request.get_json(silent=True) or {}
        q = dict(event["queryStringParameters"] or {})
        for k in ("table", "tabla", "columns", "columnas", "condition", "condicion", "limit", "limite"):
            if k in body and k not in q:
                q[k] = body[k] if not isinstance(body[k], list) else ",".join(map(str, body[k]))
        event["queryStringParameters"] = q
        event["body"] = json.dumps(body)

    resp = _lambda().invoke(
        FunctionName=FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps(event).encode("utf-8"),
    )
    raw = resp["Payload"].read()
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return jsonify({"ok": False, "error": "invalid lambda payload", "raw": raw.decode()}), 502

    # Si la Lambda ya devolvió formato proxy (statusCode/body)
    if isinstance(payload, dict) and "statusCode" in payload:
        body = payload.get("body")
        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                pass
        return jsonify(body), int(payload.get("statusCode", 200))

    return jsonify(payload), 200


if __name__ == "__main__":
    # 8088 HTTP (Postman fácil). En AWS real sería :443 TLS terminado en ALB.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8088")))
