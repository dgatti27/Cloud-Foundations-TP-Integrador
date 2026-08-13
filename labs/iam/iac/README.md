# Lab 04 — IaC OpenTofu (IAM + buckets raw)

Declara la **infraestructura** del lab 04:

| Recurso | Lab 04 |
|---|---|
| `aws_s3_bucket` (+ seed) vía provider `minio` | Paso 2 — `*-data-raw` en MinIO |
| `aws_iam_policy` + `aws_iam_group` + attach | Paso 3 — `S3RWTP` / `S3AdminTP` |
| `aws_iam_user` + membership | Paso 4 — `usuario2-ops` / `usuario1-admin` |
| `aws_iam_role` + inline policy | Paso 6 — `app-role` / `db-role` |

Los JSON de policies/trust siguen en `iam/*.json` (misma fuente que el lab CLI).

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra (deseado)** | OpenTofu acá | Grupos, policies, users, roles, buckets raw |
| **Demo / pedagogía** | `iam/iam_demo.py --skip-infra` | Access key de larga duración (riesgo), `sts:AssumeRole`, list MinIO |
| **CLI manual** | `lab-04.md` | Aprender `iam` / `sts` paso a paso |

`iam_demo.py` **se preserva**: sigue pudiendo crear todo solo (`python iam/iam_demo.py`). Con IaC, usá `--skip-infra` para no pelear con el state.

El módulo `infra/modules/iam` es el IAM del TP completo (más roles/policies). Este stack es el **lab 04 autocontenido**.

## Prereqs

```powershell
docker compose up -d   # LocalStack + MinIO (s3-soporte)
```

## Uso

```powershell
cd iam/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Si los buckets raw ya existen:

```hcl
# terraform.tfvars
manage_minio_buckets = false
```

Luego demos:

```powershell
cd ../..
python iam/iam_demo.py --skip-infra
```

## Destroy

```powershell
tofu destroy
```

`force_destroy = true` en los buckets raw permite borrar con objetos (solo lab).

## Relación con `iam_demo.py`

| | OpenTofu | Python full |
|---|---|---|
| Idempotencia | State + plan | try/except “already exists” |
| AssumeRole / access key | No (runtime) | Sí |
| Pedagógico | Declarativo | Misma secuencia del lab |

Podés usar **uno u otro** para crear la infra; no ambos a la vez sin limpiar (duplicás o chocás con el state).
