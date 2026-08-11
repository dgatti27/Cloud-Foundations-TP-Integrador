# ECS / Airflow ETL (lab 09b)

Lab: [`lab-09b-tp.md`](./lab-09b-tp.md) — **ecosistema de cómputo** (stand-in Fargate + EFS).  
Script demo: [`ecs_demo.py`](./ecs_demo.py) — camino A (conectividad, pasos 0–4).

Origen ERP + código `extract/transform/load`: [`../etl/lab-extra-tp.md`](../etl/lab-extra-tp.md).  
En **este** lab se aplican DDL Bronce y se triggerean los DAGs → bronce/gold.

## Alcance Hobby

| Incluido | Fuera (Pro / AWS real) |
|---|---|
| IAM roles execution + task | `ecs create-cluster` / task definitions |
| `efs-standin/` ≈ EFS | `efs create-file-system` |
| Compose Airflow + DAGs grupo 1/2 | Fargate + mount NFS |
| DDL `bronce.erp_*` + carga gold | — |

## Quick start

```powershell
# Prereqs: labs 04, 07-v2, 08-tp (+ lab-extra si camino ERP)
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

python ecs/ecs_demo.py           # camino A
python ecs/ecs_demo.py --erp     # camino A + B (ERP en EFS)
# UI http://localhost:8080  admin/admin
```

API gold (siguiente): `python lambda/lambda_demo.py`

## Archivos

| Archivo | Rol |
|---|---|
| `lab-09b-tp.md` | Guía comentada (qué / por qué) |
| `ecs_demo.py` | Demo camino A |
| `docker-compose.airflow.yaml` | ≈ Fargate |
| `efs-standin/dags/` | DAGs (demo + ERP + gold) |
| `IAM-NOTES.md` / policies | Modelo IAM |
