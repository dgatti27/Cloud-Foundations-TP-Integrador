"""DAG grupo 2 (lab-extra-tp): bronce.erp_* → gold (dims + fact_venta_linea).

Tasks alineadas a etl/extract|transform|load:
  1) extract_bronce
  2) transform_to_gold
  3) load_gold
"""
from __future__ import annotations

from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator


def task_extract(**context):
    from etl.extract.from_bronce import extract_bronce_all

    data = extract_bronce_all()
    context["ti"].xcom_push(key="bronce_raw", value=_serialize(data))


def task_transform(**context):
    from etl.transform.to_gold import transform_to_gold

    raw = context["ti"].xcom_pull(key="bronce_raw", task_ids="extract_bronce") or {}
    bundle = transform_to_gold(
        clientes=raw.get("clientes", []),
        productos=raw.get("productos", []),
        ventas=raw.get("ventas", []),
    )
    context["ti"].xcom_push(key="gold_bundle", value=_serialize_bundle(bundle))


def task_load(**context):
    from etl.load.to_dw import load_gold_bundle

    bundle = context["ti"].xcom_pull(key="gold_bundle", task_ids="transform_to_gold") or {}
    n = load_gold_bundle(_deserialize_bundle(bundle))
    print(f"OK bronce→gold upserts={n}")


def _serialize(tables: dict) -> dict:
    from datetime import date, datetime as dt
    from decimal import Decimal

    out = {}
    for name, rows in tables.items():
        ser = []
        for r in rows:
            item = {}
            for k, v in r.items():
                if isinstance(v, Decimal):
                    v = float(v)
                elif isinstance(v, dt):
                    v = v.isoformat()
                elif isinstance(v, date):
                    v = v.isoformat()
                item[k] = v
            ser.append(item)
        out[name] = ser
    return out


def _serialize_bundle(bundle: dict) -> dict:
    return _serialize(bundle)


def _deserialize_bundle(bundle: dict) -> dict:
    """fecha_carga vuelve como str; load_gold acepta str/None."""
    return bundle or {}


with DAG(
    dag_id="etl_bronce_to_gold",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["tp", "gold", "grupo2", "erp"],
) as dag:
    t1 = PythonOperator(task_id="extract_bronce", python_callable=task_extract)
    t2 = PythonOperator(task_id="transform_to_gold", python_callable=task_transform)
    t3 = PythonOperator(task_id="load_gold", python_callable=task_load)
    t1 >> t2 >> t3
