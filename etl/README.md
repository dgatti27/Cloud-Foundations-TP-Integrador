# Paquete ETL

Lógica de los ETL del Datawarehouse, **separada de la orquestación**.
Los DAGs de Airflow viven en `../ecs/efs-standin/dags/` e importan este paquete
(`PYTHONPATH=/opt/airflow/packages` en el compose de Airflow).

## Lab extra (recomendado)

Guía completa: [`lab-extra-tp.md`](./lab-extra-tp.md)

```text
ERP (postgres-erp) → bronce.erp_* → gold.dim_* / fact_venta_linea
     DAG etl_erp_to_bronce              DAG etl_bronce_to_gold
```

## Estructura

```
etl/
├── lab-extra-tp.md      # Paso a paso ERP → Bronce → Gold
├── config.py            # Secrets MiniStack / env
├── db.py                # psycopg2 helpers
├── pipelines.py         # run_erp_to_bronce / run_bronce_to_gold
├── erp/seed_erp.sql     # Seed origen ERP
├── sql/bronce_erp_ddl.sql
├── extract/
│   ├── erp_foxpro.py        # Grupo 1: lee Postgres ERP
│   ├── from_bronce.py       # Grupo 2: lee bronce.erp_*
│   ├── ecommerce_mongo.py   # (stub otros orígenes)
│   ├── eventos_mongo.py
│   └── scraping.py
├── transform/
│   ├── normalize.py         # Grupo 1
│   └── to_gold.py           # Grupo 2 → modelo dimensional
└── load/
    ├── to_cruda.py          # → schema bronce
    └── to_dw.py             # → schema gold
```

## Flujo (2 etapas)

```
extract.erp_*() → transform.normalize_erp_*() → load.load_erp_to_bronce()   [grupo 1]
extract.from_bronce() → transform.to_gold() → load.load_gold_bundle()       [grupo 2]
```

## Test rápido (sin Airflow)

```powershell
$env:SECRETS_ENDPOINT = "http://localhost:4567"
$env:RDS_HOST_OVERRIDE = "localhost"
$env:RDS_PORT_OVERRIDE = "15432"
$env:ERP_SECRET = "dw/erp"
python -c "from etl.pipelines import run_erp_to_bronce; print(run_erp_to_bronce())"
```
