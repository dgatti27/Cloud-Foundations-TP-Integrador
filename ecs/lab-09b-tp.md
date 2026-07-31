# Lab 09b TP — ECS Fargate + EFS: Airflow ETL → Bronce (RDS)

Implementa en el lab la capa de **cómputo** del to-be documentado en:

| Documento | Qué fija para este lab |
|---|---|
| [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md) | 3 capas VPC; app privada = **ECS Fargate (Airflow scheduler/webserver/worker) + EFS**; datos = RDS Multi-AZ |
| [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §4–5 | Flujo ETL grupo 1 → **Bronce**; Fargate vs EC2/MWAA; EFS para DAGs/logs; NAT solo hacia orígenes; Secrets + IAM |

Cierra el arco operativo: **IAM (04) → VPC (07-v2) → RDS (08-tp) → cómputo ETL (hoy)** — fase **F3/F5** del plan en Solution Architecture.

### Mapeo docs → lab (nombres)

| To-be (`docs/`) | En el TP local (labs 07–08) |
|---|---|
| Base **Bronce** + **DW** en una RDS Multi-AZ | Misma instancia `tp-dw-db`, schemas **`bronce`** + **`gold`** |
| Airflow dockerizado → ECS Fargate + EFS | Task defs / service (API) + compose stand-in |
| Conexión a orígenes **por host** (no API) | Secrets `dw/origen-*` + egress NAT (`RT_COMPUTE`) |
| Staging S3 | MinIO `staging-data-lake` (decisión 002) |
| Credencial ETL | Secret MiniStack `dw/rds-etl` → user `etl_writer` |

```text
Orígenes (ERP FoxPro / Ecommerce Mongo / Eventos Mongo / scraping)
        │  conexión directa por host (docs §4.2)
        │  egress vía NAT Gateway — lab 07-v2 (RT_COMPUTE)
        ▼
┌─ Subred privada APP (docs: sin EC2) ─────────────────────────────┐
│  ECS Fargate: Airflow scheduler + webserver + worker             │
│  SG: sg-ecs-etl                                                  │
│       ├── NFS :2049 ──► EFS (sg-efs)  DAGs + logs compartidos    │
│       └── :5432 ─────► RDS (sg-rds)  schema bronce / etl_writer  │
└──────────────────────────────────────────────────────────────────┘
        ▲
        │ Task role = app-role (trust ecs-tasks.amazonaws.com)
        │ Secrets Manager: dw/rds-etl + dw/<origen>
```

> **LocalStack Community vs ejecución real**  
> LocalStack (`:4566`) modela IAM + VPC/SG y, si habilitás los servicios, la **API** de ECS/EFS.  
> **No** corre Fargate real ni monta NFS (limitación alineada a Solution Architecture: orquestación real en AWS).  
> Para **ejecutar** el ETL hoy: stand-in Docker (Airflow + volumen = EFS) → MiniStack RDS (`:4567`).  
> En AWS / Learner Lab: mismo diseño de `docs/`, Fargate + EFS mount targets reales.

---

## Por qué este lab (trazabilidad a `docs/`)

| Pieza to-be | Fuente en docs | Qué armamos hoy |
|---|---|---|
| Airflow en ECS Fargate (sin EC2) | Infra §to-be; Solution §5.2 | Cluster + task definitions + service + compose |
| EFS solo DAGs/logs (no el DW) | Solution §5.2, costos EFS 10 GB | FS + mount targets / volumen `efs-standin` |
| ETL grupo 1 → Bronce | Infra flujo; Solution §4.2 | DAG → `bronce.ingest_batch` / `raw_record` |
| NAT solo hacia orígenes | Solution §5.4 | Reuso `tp-nat-etl` + `RT_COMPUTE` (07-v2) |
| IAM mínimo + Secrets | Infra transversal; Solution §4.1 | Extiende `app-role` + `ecsTaskExecutionRole` |
| RDS :5432 solo desde capa app | Solution §4.2 | Ya cableado: `sg-ecs-etl` → `sg-rds` |

---

## Prerequisitos

```powershell
# Emuladores
docker compose up -d localstack-integrador ministack-integrador s3-soporte redis

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

# Lab 04 — app-role con trust ECS
awslocal iam get-role --role-name app-role --query "Role.Arn"

# Lab 07-v2 — VPC + SGs (entrecomillar filtros en PowerShell)
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc" --query "Vpcs[0].VpcId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-ecs-etl" --query "SecurityGroups[0].GroupId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" --query "SecurityGroups[0].GroupId" --output text
awslocal ec2 describe-subnets --filters "Name=tag:Role,Values=ecs-lambda-efs" --query "Subnets[].{Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone}" --output table

# Lab 08-tp — RDS + secret ETL
curl.exe -s http://localhost:4567/_ministack/health
aws --endpoint-url http://localhost:4567 secretsmanager get-secret-value --secret-id dw/rds-etl --query "Name" --output text
```

Variables de sesión (rellenar con los IDs de tu entorno):

```powershell
$VPC_ID   = (awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc" --query "Vpcs[0].VpcId" --output text).Trim()
$SG_ECS   = (awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-ecs-etl" --query "SecurityGroups[0].GroupId" --output text).Trim()
$SG_EFS   = (awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" --query "SecurityGroups[0].GroupId" --output text).Trim()
$SUBNETS  = awslocal ec2 describe-subnets --filters "Name=tag:Role,Values=ecs-lambda-efs" --query "Subnets[].SubnetId" --output text
$SUB_A, $SUB_B = ($SUBNETS -split "\s+")[0], ($SUBNETS -split "\s+")[1]
$APP_ROLE = (awslocal iam get-role --role-name app-role --query "Role.Arn" --output text).Trim()

Write-Host "VPC=$VPC_ID"
Write-Host "SG_ECS=$SG_ECS  SG_EFS=$SG_EFS"
Write-Host "SUB_A=$SUB_A  SUB_B=$SUB_B"
Write-Host "APP_ROLE=$APP_ROLE"
```

---

## Mapa de endpoints (no mezclar)

| Servicio | URL | Uso en este lab |
|---|---|---|
| LocalStack | `http://localhost:4566` | IAM, EC2/VPC, (API) ECS/EFS/Logs |
| MiniStack | `http://localhost:4567` | Secrets `dw/rds-etl`, endpoint lógico RDS |
| MinIO | `http://localhost:9000` | Staging opcional (`staging-data-lake`) |
| Postgres origen (compose) | `localhost:5432` (`postgres-bronce`) | **Source** de demo (simula ERP/origen) |
| RDS TP (MiniStack container) | puerto host `15432` o IP docker | Destino **bronce** |

---

## Paso 1 — Ampliar IAM para la task de Airflow/ETL

El lab 04 ya dejó `app-role` con **trust** `ecs-tasks.amazonaws.com` y policy S3.  
Para el ETL necesitamos además: leer Secrets, escribir logs, y (en AWS) describir EFS.

### 1.1 Execution role (pull imagen + logs)

En Fargate hay **dos** roles:

| Rol | Quién lo usa | Para qué |
|---|---|---|
| **Execution role** | agente ECS | pull ECR, escribir CloudWatch Logs, montar secrets en env |
| **Task role** (`app-role`) | el proceso (Airflow/ETL) | Secrets Manager, S3 staging, connect a RDS vía secret |

```powershell
# Trust compartido ECS (mismo del lab 04)
@'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
'@ | Set-Content -Path ecs\trust_ecs.json -Encoding utf8

awslocal iam create-role `
  --role-name ecsTaskExecutionRole `
  --assume-role-policy-document file://ecs/trust_ecs.json 2>$null

@'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Logs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"],
      "Resource": "*"
    },
    {
      "Sid": "ECRPull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
'@ | Set-Content -Path ecs\execution_policy.json -Encoding utf8

awslocal iam put-role-policy `
  --role-name ecsTaskExecutionRole `
  --policy-name InlineEcsExecution `
  --policy-document file://ecs/execution_policy.json

$EXEC_ROLE = (awslocal iam get-role --role-name ecsTaskExecutionRole --query "Role.Arn" --output text).Trim()
Write-Host "EXEC_ROLE=$EXEC_ROLE"
```

### 1.2 Task role — Secrets ETL + (opcional) staging MinIO

`app-role` ya puede S3. Agregamos lectura del secret de RDS (y placeholders de orígenes):

```powershell
@'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadEtlSecrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      "Resource": [
        "arn:aws:secretsmanager:*:*:secret:dw/rds-etl*",
        "arn:aws:secretsmanager:*:*:secret:dw/erp*",
        "arn:aws:secretsmanager:*:*:secret:dw/ecommerce*",
        "arn:aws:secretsmanager:*:*:secret:dw/eventos*",
        "arn:aws:secretsmanager:*:*:secret:dw/scraping*"
      ]
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*"
    }
  ]
}
'@ | Set-Content -Path ecs\task_secrets_policy.json -Encoding utf8

