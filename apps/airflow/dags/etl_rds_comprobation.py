"""
================================================================================
DAG: etl_rds_comprobation  (CAMINO A — smoke de conectividad)
================================================================================

Rol
---
Prueba de punta a punta mínima:
  1) Lee secret de un origen demo (`dw/origen-demo`)
  2) Conecta y hace un SELECT trivial
  3) Escribe 1 fila en bronce.ingest_batch + bronce.raw_record
     usando secret `dw/rds-etl`

NO es el ETL de negocio ERP. No llama a `apps/pipeline/`.
Sirve para validar secrets + red + permisos del schema bronce
antes (o aparte) del camino B.

Stand-in Hobby
--------------
Misma carpeta de DAGs montada por Compose (≈ EFS /airflow/dags).

Variables de entorno esperadas (Compose → Airflow)
-------------------------------------------------
  SECRETS_ENDPOINT   URL MiniStack/Secrets (obligatoria)
  ORIGEN_SECRET      default dw/origen-demo
  RDS_HOST_OVERRIDE / RDS_PORT_OVERRIDE
                     host/puerto alcanzables desde el contenedor Airflow
                     hacia la RDS publicada (ej. host.docker.internal:15432)
"""
from __future__ import annotations

import json
import os
from datetime import datetime

import boto3
import psycopg2
from airflow import DAG
from airflow.operators.python import PythonOperator


# ---------------------------------------------------------------------------
# Secrets Manager (MiniStack)
# ---------------------------------------------------------------------------
def _sm(endpoint: str, name: str) -> dict:
    """Lee un secret JSON desde el endpoint emulado (Hobby) o AWS real."""
    client = boto3.client(
        "secretsmanager",
        endpoint_url=endpoint,
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    )
    return json.loads(client.get_secret_value(SecretId=name)["SecretString"])


# ---------------------------------------------------------------------------
# Única task: extract mínimo + load mínimo (todo en un callable)
# ---------------------------------------------------------------------------
def extract_and_load_bronce(**_):
    """Smoke end-to-end: origen demo → un INSERT en bronce."""
    sm_url = os.environ["SECRETS_ENDPOINT"]
    origen = _sm(sm_url, os.environ.get("ORIGEN_SECRET", "dw/origen-demo"))
    dest = _sm(sm_url, "dw/rds-etl")

    # --- Lectura origen demo ------------------------------------------------
    src = psycopg2.connect(
        host=origen["host"],
        port=int(origen.get("port", 5432)),
        dbname=origen.get("dbname") or origen.get("database"),
        user=origen["username"],
        password=origen["password"],
    )
    with src.cursor() as cur:
        cur.execute("SELECT current_database(), now()")
        row = cur.fetchone()
    src.close()
    payload = {
        "source_db": row[0],
        "extracted_at": str(row[1]),
        "origen": "origen-demo",
    }

    # --- Escritura bronce (RDS) ---------------------------------------------
    # Override de host/port: el secret puede traer IP interna Docker;
    # desde Airflow Compose suele usarse host.docker.internal:15432
    dest_host = os.environ.get("RDS_HOST_OVERRIDE", dest["host"])
    dest_port = int(os.environ.get("RDS_PORT_OVERRIDE", dest.get("port", 5432)))

    dst = psycopg2.connect(
        host=dest_host,
        port=dest_port,
        dbname=dest["dbname"],
        user=dest["username"],
        password=dest["password"],
    )
    with dst.cursor() as cur:
        cur.execute(
            "INSERT INTO bronce.ingest_batch (origen, row_count, status) "
            "VALUES (%s, %s, %s) RETURNING batch_id",
            ("origen-demo", 1, "loaded"),
        )
        batch_id = cur.fetchone()[0]
        # raw_record: payload JSON genérico (tabla del seed RDS, no erp_*)
        cur.execute(
            "INSERT INTO bronce.raw_record (batch_id, origen, payload) "
            "VALUES (%s, %s, %s::jsonb)",
            (batch_id, "origen-demo", json.dumps(payload)),
        )
    dst.commit()
    dst.close()
    print(f"OK bronce batch_id={batch_id}")


# ---------------------------------------------------------------------------
# Definición del DAG (una sola task)
# ---------------------------------------------------------------------------
with DAG(
    dag_id="etl_rds_comprobation",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["tp", "bronce", "grupo1"],
) as dag:
    PythonOperator(
        task_id="extract_load_bronce",
        python_callable=extract_and_load_bronce,
    )
