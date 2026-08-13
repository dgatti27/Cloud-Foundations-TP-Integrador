# Lab 08-TP — IaC OpenTofu (RDS + secrets en MiniStack)

Declara la **infraestructura** del lab 08-TP:

| Recurso | Lab 08-TP |
|---|---|
| `data` VPC / subnets `Role=rds` / `sg-rds` | Paso 2 — lookup lab 07-v2 (LocalStack) |
| `aws_db_subnet_group` | Paso 3 — `tp-rds-subnets` |
| `aws_db_instance` | Paso 4–5 — `tp-dw-db` Multi-AZ (MiniStack) |
| `aws_secretsmanager_secret*` | Pasos 1 + 7 — `dw/rds-master`, `dw/rds-etl`, `dw/rds-api` |
| `null_resource` + `scripts/post_rds.py` | Pasos 6–7 — `seed_tp.sql` + ALTER ROLE (opcional) |
| `aws_s3_bucket` (MinIO) | Paso 9 — asegura `snapshot-data-lake` (opcional) |

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra (deseado)** | OpenTofu acá | Subnet group, instancia, secrets, seed, bucket snapshot |
| **Demo / pedagogía** | `rds/rds_tp_demo.py --skip-infra` | Verify privilegios + snapshot API + `pg_dump`→MinIO |
| **CLI manual** | `lab-08-tp.md` | Explorar MiniStack / `psql` / MinIO |
| **Full sin tofu** | `python rds/rds_tp_demo.py` | **Se preserva** — orquesta 1–9 solo |

El módulo `infra/modules/rds` (+ secrets) es la misma idea a escala TP (lab 09).  
Este stack es **autocontenido para lab-08-tp**.

## Prereqs

```powershell
docker compose up -d localstack-integrador ministack-integrador s3-soporte

# Lab 07-v2 (VPC + sg-rds + subnets Role=rds) — obligatorio
cd vpc/iac; tofu apply; cd ../..

# Lab 04 (app-role) recomendado; no bloquea el apply RDS
```

## Uso

```powershell
cd rds/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Si preferís seed solo con Python:

```hcl
# terraform.tfvars
apply_rds_seed = false
```

Luego demos:

```powershell
cd ../..
python rds/rds_tp_demo.py --skip-infra
```

## Destroy

```powershell
tofu destroy
```

`skip_final_snapshot = true` y `force_destroy` en el bucket (solo lab).

## Relación con `rds_tp_demo.py`

| | OpenTofu | Python full |
|---|---|---|
| Idempotencia | State + plan | try/except “already exists” |
| Passwords | `random_password` → state + Secrets | generadas en proceso |
| Seed | `null_resource` (default on) | `apply_seed` + `configure_app_roles` |
| Snapshot/dump | No | Sí (paso 9) |

No mezcles infra Python y OpenTofu sobre la misma `tp-dw-db` sin limpiar.
