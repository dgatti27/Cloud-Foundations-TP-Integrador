# Lab 06 — IaC OpenTofu (data lake MinIO)

Declara la **infraestructura** del lab 06 contra MinIO (`:9000`):

| Recurso | Lab 06 |
|---|---|
| `aws_s3_bucket` | Paso 1 — buckets `*-data-lake` |
| `aws_s3_bucket_versioning` | Paso 2 |
| `aws_s3_bucket_server_side_encryption_configuration` | Paso 1 (SSE-S3) |
| `aws_s3_bucket_policy` | Paso 5 — JSON en `s3/bucket_policy_*.json` |
| `aws_s3_object` (opcional) | Paso 3 — `raw/README.md` |

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra (deseado)** | OpenTofu acá | Buckets, versioning, encryption, policies, seed |
| **Demo / pedagogía** | `s3/s3_demo.py --skip-infra` | Mutar objeto (versioning), AssumeRole STS (LocalStack), list/get MinIO, presign |
| **CLI manual** | `lab-06.md` | Aprender `s3` / `s3api` paso a paso |

`s3_demo.py` **se preserva**: sigue pudiendo crear todo solo (`python s3/s3_demo.py`). Con IaC, usá `--skip-infra` para no pelear con el state.

El módulo `iac/tp/modules/s3` es el mismo patrón a escala TP (sin policies por archivo); este stack es el **lab 06 autocontenido**.

## Prereqs

```powershell
docker compose up -d s3-soporte
# MinIO con KMS si querés encryption (compose MINIO_KMS_SECRET_KEY)
```

## Uso

```powershell
cd s3/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Si encryption falla en MinIO (sin KMS):

```hcl
# terraform.tfvars
enable_encryption = false
```

Luego demos:

```powershell
cd ../..
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
python s3/s3_demo.py --skip-infra
```

## Destroy

```powershell
tofu destroy
```

`force_destroy = true` en los buckets permite borrar con objetos (solo lab).
