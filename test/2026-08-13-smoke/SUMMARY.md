# Smoke + IaC — 13 ago 2026

**Host:** SFNOT96 · Windows 10.0.26200 · **ETL:** no ejecutado.

## IaC (OpenTofu `infra/`)

| Check | Resultado | Log |
|-------|-----------|-----|
| `tofu apply` | **67 added, 5 changed, 2 destroyed** | [`12-tofu-apply-complete.txt`](./12-tofu-apply-complete.txt) |
| `tofu output` | VPC, IAM roles, lake, Lambda `tp-gold-api`, secrets names, `ecs_mode=hobby-standin` | [`02-tofu-output.txt`](./02-tofu-output.txt) |
| `tofu state list` | **96** resources | [`13-tofu-state-summary.txt`](./13-tofu-state-summary.txt) |
| `tofu plan` | exit **2** — 1 add / 1 destroy (`finops_inventory` local_file tras docs) | [`10-tofu-plan.txt`](./10-tofu-plan.txt) |

## Compose / runtime Hobby

| Servicio | Estado | Log |
|----------|--------|-----|
| LocalStack `:4566` | healthy | [`01-compose-ps.txt`](./01-compose-ps.txt) |
| MiniStack `:4567` + RDS host **:15434** | healthy / Up 10 days | idem |
| MinIO `:9000` | buckets `*-data-lake` | [`04-minio-s3.txt`](./04-minio-s3.txt) |
| Airflow `:8080` | Up, login 200, health 200 | [`08-http-health.txt`](./08-http-health.txt) |
| ALB stand-in `:8088` | `{"ok":true,"target":"tp-gold-api"}` | idem |
| pgAdmin `:5050` | `PING` 200 | idem |

## AWS APIs emuladas

| API | OK | Log |
|-----|----|-----|
| IAM roles `app-role` `api-role` `ecsTaskExecutionRole` `db-role` + grupos + users | sí | [`03-iam.txt`](./03-iam.txt) |
| RDS `tp-dw-db` available | sí | [`05-rds.txt`](./05-rds.txt) |
| Secrets names `dw/rds-*` `dw/erp` `dw/origen-demo` | sí (sin valores) | [`06-secrets-names.txt`](./06-secrets-names.txt) |
| Lambda `tp-gold-api` Active python3.12 | sí | [`07-lambda.txt`](./07-lambda.txt) |

## API gold (sin ETL)

| Request | Resultado | Log |
|---------|-----------|-----|
| `?table=hecho_ventas` | 400 allowlist | [`09-gold-query.txt`](./09-gold-query.txt) |
| `?table=dim_cliente` | 500 `No module named 'pg8000'` | idem |

Esperado: Lambda en línea; zip Hobby lite (decisión 006).

## FinOps

[`11-finops-pricing.txt`](./11-finops-pricing.txt) — OD **275,78** / SP **262,26** vs budget 300.

## Versiones

[`00-versions.txt`](./00-versions.txt) · meta [`00-meta.txt`](./00-meta.txt)