awslocal iam put-role-policy `
  --role-name app-role `
  --policy-name InlineEtlSecrets `
  --policy-document file://ecs/task_secrets_policy.json

awslocal iam list-role-policies --role-name app-role
```

> En local, MiniStack (`:4567`) guarda `dw/rds-etl`. LocalStack IAM **autoriza el modelo**; la lectura real del secret en el stand-in Docker usa `AWS_ENDPOINT_URL=http://ministack-integrador:4566` (red compose) o el host `localhost:4567`.

---

## Paso 2 — EFS (DAGs + logs)

En AWS real: un file system Multi-AZ, mount targets en **ambas** subnets compute, SG `sg-efs` (2049 solo desde `sg-ecs-etl`).

### 2.1 Crear file system + mount targets (API LocalStack / AWS)

Primero habilitá `efs` (y `ecs`) en LocalStack si querés practicar la API. En `compose.yaml`:

```yaml
# SERVICES: ...,iam,ec2,ecs,efs,secretsmanager,logs,cloudwatch
```

Luego recreá solo LocalStack **sin** `-v` (para no borrar VPC):

```powershell
docker compose up -d localstack-integrador
```

```powershell
# Crear EFS
$FS_ID = (awslocal efs create-file-system `
  --performance-mode generalPurpose `
  --throughput-mode bursting `
  --tags Key=Name,Value=tp-airflow-efs Key=Lab,Value=09b-tp `
  --query "FileSystemId" --output text).Trim()
Write-Host "FS_ID=$FS_ID"

# Access point para DAGs (uid/gid de airflow = 50000 en imagen oficial)
$AP_DAGS = (awslocal efs create-access-point `
  --file-system-id $FS_ID `
  --posix-user Uid=50000,Gid=0 `
  --root-directory "Path=/airflow/dags,CreationInfo={OwnerUid=50000,OwnerGid=0,Permissions=775}" `
  --tags Key=Name,Value=ap-airflow-dags `
  --query "AccessPointId" --output text).Trim()

