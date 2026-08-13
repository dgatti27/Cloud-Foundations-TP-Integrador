# Labs del curso

Material pedagógico (guías, demos Python, stacks OpenTofu por lab).  
La infraestructura del TP se genera desde [`../infra`](../infra), no desde acá.

| Lab | Carpeta |
|-----|---------|
| 04 IAM | [`iam/`](iam/) |
| 06 S3 | [`s3/`](s3/) |
| 07 VPC | [`vpc/`](vpc/) |
| 08 RDS | [`rds/`](rds/) |
| 09b ECS / Airflow | [`ecs/`](ecs/) |
| API Lambda | [`lambda/`](lambda/) |
| 10 FinOps | [`finops/`](finops/) |

Runtime del producto:

- DAGs → [`../apps/airflow`](../apps/airflow)
- ETL → [`../apps/etl`](../apps/etl)
- API → [`../apps/api`](../apps/api)
- Seeds → [`../data/rds`](../data/rds)

Si queda un `s3/` en la **raíz** del repo, es un apply OpenTofu en curso: cuando termine, movelo a `labs/s3`.
