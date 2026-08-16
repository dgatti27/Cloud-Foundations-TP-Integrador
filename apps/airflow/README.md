# Orquestación Airflow (stand-in Hobby ≈ Fargate + EFS)

En AWS real: DAGs/logs en EFS montado por las tasks Fargate.  
En este TP: la misma idea con volúmenes Compose.

```text
apps/airflow/
├── dags/     → montado en /opt/airflow/dags   (código de orquestación)
└── logs/     → montado en /opt/airflow/logs   (runtime; suele estar en .gitignore)
```

El paquete de negocio **no** vive acá: está en `apps/pipeline/` y Compose lo
monta en `/opt/airflow/packages/pipeline` (`PYTHONPATH=/opt/airflow/packages`).

Detalle del flujo ERP → gold: [`apps/pipeline/README.md`](../pipeline/README.md).

---

## DAGs

| Archivo | `dag_id` | Camino | Qué hace |
|---|---|---|---|
| [`dags/etl_rds_comprobation.py`](./dags/etl_rds_comprobation.py) | `etl_rds_comprobation` | A (smoke) | Secrets + INSERT mínimo en `bronce.raw_record`. **No** usa `pipeline/`. |
| [`dags/etl_erp_to_bronce.py`](./dags/etl_erp_to_bronce.py) | `etl_erp_to_bronce` | B grupo 1 | ERP Postgres → `bronce.erp_*` vía `pipeline` |
| [`dags/etl_bronce_to_gold.py`](./dags/etl_bronce_to_gold.py) | `etl_bronce_to_gold` | B grupo 2 | `bronce.erp_*` → `gold.*` vía `pipeline` |

### Orden camino B (negocio)

```text
etl_erp_to_bronce  →  etl_bronce_to_gold
```

Ambos tienen `schedule=None`: solo trigger manual (UI o CLI).

### Camino A vs B

| | Camino A | Camino B |
|---|---|---|
| DAG | `etl_rds_comprobation` | `etl_erp_to_bronce` luego `etl_bronce_to_gold` |
| Origen | secret `dw/origen-demo` | `postgres-erp` + secret `dw/erp` |
| Destino | `bronce.ingest_batch` + `raw_record` | `bronce.erp_*` → `gold` (dims + fact) |
| Código | inline en el DAG | `apps/pipeline/` |

---

## Anatomía de un DAG de este TP

1. **Docstring** del archivo: rol, orden de tasks, stand-in.
2. **Callables** (`task_*`): importan `pipeline` *dentro* de la función.
3. **XCom** (solo grupos 1 y 2): pasan dicts entre tasks; `_serialize` convierte
   `Decimal`/`date` a JSON-safe.
4. **`with DAG(...):`**: metadata (`dag_id`, `start_date`, `schedule`, `tags`).
5. **`PythonOperator` + `>>`**: define tasks y dependencias.

`default_args` **no** está: es opcional (retries/owner comunes). No hace falta
para corridas manuales del TP.

---

## Cómo se monta (Compose)

Ver `compose.yaml` → anclas `x-airflow-env` / `x-airflow-volumes`:

| Host | Contenedor | Para qué |
|---|---|---|
| `./apps/airflow/dags` | `/opt/airflow/dags` | Scheduler/web leen los DAGs |
| `./apps/airflow/logs` | `/opt/airflow/logs` | Logs de task |
| `./apps/pipeline` | `/opt/airflow/packages/pipeline` | Import `from pipeline...` |

Servicios típicos: `airflow-init`, `airflow-webserver`, `airflow-scheduler`.

UI local (según compose): puerto del webserver (suele ser `8080`).  
Usuario demo del init: `admin` / `admin`.

---

## Disparo rápido

```powershell
# Stack + IaC ya deben haber dejado postgres-erp (seed) y secret dw/erp
python labs/ecs/ecs.py --skip-infra --erp
```

En la UI: trigger `etl_erp_to_bronce` → al verde, trigger `etl_bronce_to_gold`.

Los comentarios al detalle de cada task/helper están **dentro de cada `.py`**.
