# `s3/` — Lab 06: data lake en MinIO (API S3)

Object storage del TP: **MinIO** (`s3-soporte`, `:9000`). LocalStack S3 queda comentado en compose y labs (decisión 002).

## Archivos

| Archivo | Rol |
|---|---|
| [`lab-06.md`](./lab-06.md) | Guía paso a paso (MinIO + `s3api`) |
| [`s3_demo.py`](./s3_demo.py) | Orquestación end-to-end |
| `bucket_policy_*-data-lake.json` | Resource policies por bucket |
| `bucket_policy.json` | Molde genérico (referencia) |

## Endpoints

| Qué | Dónde |
|---|---|
| Buckets lake / raw | MinIO `:9000` (`minioadmin`) |
| IAM / STS (`app-role`) | LocalStack `:4566` |
| LocalStack S3 | Comentado — no usar |

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
python s3/s3_demo.py
```

## Identity vs resource policy

| Capa | Dónde | En el TP |
|---|---|---|
| Identity (lab 04) | LocalStack IAM | Policies `S3RWTP` / `S3AdminTP` |
| Resource (lab 06) | MinIO `put-bucket-policy` | JSON por bucket |

En AWS real ambas se evalúan juntas. Acá IAM no enforcea MinIO: el lab enseña el modelo y persiste el lake en volume Docker.
