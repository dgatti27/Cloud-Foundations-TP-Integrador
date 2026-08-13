"""DAG grupo 1 (camino B): ERP Postgres → schema bronce.

Ubicación OBLIGATORIA: apps/airflow/dags/  (≈ EFS access point /airflow/dags).
Los logs de cada run van a apps/airflow/logs/ (≈ EFS /airflow/logs).
No mover este archivo fuera del stand-in: scheduler y webserver solo ven ese mount.

Lógica de negocio: paquete etl/. Este archivo solo orquesta tasks:
  1) ensure_bronce_ddl
  2) extract_erp
  3) transform_normalize
  4) load_bronce
"""
from __future__ import annotations

from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator


def task_ensure_ddl(**_):
    from etl.load.to_cruda import ensure_bronce_erp_ddl

    ensure_bronce_erp_ddl()


def task_extract(**context):
    from etl.extract.erp_foxpro import extract_erp_all

    data = extract_erp_all()
    # XCom: fechas/Decimal no siempre serializan; convertimos vía normalize ya en transform.
    context["ti"].xcom_push(key="erp_raw", value=_serialize(data))


def task_transform(**context):
    from etl.transform.normalize import normalize_erp_bundle

    raw = _deserialize(context["ti"].xcom_pull(key="erp_raw", task_ids="extract_erp"))
    clean = normalize_erp_bundle(raw)
    context["ti"].xcom_push(key="erp_clean", value=_serialize(clean))


def task_load(**context):
    from etl.load.to_cruda import load_erp_to_bronce

    clean = _deserialize(context["ti"].xcom_pull(key="erp_clean", task_ids="transform_normalize"))
    n = load_erp_to_bronce(clean, origen="erp")
    print(f"OK erp→bronce filas={n}")


def _serialize(tables: dict) -> dict:
    """JSON-friendly: dates/decimals → str/float."""
    from datetime import date, datetime
    from decimal import Decimal

    out = {}
    for name, rows in tables.items():
        ser = []
        for r in rows:
            item = {}
            for k, v in r.items():
                if isinstance(v, Decimal):
                    v = float(v)
                elif isinstance(v, datetime):
                    v = v.isoformat()
                elif isinstance(v, date):
                    v = v.isoformat()
                item[k] = v
            ser.append(item)
        out[name] = ser
    return out


def _deserialize(tables: dict) -> dict:
    """Rehidrata fechas ISO → date donde aplica (load acepta str ISO también)."""
    return tables or {}


with DAG(
    dag_id="etl_erp_to_bronce",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["tp", "bronce", "grupo1", "erp"],
) as dag:
    t0 = PythonOperator(task_id="ensure_bronce_ddl", python_callable=task_ensure_ddl)
    t1 = PythonOperator(task_id="extract_erp", python_callable=task_extract)
    t2 = PythonOperator(task_id="transform_normalize", python_callable=task_transform)
    t3 = PythonOperator(task_id="load_bronce", python_callable=task_load)
    t0 >> t1 >> t2 >> t3
