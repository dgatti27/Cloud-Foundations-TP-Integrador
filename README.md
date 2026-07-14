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
