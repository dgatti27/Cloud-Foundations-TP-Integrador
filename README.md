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
├── Dockerfile                 # imagen toolbox (OpenTofu + proyecto) — ver iac/DOCKER.md
├── docker-compose.iac.yaml    # servicio tp-iac (profile: iac)
├── compose.yaml               # LocalStack + MiniStack + MinIO + Postgres
├── Solution_Arquitecture.md   # plan de migracion (entregable principal)
├── .github/
│   └── workflows/
│       └── ci.yml             # validaciones CI (GitHub Actions)
├── assets/                    # diagramas del plan (as-is, to-be, Gantt)
├── docs/
├── etl/                       # logica de los ETL (paquete Python)
├── finops/                    # estimador de costos
├── iac/                       # OpenTofu + demos + DOCKER.md
├── iam/                       # identidad y accesos
├── monitoring/                # observabilidad
├── rds/                       # base de datos (Bronce + DW)
├── s3/                        # almacenamiento de objetos
├── ecs/                       # Airflow stand-in / Fargate model
├── lambda/                    # API gold
└── vpc/                       # red y aislamiento
```

## Ejecutar IaC (OpenTofu)

Levanta IAM, VPC, S3 (MinIO), RDS, Secrets, CloudWatch, Lambda y marcadores ECS/EFS de forma **idempotente**.

Docs: [`iac/lab-09-tp.md`](iac/lab-09-tp.md) · imagen Docker: [`iac/DOCKER.md`](iac/DOCKER.md)

### 1. Prerequisitos

```bash
cp .env.example .env
# Editá .env y seteá LOCALSTACK_AUTH_TOKEN (LocalStack Hobby)
```

### 2. Emuladores

```bash
docker compose up -d
docker compose ps   # localstack / ministack / s3-soporte → healthy
```

### 3. Aplicar la infraestructura

**Opción A — en el host** (necesitás OpenTofu + Python/boto3):

```bash
# Primera vez si ya corriste demos a mano (roles/buckets/RDS):
python iac/iac_demo.py --reconcile

# Apply (re-ejecutable; segundo run ≈ sin cambios):
python iac/iac_demo.py
```

**Opción B — con la imagen toolbox** (sin instalar `tofu` en el host):

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac build tp-iac

# Primera vez con restos de demos imperativos:
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac apply-reconcile

# Apply idempotente:
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac apply
```

### 4. Verificar

```bash
# Host
cd iac/tp && tofu output

# O desde la imagen
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac tofu output
```

Checks útiles:

```bash
aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db
aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api
```

### 5. Runtime Hobby (opcional)

```bash
python ecs/ecs_demo.py       # Airflow ≈ Fargate
python lambda/lambda_demo.py # API gold / ALB stand-in
```

### Cleanup

```bash
python iac/iac_demo.py --destroy
# o: docker compose … run --rm tp-iac destroy

docker compose down          # no uses -v si querés conservar datos
```
