# IAM ECS / Airflow — notas (JSON no admite //)

## execution_policy.json

Usado por `ecsTaskExecutionRole` (mismo patrón que el agente ECS en to-be).

Permisos típicos: pull ECR, escribir logs a CloudWatch.

En Hobby: el rol se crea como **modelo** en LocalStack; Compose no asume el role
(inyecta `AWS_ACCESS_KEY_ID=test`).

## task_secrets_policy.json

Adjunta a `app-role` (task role): `GetSecretValue` / `DescribeSecret` sobre
`dw/rds-etl*`, `dw/origen*`, `dw/erp*`, etc.

Complementa lectura S3 de staging (MinIO/S3).

En Hobby: modela privilegios; el DAG usa credenciales dummy contra MiniStack.

Detalle IaC: `infra/modules/iam` + `infra/modules/ecs`.
