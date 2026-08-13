# Paquete ETL

Lógica de negocio del Datawarehouse, **separada de la orquestación**.

| Dónde | Qué |
|---|---|
| [`lab-extra-tp.md`](./lab-extra-tp.md) | Guía origen ERP + módulos |
| [`etl_demo.py`](./etl_demo.py) | Script de ejecución |
| [`../airflow/dags/`](../airflow/dags/) | DAGs Airflow (orquestación) |

```powershell
python apps/etl/etl_demo.py
python labs/ecs/ecs_demo.py --erp
```

```text
etl:       postgres-erp + paquete extract/transform/load
airflow:   orquesta → bronce.erp_* → gold.*
api:       Lambda GET gold (ALB stand-in :8088 vía compose)
```
