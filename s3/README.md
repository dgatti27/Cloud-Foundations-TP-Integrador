# `s3/` — Lab 06: data lake en MinIO (API S3)

Object storage del TP: **MinIO** (`s3-soporte`, `:9000`). LocalStack S3 queda comentado en compose y labs (decisión 002).

## Archivos

| Archivo | Rol |
|---|---|
| [`lab-06.md`](./lab-06.md) | Guía paso a paso (MinIO + `s3api`) |
| [`iac/`](./iac/) | **OpenTofu** — buckets, versioning, SSE, policies, seed |
| [`s3_demo.py`](./s3_demo.py) | Orquestación / demos (STS, versioning, presign) |
| `bucket_policy_*-data-lake.json` | Resource policies por bucket |
| `bucket_policy.json` | Molde genérico (referencia) |

## IaC vs Python (qué usar)

| Enfoque | Cuándo |
|---|---|
| `s3/iac` (`tofu apply`) | Infra **declarativa** del lake (lab 06 pasos 1–3, 5) |
| `python s3/s3_demo.py --skip-infra` | Demos **después** del apply (versioning mutate, AssumeRole, presign) |
| `python s3/s3_demo.py` | Todo en un comando (sin OpenTofu) — sigue válido |
| `lab-06.md` CLI | Aprendizaje manual `s3` / `s3api` |

```powershell
# A) Camino IaC + demos
cd s3/iac
Copy-Item terraform.tfvars.example terraform.tfvars
tofu init; tofu apply
cd ../..
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
python s3/s3_demo.py --skip-infra

# B) Solo Python (como antes)
python s3/s3_demo.py
```

## Endpoints

| Qué | Dónde |
|---|---|
| Buckets lake / raw | MinIO `:9000` (`minioadmin`) |
| IAM / STS (`app-role`) | LocalStack `:4566` |
| LocalStack S3 | Comentado — no usar |

## Identity vs resource policy

| Capa | Dónde | En el TP |
|---|---|---|
| Identity (lab 04) | LocalStack IAM | Policies `S3RWTP` / `S3AdminTP` |
| Resource (lab 06) | MinIO `put-bucket-policy` / OpenTofu | JSON por bucket |

En AWS real ambas se evalúan juntas. Acá IAM no enforcea MinIO: el lab enseña el modelo y persiste el lake en volume Docker.