$AP_LOGS = (awslocal efs create-access-point `
  --file-system-id $FS_ID `
  --posix-user Uid=50000,Gid=0 `
  --root-directory "Path=/airflow/logs,CreationInfo={OwnerUid=50000,OwnerGid=0,Permissions=775}" `
  --tags Key=Name,Value=ap-airflow-logs `
  --query "AccessPointId" --output text).Trim()

# Mount targets en las dos AZ de compute
awslocal efs create-mount-target --file-system-id $FS_ID --subnet-id $SUB_A --security-groups $SG_EFS
awslocal efs create-mount-target --file-system-id $FS_ID --subnet-id $SUB_B --security-groups $SG_EFS

awslocal efs describe-file-systems --file-system-id $FS_ID
awslocal efs describe-mount-targets --file-system-id $FS_ID
```

### Qué modela

| Path EFS | Contenido | Quién escribe |
|---|---|---|
| `/airflow/dags` | DAGs Python (versionados en git → sync) | CI / deploy |
| `/airflow/logs` | Task logs de Airflow | workers Fargate |

**No** va el data warehouse en EFS: los datos van a **RDS `bronce` / `gold`**. EFS es solo orquestación.

### Stand-in local (si la API EFS no responde en Community)

```powershell
New-Item -ItemType Directory -Force -Path ecs\efs-standin\dags, ecs\efs-standin\logs | Out-Null
# Este directorio = EFS en el compose del Paso 5
```

---

## Paso 3 — Cluster ECS + log group

```powershell
awslocal ecs create-cluster --cluster-name tp-airflow `
  --tags key=Name,value=tp-airflow key=Lab,value=09b-tp

awslocal logs create-log-group --log-group-name /ecs/tp-airflow 2>$null

awslocal ecs describe-clusters --clusters tp-airflow `
  --query "clusters[0].{Name:clusterName,Status:status}" --output table
```

---

## Paso 4 — Task definition (Airflow worker / one-shot ETL)

En producción: 3 services (webserver, scheduler, worker) con la misma imagen Airflow y mounts EFS.  
En el lab: una **task definition** de worker/ETL que:

1. Monta EFS (dags + logs)  
2. Usa `app-role` como taskRoleArn  
3. Lee `dw/rds-etl` y escribe en `bronce`

```powershell
# ARNs (LocalStack account 000000000000)
$TASK_ROLE = $APP_ROLE
# Imagen oficial Airflow — en AWS real irá a ECR tras docker push
$IMAGE = "apache/airflow:2.9.3-python3.12"

@'
{
  "family": "tp-airflow-worker",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "EXEC_ROLE_PLACEHOLDER",
  "taskRoleArn": "TASK_ROLE_PLACEHOLDER",
  "containerDefinitions": [
    {
      "name": "airflow-worker",
      "image": "IMAGE_PLACEHOLDER",
      "essential": true,
      "command": ["celery", "worker"],
      "environment": [
        { "name": "AIRFLOW__CORE__LOAD_EXAMPLES", "value": "false" },
        { "name": "AIRFLOW__CORE__EXECUTOR", "value": "CeleryExecutor" },
        { "name": "USE_SECRETS_MANAGER", "value": "1" },
        { "name": "AWS_DEFAULT_REGION", "value": "us-east-1" }
      ],
      "secrets": [],
      "mountPoints": [
        { "sourceVolume": "dags", "containerPath": "/opt/airflow/dags", "readOnly": false },
        { "sourceVolume": "logs", "containerPath": "/opt/airflow/logs", "readOnly": false }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/tp-airflow",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "worker"
        }
      }
    }
  ],
  "volumes": [
    {
      "name": "dags",
      "efsVolumeConfiguration": {
        "fileSystemId": "FS_ID_PLACEHOLDER",
        "transitEncryption": "ENABLED",
        "authorizationConfig": { "accessPointId": "AP_DAGS_PLACEHOLDER", "iam": "ENABLED" }
      }
    },
    {
      "name": "logs",
      "efsVolumeConfiguration": {
        "fileSystemId": "FS_ID_PLACEHOLDER",
        "transitEncryption": "ENABLED",
        "authorizationConfig": { "accessPointId": "AP_LOGS_PLACEHOLDER", "iam": "ENABLED" }
      }
    }
  ]
}
'@ | ForEach-Object {
  $_ -replace "EXEC_ROLE_PLACEHOLDER", $EXEC_ROLE `
     -replace "TASK_ROLE_PLACEHOLDER", $TASK_ROLE `
     -replace "IMAGE_PLACEHOLDER", $IMAGE `
     -replace "FS_ID_PLACEHOLDER", $FS_ID `
     -replace "AP_DAGS_PLACEHOLDER", $AP_DAGS `
     -replace "AP_LOGS_PLACEHOLDER", $AP_LOGS
} | Set-Content -Path ecs\taskdef-airflow-worker.json -Encoding utf8

