# Migracion Base de datos Datawarehouse → AWS

Plan de migracion de Datawarehouse (hoy en un hosting local) hacia AWS. 
Se dimensiona y justifica la infraestructura.
Se emula con codigo reproducible sobre **LocalStack**.

Nota: Basado en las convenciones del repo del curso `cloud-foundations-lab`.

## Que se migra

- La **base de datos bronce** y el **Datawarehouse** (ambos en PostgreSQL) → **RDS PostgreSQL Multi-AZ** (una instancia, dos bases).
- **ETLs** (sobre Airflow dockerizado, DAGs Python) que alimentan el DW desde la Bronce DB y con origen en diferentes fuentes de datos:
  ERP (FoxPro), el Ecommerce (MongoDB), Eventos (MongoDB) y scraping (Repo CSV) → **ECS Fargate** (serverless, sin EC2).
- **API** que expone el DW para que **Qlik** lo consuma → **Lambda detras de ALB**.

## Adicionalemente
Los ETLs y Qlik se conectan **por host conextion** a las bases de datos (conexion directa a la base), no por API; eso se
respeta con **VPC**, subredes privadas y **IAM**, security groups y roles, y (en AWS real) **VPN/Direct Connect** hacia los origenes on-host. 
El computo de los ETL es serverless sobre **ECS Fargate + EFS**: no se usa EC2.

## Estructura

```
.
├── README.md
├── compose.yaml               # runtime local: emuladores + Airflow + ALB + pgAdmin
├── requirements.txt
├── docker/                    # imagen toolbox OpenTofu
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── DOCKER.md
├── docs/                      # arquitectura / ADRs
├── infra/                     # única fuente IaC (OpenTofu)
│   ├── main.tf
│   ├── modules/               # iam, vpc, s3, rds, secrets, lambda, ecs, cloudwatch
│   └── scripts/post_rds.py
├── apps/
│   ├── etl/                   # paquete Python de pipelines
│   ├── api/                   # Lambda handler + ALB stand-in
│   └── airflow/               # DAGs + logs (≈ EFS)
├── data/rds/                  # seeds SQL
├── ops/                       # pgAdmin + scripts de bootstrap
├── labs/                      # labs del curso (demos + iac pedagógicos)
└── .github/workflows/
```

## Ejecutar IaC (OpenTofu)

Levanta IAM, VPC, S3 (MinIO), RDS, Secrets, CloudWatch, Lambda y marcadores ECS/EFS de forma **idempotente**.

Docs: [`docker/DOCKER.md`](docker/DOCKER.md)

### 1. Prerequisitos

```bash
cp .env.example .env
# Editá .env y seteá LOCALSTACK_AUTH_TOKEN (LocalStack Hobby)
```

### 2. Emuladores

```bash
docker compose up -d
docker compose ps   # localstack / ministack / minio / airflow / alb / pgadmin → healthy
```

### 3. Aplicar la infraestructura

**Opción A — en el host** (necesitás OpenTofu + Python/boto3):

```bash
# Primera vez / apply (re-ejecutable; segundo run ≈ sin cambios):
cd infra && tofu init && tofu apply
```

**Opción B — con la imagen toolbox** (sin instalar `tofu` en el host):

```bash
docker compose --profile iac build tp-iac

# Primera vez con restos de demos imperativos:
docker compose --profile iac run --rm tp-iac apply-reconcile

# Apply idempotente:
docker compose --profile iac run --rm tp-iac apply
```

### 4. Verificar

```bash
# Host
cd infra && tofu output

# O desde la imagen
docker compose --profile iac run --rm tp-iac tofu output
```

Checks útiles:

```bash
aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db
aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api
```

### 5. Runtime Hobby

Airflow (`:8080`) y ALB stand-in (`:8088`) ya arrancan con `docker compose up -d`.
Los demos Python triggerean DAGs / invocan la Lambda (no hace falta otro compose).

### Cleanup

```bash
cd infra && tofu destroy
# o: docker compose --profile iac run --rm tp-iac destroy

docker compose down          # no uses -v si querés conservar datos
```
