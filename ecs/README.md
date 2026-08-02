# ECS / Airflow ETL → Bronce (lab 09b)

Lab: [`lab-09b-tp.md`](./lab-09b-tp.md) — **solo lo ejecutable en LocalStack Hobby**.  
Script: [`ecs_demo.py`](./ecs_demo.py) — automatiza pasos 0–4 (recomendado).

Arquitectura to-be: [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md), [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md).

## Alcance Hobby

| Incluido | Fuera (Pro / AWS real) |
|---|---|
| IAM roles execution + task | `ecs create-cluster` / task definitions |
| `efs-standin/` ≈ EFS | `efs create-file-system` |
| Compose Airflow → `bronce` | Fargate + mount NFS |

## Quick start

```powershell
# Prereqs labs 04, 07-v2, 08-tp + compose base up
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

python ecs/ecs_demo.py
# UI http://localhost:8080  admin/admin
```

ETL ERP → Bronce → Gold (lab extra): ver [`../etl/lab-extra-tp.md`](../etl/lab-extra-tp.md).
DAGs: `etl_erp_to_bronce`, `etl_bronce_to_gold`.

## Archivos

| Archivo | Rol |
|---|---|
| `lab-09b-tp.md` | Paso a paso comentado (qué / por qué) |
| `ecs_demo.py` | Demo Python (IAM → secret → Compose → DAG → bronce) |
| `IAM-NOTES.md` | Roles 1.1 / 1.2 |
| `docker-compose.airflow.yaml` | Stand-in Fargate |
| `efs-standin/` | Stand-in EFS |
| `*_policy.json` / `trust_ecs.json` | IAM |