awslocal ecs register-task-definition --cli-input-json file://ecs/taskdef-airflow-worker.json

awslocal ecs describe-task-definition --task-definition tp-airflow-worker `
  --query "taskDefinition.{Family:family,Cpu:cpu,Memory:memory,Network:networkMode}" --output table
```

### Service Fargate (awsvpc + subnets privadas + sg-ecs-etl)

```powershell
awslocal ecs create-service `
  --cluster tp-airflow `
  --service-name airflow-worker `
  --task-definition tp-airflow-worker `
  --desired-count 1 `
  --launch-type FARGATE `
  --network-configuration "awsvpcConfiguration={subnets=[$SUB_A,$SUB_B],securityGroups=[$SG_ECS],assignPublicIp=DISABLED}"

awslocal ecs describe-services --cluster tp-airflow --services airflow-worker `
  --query "services[0].{Status:status,Desired:desiredCount,Running:runningCount}" --output table
```

`assignPublicIp=DISABLED` + subnets compute + NAT = patrón to-be (salida a orígenes sin exponer la task).

---

## Paso 5 — Stand-in ejecutable: Airflow + “EFS” + escritura a `bronce`

Como Community no corre Fargate, este paso **sí ejecuta** el flujo ETL grupo 1.

### 5.1 Secret origen de demo + DSN hacia MiniStack

Usamos `postgres-bronce` (`localhost:5432`) como **source** (simula un origen externo).  
El destino es el schema `bronce` de MiniStack RDS.

```powershell
# Secret de origen (MiniStack) — demo
$origen = @{
  host = "postgres-bronce"
  port = 5432
  dbname = "bronce"
  username = "postgres"
  password = "postgres"
  engine = "postgres"
} | ConvertTo-Json -Compress

