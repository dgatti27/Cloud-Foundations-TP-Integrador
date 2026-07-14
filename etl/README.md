# Paquete ETL

Lógica de los ETL del Datawarehouse, **separada de la orquestación** (los DAGs
de Airflow viven en `../iac/local-docker/airflow/dags/`). Los DAGs importan
desde este paquete; así el código es testeable sin levantar Airflow.

## Estructura

```
etl/
├── config.py            # de dónde salen las conexiones (Secrets Manager en AWS,
│                        # variables de entorno en local)
├── extract/             # un módulo por origen (conexión por host, no por API)
│   ├── erp_foxpro.py        # ERP (tablas FoxPro)
│   ├── ecommerce_mongo.py   # Ecommerce (MongoDB)
│   ├── eventos_mongo.py     # Eventos (MongoDB)
│   └── scraping.py          # repositorio de scraping
├── transform/           # limpieza y normalización a esquema uniforme
│   └── normalize.py
└── load/                # carga por etapas
    ├── to_cruda.py          # ETL grupo 1 -> base CRUDA
    └── to_dw.py             # ETL grupo 2 -> Datawarehouse
```

## Flujo (2 etapas)

```
extract.<origen>()  ->  transform.normalize_records()  ->  load.load_to_cruda()   [grupo 1]
                                                             load.load_to_dw()      [grupo 2]
```

## Cómo completarlo

1. En cada `extract/*.py`, implementá la conexión real por host al origen
   (FoxPro/DBF, `pymongo` para Mongo, HTTP/archivos para scraping).
2. En `load/to_cruda.py` y `load/to_dw.py`, implementá los `INSERT`/`UPSERT`
   con `psycopg2` (ver `requirements.txt`).
3. Las credenciales: en AWS salen de Secrets Manager (`USE_SECRETS_MANAGER=1`);
   en local, de variables de entorno (`ORIGEN_*_CONN`, `DW_CRUDA_CONN`, `DW_DW_CONN`).

## Test rápido (sin Airflow)

```bash
python -c "from etl.extract import EXTRACTORS; print(list(EXTRACTORS))"
```
