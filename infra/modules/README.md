# Módulos OpenTofu del TP (`infra/modules/`)

Cada carpeta es un módulo reutilizable. El root `infra/main.tf` los llama con
`module "…"` y les pasa variables. Los comentarios **por sección** están
dentro de cada `main.tf`.

| Módulo | Qué modela | Runtime Hobby |
|---|---|---|
| [`vpc/`](./vpc/) | VPC Multi-AZ, subnets, IGW, NAT, SGs, VPCE S3 | LocalStack EC2/VPC |
| [`iam/`](./iam/) | Roles (app, api, ecs execution, db), grupos, users, policies | LocalStack IAM |
| [`s3/`](./s3/) | Buckets lake + versioning + SSE + bucket policies | MinIO |
| [`rds/`](./rds/) | Subnet group + instancia Postgres Multi-AZ | MiniStack → container |
| [`secrets/`](./secrets/) | `dw/rds-*`, `dw/erp`, `dw/origen-demo` | MiniStack Secrets |
| [`lambda/`](./lambda/) | Zip + función `tp-gold-api` | LocalStack Lambda |
| [`ecs/`](./ecs/) | Marcador EFS / cluster+EFS si `enable_ecs_api` | Compose Airflow (stand-in) |
| [`cloudwatch/`](./cloudwatch/) | Log groups Airflow / Lambda / ETL | LocalStack Logs |
| [`finops/`](./finops/) | Inventario JSON + Budget opcional | Solo inventario en Hobby |

## Archivos típicos por módulo

| Archivo | Rol |
|---|---|
| `main.tf` | Variables + recursos (documentado por pasos/secciones) |
| `outputs.tf` | Valores que el root reexpone (`tofu output`) |
| `versions.tf` | Constraints de providers del módulo |
| `policies/*.json` | (iam, s3) JSON de policies versionados |

## Orden lógico en el apply

```text
vpc → iam → s3
       ↓
      rds → secrets → post_rds (root null_resource)
       ↓
    lambda · ecs · cloudwatch · finops
```

Detalle de decisiones de diseño: [`docs/decisions.md`](../../docs/decisions.md).
