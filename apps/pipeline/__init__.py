"""Paquete `pipeline` — lógica de negocio del ETL (sin Airflow).

Rol en el TP
------------
Este directorio es el código que *hace* el trabajo de datos.
Los DAGs en `apps/airflow/dags/` solo orquestan (llaman funciones de acá).

Por qué está separado de Airflow
---------------------------------
- Se puede importar y testear sin levantar el scheduler.
- En AWS real, el mismo paquete iría en la imagen del worker / layer.
- En Hobby (Compose) se monta en `/opt/airflow/packages/pipeline`.

Mapa de carpetas
--------------
  extract/     Lee orígenes → filas en memoria (dicts).
  transform/   Limpia (grupo 1) o modela dims/facts (grupo 2).
  load/        Escribe en RDS: schema bronce, luego schema gold.
  erp/         Seed SQL del Postgres origen (`postgres-erp`; Compose initdb).
  sql/         DDL de tablas landing `bronce.erp_*`.
  config.py    Cómo obtener credenciales (env / Secrets Manager).
  db.py        Helpers psycopg2 compartidos.

Preparación (sin script demo): Compose levanta ERP+seed; `tofu apply` crea `dw/erp`.

Flujo camino B (ERP)
-------------------
  postgres-erp  --DAG grupo 1→  bronce.erp_*  --DAG grupo 2→  gold.*
"""
