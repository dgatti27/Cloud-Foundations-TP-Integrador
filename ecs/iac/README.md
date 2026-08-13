# Lab 09b-TP — IaC OpenTofu (cómputo ETL: IAM + stand-in EFS)

Declara la **infraestructura / modelo** del lab 09b-TP:

| Recurso | Lab 09b |
|---|---|
| `aws_iam_role` `ecsTaskExecutionRole` + inline | Paso 1.1 — agente boot (ECR/awslogs) |
| `aws_iam_role_policy` `InlineEtlSecrets` en `app-role` | Paso 1.2 — task role (Secrets ETL/orígenes) |
| `local_file` `.iac-managed` + `efs_inventory.json` | Paso 2 — stand-in ≈ EFS (Hobby) |
| `aws_secretsmanager_secret` `dw/origen-demo` | Paso 3.1 — origen camino A (opcional) |
| `aws_ecs_cluster` / `aws_efs_*` | Solo si `enable_ecs_api=true` (Pro / AWS) |

Los JSON de policies/trust siguen en `ecs/*.json` (misma fuente que el lab CLI).

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra / modelo** | OpenTofu acá | IAM Fargate, marcadores stand-in, secret origen, API opcional |
| **Runtime / demos** | `ecs/ecs_demo.py --skip-infra` | Compose Airflow, trigger DAG, verify bronce, `--erp`, cleanup |
| **CLI manual** | `lab-09b-tp.md` | Entender cada paso |
| **Full sin tofu** | `python ecs/ecs_demo.py` | **Se preserva** — IAM + stand-in + Compose + DAG |

> LocalStack Hobby **no** tiene APIs `ecs`/`efs`. El default (`enable_ecs_api=false`) es el camino correcto del curso.

El módulo `iac/tp/modules/ecs` es la misma idea a escala TP (lab 09).  
Este stack es **autocontenido para lab-09b**.

## Prereqs

```powershell
docker compose up -d localstack-integrador ministack-integrador s3-soporte redis postgres-bronce postgres-dw

# Lab 04 — app-role (obligatorio)
cd iam/iac; tofu apply; cd ../..

# Lab 07-v2 — VPC + sg-efs + subnets Role=ecs-lambda-efs
cd vpc/iac; tofu apply; cd ../..

# Lab 08-tp — dw/rds-etl + tp-dw-db
cd rds/iac; tofu apply; cd ../..
```

## Uso

```powershell
cd ecs/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Runtime:

```powershell
cd ../..
python ecs/ecs_demo.py --skip-infra
python ecs/ecs_demo.py --skip-infra --erp   # camino B (lab-extra primero)
```

Si `dw/origen-demo` ya existe:

```hcl
# terraform.tfvars
manage_origen_secret = false
```

## Destroy

```powershell
tofu destroy
```

No baja Compose Airflow (eso es `--cleanup` en el demo Python).

## Relación con `ecs_demo.py`

| | OpenTofu | Python full |
|---|---|---|
| IAM execution + InlineEtlSecrets | Sí | `step_iam()` |
| efs-standin dirs / marker | Sí | `step_efs_standin()` |
| Secret origen | Opcional | `step_origen_secret()` |
| Compose / DAG / verify / ERP | No | Sí |

No mezcles IAM Python y OpenTofu sobre los mismos roles sin limpiar.
