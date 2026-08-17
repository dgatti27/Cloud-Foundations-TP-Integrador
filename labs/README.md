# Labs (guías y demos)

JSONs de apoyo de la infraestructura del TP. **La infraestructura del TP se genera solo desde [`../infra`](../infra)** (`tofu apply`).

| Tema | Carpeta | IaC en el TP |
|------|---------|--------------|
| IAM | [`iam/`](iam/) | `infra/modules/iam` |
| S3 / lake | [`s3/`](s3/) | `infra/modules/s3` |
| VPC | [`vpc/`](vpc/) | `infra/modules/vpc` |
| RDS | [`rds/`](rds/) | `infra/modules/rds` + `secrets` |
| ECS / Airflow | [`ecs/`](ecs/) → [`ecs.py`](ecs/ecs.py) | `infra/modules/ecs` |
| Lambda API | [`lambda/`](lambda/) | `infra/modules/lambda` |
| FinOps | [`finops/`](finops/) → [`pricing.py`](finops/pricing.py) | `infra/modules/finops` |

Runtime de producto: [`../apps`](../apps) · seed RDS: [`../data/rds/seed_tp.sql`](../data/rds/seed_tp.sql) · bring-up: [`../README.md`](../README.md).