aws --endpoint-url http://localhost:4567 secretsmanager create-secret `
  --name dw/origen-demo `
  --secret-string $origen 2>$null

# Verificar secret ETL (lab 08)
aws --endpoint-url http://localhost:4567 secretsmanager get-secret-value `
  --secret-id dw/rds-etl --query "SecretString" --output text
```

Anotá `host`/`password` de `dw/rds-etl`. El host MiniStack desde otra red Docker suele ser la IP del container `ministack-rds-*-instance-tp-dw-db` o el hostname publicado; desde el host: `localhost` puerto **15432**.

```powershell
docker ps --filter "name=ministack-rds" --format "{{.Names}} {{.Ports}}"
# típico: 0.0.0.0:15432->5432/tcp
```

### 5.2 DAG de ejemplo (grupo 1 → bronce)

Creá `ecs/efs-standin/dags/etl_bronce_origen_demo.py`:

```python
"""DAG ETL grupo 1: origen demo -> schema bronce (tp-dw-db)."""
from __future__ import annotations

import json
import os
from datetime import datetime

import boto3
import psycopg2
from airflow import DAG
from airflow.operators.python import PythonOperator


def _sm(endpoint: str, name: str) -> dict:
    c = boto3.client(
        "secretsmanager",
        endpoint_url=endpoint,
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
    )
    return json.loads(c.get_secret_value(SecretId=name)["SecretString"])


def extract_and_load_bronce(**_):
    sm_url = os.environ["SECRETS_ENDPOINT"]  # http://ministack-integrador:4566 en compose
    origen = _sm(sm_url, os.environ.get("ORIGEN_SECRET", "dw/origen-demo"))
    dest = _sm(sm_url, "dw/rds-etl")

    # 1) EXTRACT desde origen
    src = psycopg2.connect(
        host=origen["host"],
        port=int(origen.get("port", 5432)),
        dbname=origen.get("dbname") or origen.get("database"),
        user=origen["username"],
        password=origen["password"],
    )
    with src.cursor() as cur:
        cur.execute("SELECT current_database(), now()")
        row = cur.fetchone()
    src.close()
    payload = {"source_db": row[0], "extracted_at": str(row[1]), "origen": "origen-demo"}

    # 2) LOAD a bronce (RDS TP)
    # Desde compose, host del secret puede ser IP docker; override opcional:
    dest_host = os.environ.get("RDS_HOST_OVERRIDE", dest["host"])
    dest_port = int(os.environ.get("RDS_PORT_OVERRIDE", dest.get("port", 5432)))

    dst = psycopg2.connect(
        host=dest_host,
        port=dest_port,
        dbname=dest["dbname"],
        user=dest["username"],
        password=dest["password"],
    )
    with dst.cursor() as cur:
        cur.execute(
            "INSERT INTO bronce.ingest_batch (origen, row_count, status) "
            "VALUES (%s, %s, %s) RETURNING batch_id",
            ("origen-demo", 1, "loaded"),
        )
        batch_id = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO bronce.raw_record (batch_id, origen, payload) "
            "VALUES (%s, %s, %s::jsonb)",
            (batch_id, "origen-demo", json.dumps(payload)),
        )
    dst.commit()
    dst.close()
    print(f"OK bronce batch_id={batch_id}")


with DAG(
    dag_id="etl_bronce_origen_demo",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["tp", "bronce", "grupo1"],
) as dag:
    PythonOperator(task_id="extract_load_bronce", python_callable=extract_and_load_bronce)
