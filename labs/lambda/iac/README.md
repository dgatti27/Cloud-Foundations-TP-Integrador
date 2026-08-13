# Lab API-TP — IaC OpenTofu (Lambda gold + IAM)

Declara la **infraestructura** del lab-api-tp:

| Recurso | Lab API |
|---|---|
| `aws_iam_role` `api-role` + inline policies | Paso 1 — trust Lambda + logs/ENI + `dw/rds-api*` |
| `aws_iam_group` `bi-api` + invoke (+ `bi-ops`) | Paso 1 — quién puede Invoke |
| `aws_cloudwatch_log_group` | Observabilidad CW |
| zip + `aws_lambda_function` `tp-gold-api` | Paso 2 — deploy (pg8000 opcional) |
| `local_file` `lambda_inventory.json` | Inventario |

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra** | OpenTofu acá | IAM, log group, empaquetado, función Lambda |
| **Runtime / demos** | `lambda/lambda_demo.py --skip-infra` | ALB stand-in `:8088`, invoke, export logs→MinIO |
| **Full sin tofu** | `python lambda/lambda_demo.py` | **Se preserva** — todo el lab |

> Hobby no tiene ELBv2 → el ALB queda en Compose (Python), no en OpenTofu.

El módulo `infra/modules/lambda` es la misma idea a escala TP (lab 09).

## Prereqs

```powershell
# Labs 04 (bi-ops), 07-v2 (VPC/sg-api), 08-tp (dw/rds-api)
# Datos en gold (ecs --erp / etl) para que el invoke tenga filas
docker compose up -d localstack-integrador ministack-integrador s3-soporte
```

## Uso

```powershell
cd lambda/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Demos:

```powershell
cd ../..
python lambda/lambda_demo.py --skip-infra
```

Si LocalStack soporta ENI y querés VpcConfig:

```hcl
# terraform.tfvars
attach_vpc = true
```

## Destroy

```powershell
tofu destroy
```

No baja el ALB stand-in (`--cleanup` en el demo Python).
