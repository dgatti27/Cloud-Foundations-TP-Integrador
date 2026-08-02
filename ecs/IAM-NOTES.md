# IAM del lab 09b — comentarios (JSON no admite //)

Los archivos `trust_ecs.json`, `execution_policy.json` y `task_secrets_policy.json`
son documentos IAM válidos (sin comentarios). Este archivo documenta **qué hace cada uno**.

## `trust_ecs.json` (trust policy)

Usado por `ecsTaskExecutionRole` (y el mismo patrón que `app-role` en lab 04).

- **Principal:** `ecs-tasks.amazonaws.com` — solo el servicio ECS puede asumir el rol.
- **Action:** `sts:AssumeRole`.
- **Efecto:** ni un usuario IAM humano ni Lambda asumen este rol “de casualidad”;
  hace falta que una task/service ECS lo pida.

## `execution_policy.json` → rol `ecsTaskExecutionRole` (paso 1.1)

Permisos del **agente ECS** al **arrancar** la task Fargate:

| Sid | Acciones | Para qué |
|---|---|---|
| `Logs` | `logs:CreateLogGroup`, `CreateLogStream`, `PutLogEvents` | Driver `awslogs` de la task definition |
| `ECRPull` | `ecr:GetAuthorizationToken` + Batch/Get image | Descargar la imagen del registry |

**No incluye** Secrets de negocio ni S3 del ETL: eso es del task role.

En AWS real: campo `executionRoleArn` de la task definition.  
En este lab Hobby: el rol se crea como modelo; el compose no lo asume.

## `task_secrets_policy.json` → rol `app-role` (paso 1.2)

Permisos del **código dentro del contenedor** (Airflow / DAG):

| Sid | Acciones | Recursos |
|---|---|---|
| `ReadEtlSecrets` | `GetSecretValue`, `DescribeSecret` | Solo `dw/rds-etl*`, `dw/origen*`, `dw/erp*`, `dw/ecommerce*`, `dw/eventos*`, `dw/scraping*` |
| `CloudWatchMetrics` | `PutMetricData` | `*` (métricas custom del job) |

**No incluye** `dw/rds-master` ni `dw/rds-api` (privilegio mínimo).

Complementa `InlineS3Read` del lab 04 (staging MinIO/S3).

En AWS real: campo `taskRoleArn`.  
En este lab Hobby: el rol modela privilegios; el DAG usa `AWS_ACCESS_KEY_ID=test` contra MiniStack.

## Por qué dos roles

1. **1.1 Execution** = plataforma (imagen + logs de arranque).
2. **1.2 Task** = aplicación (secrets ETL → connect a orígenes y a `bronce`).

Si el DAG se filtra, el atacante no obtiene automáticamente pull a ECR (y el agente no necesita la password de RDS).
