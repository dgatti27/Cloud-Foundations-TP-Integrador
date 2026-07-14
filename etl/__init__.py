"""Paquete ETL del Datawarehouse.

Separa la LOGICA de los ETL (extraer/transformar/cargar) de la ORQUESTACION
(los DAGs de Airflow en iac/local-docker/airflow/dags). Los DAGs importan desde
aca; asi el codigo es testeable sin levantar Airflow.

Etapas:
  - extract/  : un modulo por origen (conexion por host, no por API).
  - transform/: limpieza y normalizacion.
  - load/     : grupo 1 -> base CRUDA ; grupo 2 -> Datawarehouse.
"""
