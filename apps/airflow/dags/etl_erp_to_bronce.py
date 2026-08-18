"""
================================================================================
DAG: etl_erp_to_bronce  (GRUPO 1 — camino ERP de negocio)
================================================================================

Rol
---
Orquesta el paquete `apps/pipeline/` para llevar datos del Postgres origen
(`postgres-erp`) al schema `bronce` de la RDS MiniStack.

Stand-in Hobby
--------------
En Compose, este archivo vive en `apps/airflow/dags/` y se monta en
`/opt/airflow/dags` (≈ access point EFS de DAGs en AWS Fargate).
La lógica de datos NO está acá: está en `pipeline.extract|transform|load`.

Orden de tasks (obligatorio)
----------------------------
  ensure_bronce_ddl >> extract_erp >> transform_normalize >> load_bronce

Cómo dispararlo
---------------
  schedule="@once" → una corrida automática cuando el scheduler arranca
  (espera RDS/secrets en `wait_for_infra`). Al terminar OK dispara
  `etl_bronce_to_gold`. También podés trigger manual desde la UI.

default_args
------------
No se usa: no es obligatorio. El TP no necesita retries/owner compartidos.
"""
from __future__ import annotations

from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.trigger_dagrun import TriggerDagRunOperator


# ---------------------------------------------------------------------------
# Tasks — cada una importa pipeline *dentro* de la función
# (evita fallar el parseo del DAG si el worker aún no tiene deps listas)
# ---------------------------------------------------------------------------
def task_wait_for_infra(**_):
    """Espera a que existan secrets + RDS tras `tofu apply` (poll cada 15 s).

    MiniStack publica RDS en 15432/15433/…; si `.env` quedó desfasado,
    prueba esos puertos y deja `RDS_PORT_OVERRIDE` para las tasks siguientes
    (LocalExecutor = mismo proceso del scheduler).
    """
    import os
    import time

    try:
        import boto3  # noqa: F401
        import psycopg2  # noqa: F401
        from pipeline.config import from_secrets, rds_etl_conn, source_conn
        from pipeline.db import connect
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            f"Falta dependencia en el scheduler ({exc}). "
            "Recreá Airflow: docker compose up -d --force-recreate "
            "airflow-scheduler airflow-webserver "
            "(compose instala boto3 + psycopg2 vía _PIP_ADDITIONAL_REQUIREMENTS)."
        ) from exc

    primary = int(os.environ.get("RDS_PORT_OVERRIDE", "15432"))
    rds_ports: list[int] = []
    for port in (primary, 15432, 15433, 15434, 15435):
        if port not in rds_ports:
            rds_ports.append(port)

    deadline = time.time() + 900
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            etl = from_secrets("dw/rds-etl")
            erp = from_secrets("dw/erp")
            print(
                f"Secrets OK  etl_host={etl.get('host')} erp_host={erp.get('host')} "
                f"override={os.environ.get('RDS_HOST_OVERRIDE')} "
                f"ports={rds_ports}"
            )

            rds_ok = False
            rds_err: Exception | None = None
            for port in rds_ports:
                os.environ["RDS_PORT_OVERRIDE"] = str(port)
                try:
                    with connect(rds_etl_conn()) as conn:
                        with conn.cursor() as cur:
                            cur.execute("SELECT 1")
                    print(f"RDS OK en puerto {port}")
                    rds_ok = True
                    break
                except Exception as exc:
                    rds_err = exc
                    print(f"RDS puerto {port}: {exc}")
            if not rds_ok:
                raise rds_err or RuntimeError("RDS no respondió en ningún puerto")

            with connect(source_conn("erp")) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
            print("Infra lista (secrets + RDS + ERP)")
            return
        except Exception as exc:
            last_err = exc
            print(f"Infra aún no lista ({exc}); reintento en 15 s…")
            time.sleep(15)
    raise TimeoutError(f"Infra no disponible tras 15 min: {last_err}")


def task_ensure_ddl(**_):
    """Crea tablas bronce.erp_* / ingest_batch si no existen (DDL idempotente)."""
    from pipeline.load.to_cruda import ensure_bronce_erp_ddl

    ensure_bronce_erp_ddl()


def task_extract(**context):
    """Lee Clientes/Productos/Ventas del ERP → dict en memoria → XCom `erp_raw`.

    `context["ti"]` = TaskInstance de Airflow; XCom pasa datos a la task siguiente.
    `_serialize` convierte Decimal/date a tipos JSON-safe antes del push.
    """
    from pipeline.extract.erp_foxpro import extract_erp_all

    data = extract_erp_all()
    #Serializa los datos para que puedan ser guardados en XCom.
    context["ti"].xcom_push(key="erp_raw", value=_serialize(data))


def task_transform(**context):
    """Limpieza ligera (strip, metadatos). NO modela gold todavía.

    Pull de XCom `erp_raw` (task extract_erp) → push `erp_clean`.
    """
    from pipeline.transform.normalize import normalize_erp_bundle

    #Deserializa los datos para que puedan ser procesados por normalize_erp_bundle.
    #XCom: el metadata DB de Airflow serializa valores como JSON.
    raw = _deserialize(context["ti"].xcom_pull(key="erp_raw", task_ids="extract_erp"))
    clean = normalize_erp_bundle(raw)
    context["ti"].xcom_push(key="erp_clean", value=_serialize(clean))


def task_load(**context):
    """UPSERT a bronce.erp_* + registro en ingest_batch (credencial dw/rds-etl)."""
    from pipeline.load.to_cruda import load_erp_to_bronce

    clean = _deserialize(context["ti"].xcom_pull(key="erp_clean", task_ids="transform_normalize"))
    n = load_erp_to_bronce(clean, origen="erp")
    print(f"OK erp→bronce filas={n}")


# ---------------------------------------------------------------------------
# Helpers XCom — el metadata DB de Airflow serializa valores como JSON
#Serializa los datos para que puedan ser guardados en XCom.
#Decimal → float ; date/datetime → ISO string. Evita TypeError en xcom_push.
# ---------------------------------------------------------------------------
def _serialize(tables: dict) -> dict:
    """Decimal → float ; date/datetime → ISO string. Evita TypeError en xcom_push."""
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
    """XCom ya devolvió dict; solo normaliza None → {}."""
    return tables or {}


# ---------------------------------------------------------------------------
# Definición del DAG
# ---------------------------------------------------------------------------
# start_date  → desde cuándo Airflow considera el DAG “activo” (histórico)
# schedule    → @once = una corrida al activar el scheduler (post infra)
# catchup     → False = no rellena corridas pasadas al activarlo
# tags        → filtros en la UI
with DAG(
    dag_id="etl_erp_to_bronce",
    start_date=datetime(2026, 1, 1),
    schedule="@once",
    catchup=False,
    is_paused_upon_creation=False,
    max_active_runs=1,
    tags=["tp", "bronce", "grupo1", "erp"],
) as dag:
    t_wait = PythonOperator(task_id="wait_for_infra", python_callable=task_wait_for_infra)
    t0 = PythonOperator(task_id="ensure_bronce_ddl", python_callable=task_ensure_ddl)
    t1 = PythonOperator(task_id="extract_erp", python_callable=task_extract)
    t2 = PythonOperator(task_id="transform_normalize", python_callable=task_transform)
    t3 = PythonOperator(task_id="load_bronce", python_callable=task_load)
    t4 = TriggerDagRunOperator(
        task_id="trigger_bronce_to_gold",
        trigger_dag_id="etl_bronce_to_gold",
        wait_for_completion=True,
        poke_interval=15,
    )

    t_wait >> t0 >> t1 >> t2 >> t3 >> t4