```

### 5.3 Compose stand-in (Airflow + volumen EFS)

Archivo `ecs/docker-compose.airflow.yaml` (referencia):

```yaml
# Stand-in local del lab 09b-tp: Airflow ≈ ECS Fargate; volumen ≈ EFS
services:
  airflow-init:
    image: apache/airflow:2.9.3-python3.12
    entrypoint: /bin/bash
    command:
      - -c
      - |
        pip install --quiet psycopg2-binary boto3 &&
        airflow db migrate &&
        airflow users create --username admin --password admin --firstname A --lastname A --role Admin --email a@a.com || true
    environment: &airflow_env
      AIRFLOW__CORE__EXECUTOR: LocalExecutor
      AIRFLOW__CORE__LOAD_EXAMPLES: "false"
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://postgres:postgres@postgres-dw:5432/gold
      AIRFLOW__CORE__DAGS_FOLDER: /opt/airflow/dags
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
      AWS_DEFAULT_REGION: us-east-1
      SECRETS_ENDPOINT: http://ministack-integrador:4566
      # Host/puerto alcanzables desde la red compose hacia el Postgres de MiniStack:
      RDS_HOST_OVERRIDE: host.docker.internal
      RDS_PORT_OVERRIDE: "15432"
      ORIGEN_SECRET: dw/origen-demo
    volumes:
      - ./efs-standin/dags:/opt/airflow/dags
      - ./efs-standin/logs:/opt/airflow/logs
    extra_hosts:
      - "host.docker.internal:host-gateway"

  airflow-webserver:
    image: apache/airflow:2.9.3-python3.12
    command: webserver
    ports: ["8080:8080"]
    environment: *airflow_env
    volumes:
      - ./efs-standin/dags:/opt/airflow/dags
      - ./efs-standin/logs:/opt/airflow/logs
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on: [airflow-init]

  airflow-scheduler:
    image: apache/airflow:2.9.3-python3.12
    command: scheduler
    environment: *airflow_env
    volumes:
      - ./efs-standin/dags:/opt/airflow/dags
      - ./efs-standin/logs:/opt/airflow/logs
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on: [airflow-init]
```

> Metadata DB de Airflow: reutilizamos `postgres-dw:5432` solo como **metastore** de Airflow (no confundir con schema `gold` del DW). En AWS real Airflow usa RDS/Aurora propio o el mismo patrón aislado.

```powershell
# Ajustar secret origen para que el host sea alcanzable desde Airflow
$origen = @{
  host = "postgres-bronce"
  port = 5432
  dbname = "bronce"
  username = "postgres"
  password = "postgres"
  engine = "postgres"
} | ConvertTo-Json -Compress
aws --endpoint-url http://localhost:4567 secretsmanager put-secret-value `
  --secret-id dw/origen-demo --secret-string $origen

cd ecs
docker compose -f docker-compose.airflow.yaml up -d
# UI: http://localhost:8080  (admin / admin)
```

En la UI: Trigger DAG `etl_bronce_origen_demo`.

### 5.4 Verificar en RDS `bronce`

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT * FROM bronce.ingest_batch ORDER BY batch_id DESC LIMIT 5;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT id, batch_id, origen, payload FROM bronce.raw_record ORDER BY id DESC LIMIT 5;"
```

Esperado: filas con `origen = origen-demo` y payload JSON.

---

## Paso 6 — Flujo end-to-end (qué debe quedar claro)

```text
1. Airflow scheduler lee DAG desde EFS (/opt/airflow/dags)     ← lab hoy: volumen
2. Worker asume identidad app-role (task role)                 ← lab 04 + Paso 1
3. GetSecretValue dw/origen-demo  → connect SOURCE             ← NAT en AWS; red compose en lab
4. extract + normalize (paquete etl/)                          ← código en etl/
5. GetSecretValue dw/rds-etl      → connect RDS como etl_writer
6. INSERT bronce.ingest_batch + bronce.raw_record              ← lab 08-tp GRANTs
7. Logs de la task → EFS /opt/airflow/logs (+ CloudWatch)      ← sg-efs :2049
```

**Capa de control (igual que lab 08):**

1. **Red:** solo `sg-ecs-etl` llega a `sg-rds:5432` y a `sg-efs:2049`.  
2. **IAM:** task role no es master; solo secrets ETL/orígenes.  
3. **SQL:** `etl_writer` escribe bronce; `api_reader` no ve bronce.

---

## Paso 7 — Documentar decisión

Agregá en [`docs/decisions.md`](../docs/decisions.md) (ADR del TP), alineado a Solution §5.2:

