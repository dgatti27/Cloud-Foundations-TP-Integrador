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
├── Solution_Arquitecture.md   # plan de migracion (entregable principal)
├── .github/
│   └── workflows/
│       └── ci.yml             # validaciones CI (GitHub Actions)
├── assets/                    # diagramas del plan (as-is, to-be, Gantt)
│   ├── arquitectura-as-is.png
│   ├── arquitectura-to-be.png
│   └── gantt-migracion.png
├── docs/
│   ├── architecture.md        # as-is / to-be, SPOFs, decisiones de identidad
│   ├── decisions.md           # ADRs / justificaciones de la arquitectura to-be
│   └── img/                   # diagramas as-is, to-be y Gantt (PNG)
├── etl/                       # logica de los ETL (paquete Python)
│   ├── extract/               # un modulo por origen (ERP FoxPro, Mongo x2, scraping)
│   ├── transform/             # normalizacion
│   ├── load/                  # grupo 1 -> cruda ; grupo 2 -> DW
│   ├── config.py
│   ├── requirements.txt
│   └── README.md
├── finops/                    # estimador de costos
├── iac/                       # provisioning reproducible
├── iam/                       # identidad y accesos
├── monitoring/                # observabilidad
├── rds/                       # base de datos (Bronce + DW)
├── s3/                        # almacenamiento de objetos
└── vpc/                       # red y aislamiento
```

## Como correr el codigo reproducible

Hay tres vias equivalentes; elegí una. Requisitos: Docker + Docker Compose y,
para A/B, AWS CLI y Terraform/OpenTofu.

### Opcion A — Script AWS CLI (LocalStack)

```bash
docker compose up -d localstack        # compose del repo del curso (:4566)
./iac/aws-cli/provision_localstack.sh          # IAM, VPC/red, S3, Secrets, Lambda
./iac/aws-cli/provision_localstack.sh --verify # lista lo creado
./iac/aws-cli/teardown.sh                       # limpiar
```

### Opcion B — Terraform / OpenTofu (LocalStack)

```bash
cd iac/terraform
tofu init && tofu apply -auto-approve  # o terraform ...
tofu output
tofu destroy -auto-approve
```

### Opcion C — Stack local completo con MiniStack (sustitutos)

Corre la arquitectura entera en tu maquina sin AWS, con **MiniStack** (emulador
libre). La base del DW es un recurso **RDS real** gobernado por IAM (no un
Postgres suelto). MiniStack auto-provisiona RDS+IAM+S3+Secrets al arrancar. Ver
`iac/local-docker/README.md`.

```bash
cd iac/local-docker && cp .env.example .env && docker compose up -d
# Airflow UI http://localhost:8080 (airflow/airflow) · MiniStack :4566 · RDS :15432
```

### Costos (AWS real, cualquier opcion)

```bash
python3 finops/pricing.py --services finops/services.json --budget 300
```

## Validaciones (CI · GitHub Actions)

En cada push / pull request corre `.github/workflows/ci.yml` con 5 jobs:

| Job | Qué valida |
|---|---|
| `python-etl` | ruff (errores), `py_compile` del paquete `etl/` y los DAGs, e import + smoke test del flujo ETL |
| `shell` | `bash -n` y ShellCheck (severidad error) de los scripts AWS CLI |
| `terraform` | `terraform fmt -check`, `init -backend=false` y `validate` de `iac/terraform` |
| `compose` | `docker compose config` del stack local |
| `finops` | valida `services.json` y corre el estimador de costos |

## Nota sobre LocalStack Community

ECS Fargate, RDS y ELBv2 requieren LocalStack **Pro**. Por eso el proyecto ofrece
**dos tratamientos** de esos servicios:

1. **Documentados como `[AWS-REAL]`** en las opciones A (script) y B (Terraform):
   los recursos que LocalStack Community soporta (IAM, VPC/red, S3, Secrets,
   Lambda) se levantan de verdad, y RDS/ECS Fargate/ELB quedan como bloques
   comentados listos para AWS real.
2. **Sustitutos locales (Docker)** en la opcion C: con **MiniStack**, RDS es un
   Postgres real gestionado (gobernado por IAM), ELB/Lambda/S3/Secrets también se
   emulan, y ECS Fargate → contenedor Airflow. MiniStack es la clave para que las
   políticas IAM alcancen a la base (un Postgres suelto quedaría fuera de IAM).

Asi se levantan **≥5 servicios reales** por debajo (IAM, red VPC, S3, Secrets,
Lambda), por encima del minimo de 4 que pide la consigna, y ademas queda una via
para probar el flujo ETL end-to-end en local.
