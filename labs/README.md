# Labs del curso

Guías y demos Python. **La infraestructura se genera solo desde [`../infra`](../infra)** (`tofu apply`).

| Lab | Carpeta | IaC vigente |
|-----|---------|-------------|
| 04 IAM | [`iam/`](iam/) | `infra/modules/iam` |
| 06 S3 | [`s3/`](s3/) | `infra/modules/s3` |
| 07 VPC | [`vpc/`](vpc/) | `infra/modules/vpc` |
| 08 RDS | [`rds/`](rds/) | `infra/modules/rds` + `secrets` |
| 09b ECS | [`ecs/`](ecs/) | `infra/modules/ecs` |
| API Lambda | [`lambda/`](lambda/) | `infra/modules/lambda` |
| 10 FinOps | [`finops/`](finops/) | `infra/modules/finops` |

Runtime: [`../apps`](../apps) · seeds: [`../data/rds`](../data/rds)
