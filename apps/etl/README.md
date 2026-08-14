# Paquete ETL

Lógica de negocio del DW, **separada de la orquestación** (DAGs en `apps/airflow/dags/`).

Esquemas y flujo: [README raíz — Datos](../../README.md#datos-esquemas-y-procesamiento).

| Pieza | Rol |
|---|---|
| [`etl_demo.py`](./etl_demo.py) | Levanta `postgres-erp` + secret `dw/erp` |
| [`erp/seed_erp.sql`](./erp/seed_erp.sql) | Semilla origen |
| [`extract/erp_foxpro.py`](./extract/erp_foxpro.py) | Lee ERP → memoria |
| [`extract/from_bronce.py`](./extract/from_bronce.py) | Lee `bronce.erp_*` |
| [`transform/`](./transform/) | normalize + `to_gold` (6 dims + `fact_venta_linea`) |
| [`load/`](./load/) | UPSERT bronce / gold |
| [`sql/bronce_erp_ddl.sql`](./sql/bronce_erp_ddl.sql) | DDL landing ERP (lo aplica el DAG) |

```powershell
python apps/etl/etl_demo.py
python labs/ecs/ecs.py --skip-infra --erp
```
