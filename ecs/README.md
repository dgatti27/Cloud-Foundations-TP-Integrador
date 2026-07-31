# ECS Fargate + EFS — Airflow ETL → Bronce

Lab del TP Integrador: [`lab-09b-tp.md`](./lab-09b-tp.md)

Arquitectura de referencia (fuente de verdad del to-be):

- [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md)
- [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) (§4 componentes / §5.2 Fargate+EFS)

## Qué hay acá

| Pieza | Archivo |
|---|---|
| Paso a paso | `lab-09b-tp.md` |
| IAM trust / policies | `trust_ecs.json`, `execution_policy.json`, `task_secrets_policy.json` |
| Stand-in Airflow (≈ Fargate + EFS) | `docker-compose.airflow.yaml` + `efs-standin/` |
| DAG demo → bronce | `efs-standin/dags/etl_bronce_origen_demo.py` |

## Prerrequisitos

Labs 04 (IAM), 07-v2 (VPC), 08-tp (RDS `bronce` + `dw/rds-etl`).

## Quick start (ejecución local)

```powershell
docker compose up -d
# seguir pasos IAM/EFS/ECS del lab; para correr el ETL:
docker compose -f ecs/docker-compose.airflow.yaml up -d
# UI http://localhost:8080  admin/admin → trigger etl_bronce_origen_demo
```
