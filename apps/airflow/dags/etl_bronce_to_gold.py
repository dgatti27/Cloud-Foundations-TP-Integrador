"""
================================================================================
DAG: etl_bronce_to_gold  (GRUPO 2 — camino ERP de negocio)
================================================================================

Rol
---
Orquesta `apps/pipeline/` para leer el landing `bronce.erp_*` y cargar el
modelo dimensional en `gold` (6 dims + fact_venta_linea).

Prerrequisito
-------------
Debe haberse corrido con éxito `etl_erp_to_bronce` (grupo 1). Si bronce
está vacío, este DAG termina “OK” con 0 filas o falla según datos.

Orden de tasks
--------------
  extract_bronce >> transform_to_gold >> load_gold

Stand-in Hobby
--------------
DAGs: `apps/airflow/dags/` → `/opt/airflow/dags`
Logs: `apps/airflow/logs/` → `/opt/airflow/logs` (≈ EFS logs)

default_args: no usado (opcional; ver docstring del DAG grupo 1).
"""
from __future__ import annotations

from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator


# ---------------------------------------------------------------------------
# Tasks
#Extrae las tres tablas en un solo dict y guarda en memoria y las recibe el DAG
# ---------------------------------------------------------------------------
def task_extract(**context):
    """Lee bronce.erp_clientes/productos/ventas → XCom `bronce_raw`.

    Credencial: dw/rds-etl (etl_writer). Serializa tipos para XCom.
    """
    from pipeline.extract.from_bronce import extract_bronce_all

    data = extract_bronce_all()
    context["ti"].xcom_push(key="bronce_raw", value=_serialize(data))


def task_transform(**context):
    """Arma el bundle gold en memoria (dims + fact) → XCom `gold_bundle`.

    `transform_to_gold` mapea:
      clientes  → dim_cliente
      productos → dim_producto
      ventas    → fact_venta_linea + dim_fecha/canal/pago/moneda
    """
    from pipeline.transform.to_gold import transform_to_gold

    #Deserializa los datos para que puedan ser procesados por transform_to_gold.
    raw = context["ti"].xcom_pull(key="bronce_raw", task_ids="extract_bronce") or {}
    #Arma el bundle ( paquete de tablas en un solo dict en memoria) gold en memoria (dims + fact).
    bundle = transform_to_gold(
        clientes=raw.get("clientes", []),
        productos=raw.get("productos", []),
        ventas=raw.get("ventas", []),
    )
    context["ti"].xcom_push(key="gold_bundle", value=_serialize_bundle(bundle))


def task_load(**context):
    """UPSERT del bundle a gold.* (orden: dims de apoyo → maestros → fact)."""
    from pipeline.load.to_dw import load_gold_bundle

    bundle = context["ti"].xcom_pull(key="gold_bundle", task_ids="transform_to_gold") or {}
    n = load_gold_bundle(_deserialize_bundle(bundle))
    print(f"OK bronce→gold upserts={n}")


# ---------------------------------------------------------------------------
# Helpers XCom (mismo criterio que el DAG grupo 1)
# ---------------------------------------------------------------------------
def _serialize(tables: dict) -> dict:
    """Decimal/date/datetime → float/ISO para que XCom pueda guardar JSON."""
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
    """Alias semántico: el bundle gold es un dict de listas igual que tables."""
    return _serialize(bundle)


def _deserialize_bundle(bundle: dict) -> dict:
    """No reconstruye date objects; load_gold acepta str/None en fecha_carga."""
    return bundle or {}


# ---------------------------------------------------------------------------
# Definición del DAG
# ---------------------------------------------------------------------------
with DAG(
    dag_id="etl_bronce_to_gold",
    start_date=datetime(2026, 1, 1),
    schedule=None,       # solo manual
    catchup=False,
    tags=["tp", "gold", "grupo2", "erp"],
) as dag:
    t1 = PythonOperator(task_id="extract_bronce", python_callable=task_extract)
    t2 = PythonOperator(task_id="transform_to_gold", python_callable=task_transform)
    t3 = PythonOperator(task_id="load_gold", python_callable=task_load)
    t1 >> t2 >> t3