```
### 012 — Airflow en ECS Fargate + EFS (DAGs/logs); datos en RDS Bronce

Decision: orquestar ETL con Airflow sobre Fargate; persistir DAGs/logs en EFS;
escribir crudos en Bronce (schema bronce de tp-dw-db) vía secret dw/rds-etl.
Justificación: docs/Solution_Architecture.md §5.2 (vs EC2 / MWAA).

Contexto: to-be sin EC2 (Infraestructure_Architecture); NAT para orígenes;
VPC lab 07-v2 ya define sg-ecs-etl / sg-efs / subnets compute.

Alternativas: MWAA (managed), Airflow solo en EC2, Step Functions + Lambda.

Tradeoff: Fargate + EFS tiene costo (~USD 48 + EFS en finops); EFS no
reemplaza el DW. LocalStack modela API; ejecución del lab usa compose.

Resultado: lab 09b-tp — IAM execution/task, EFS, ECS taskdef/service,
DAG demo → bronce.
```

---

## Paso 8 — Cleanup

```powershell
# Stand-in
cd ecs
docker compose -f docker-compose.airflow.yaml down

# API LocalStack (si creaste recursos)
awslocal ecs update-service --cluster tp-airflow --service airflow-worker --desired-count 0
awslocal ecs delete-service --cluster tp-airflow --service airflow-worker --force
awslocal ecs delete-cluster --cluster tp-airflow
# EFS: borrar mount targets → access points → file system (orden AWS)
```

No borres la VPC ni RDS: siguen para el resto del TP.

---

## Checkpoint

- [ ] `app-role` tiene policy de Secrets ETL; existe `ecsTaskExecutionRole`
- [ ] EFS (API) o stand-in `ecs/efs-standin/{dags,logs}` listo
- [ ] Cluster `tp-airflow` + task definition `tp-airflow-worker` (awsvpc, Fargate)
- [ ] Service en subnets `Role=ecs-lambda-efs` + `sg-ecs-etl`, sin IP pública
- [ ] DAG `etl_bronce_origen_demo` triggereado
- [ ] Filas nuevas en `bronce.ingest_batch` / `bronce.raw_record`
- [ ] Entendido: EFS = orquestación; RDS bronce = datos; NAT = salida a orígenes

---

## Para llevar: LocalStack vs AWS real

| Acción | LocalStack Community + stand-in | AWS real |
|---|---|---|
| IAM roles / policies ECS | ✅ | ✅ |
| Subnets + SG (sg-ecs-etl, sg-efs) | ✅ (lab 07-v2) | ✅ |
| EFS create + mount targets | ⚠️ API parcial / Pro | ✅ |
| ECS RunTask / Service Fargate | ⚠️ API; sin ENI real | ✅ |
| Montaje NFS EFS en la task | ❌ → volumen Docker | ✅ |
| ETL escribe `bronce` | ✅ vía MiniStack + compose | ✅ |
| Egress orígenes vía NAT | ⚠️ topología sí; paquetes limitados | ✅ |
| Imagen en ECR | ⚠️ | ✅ |

---

## Archivos de este lab

| Archivo | Rol |
|---|---|
| `ecs/lab-09b-tp.md` | Este documento |
| `ecs/trust_ecs.json` | Trust `ecs-tasks.amazonaws.com` |
| `ecs/execution_policy.json` | Execution role (logs/ECR) |
| `ecs/task_secrets_policy.json` | Task role Secrets ETL |
| `ecs/taskdef-airflow-worker.json` | Task definition Fargate (generada) |
| `ecs/efs-standin/` | Volumen local ≈ EFS (dags/logs) |
| `ecs/docker-compose.airflow.yaml` | Stand-in ejecutable Airflow |
| `etl/` | Lógica extract/transform/load (importable desde DAGs) |

---

## Relación con labs previos y `docs/`

| Fuente | Aporte que reutilizamos |
|---|---|
| `docs/Infraestructure_Architecture.md` | Capas VPC; Fargate+EFS; RDS Multi-AZ |
| `docs/Solution_Architecture.md` §4–5 | Flujo grupo 1→Bronce; justificación Fargate; NAT/endpoints |
| Lab 04 IAM | `app-role` + trust ECS + S3 staging |
| Lab 06 MinIO | `staging-data-lake` |
| Lab 07-v2 VPC | compute, NAT, `sg-ecs-etl`, `sg-efs`, `sg-rds` |
| Lab 08-tp RDS | `tp-dw-db`, schema `bronce`, secret `dw/rds-etl` |
| Lab 09 IaC | Declarar runtime; 09b declara cómputo ETL (F3 del Gantt) |
