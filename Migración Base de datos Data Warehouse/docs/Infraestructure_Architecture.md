# Arquitectura — Migracion Datawarehouse a AWS

## Situacion actual (as-is)

**Dos servidores** en un hosting compartido concentran toda la operacion analitica:

- **Servidor 1 (datos)**: base **BRONCE** en PostgreSQL + **Datawarehouse** en PostgreSQL.
- **Servidor 2 (computo/BI)**: **Airflow dockerizado** (DAGs Python) + sirve las consultas de BI.
- Los ETL se conectan **por host, conexion directa (sin API)** a 4 origenes: ERP
  (tablas FoxPro), Ecommerce (MongoDB), Eventos (MongoDB) y repositorio de scraping.
- Flujo: origenes -> **ETL grupo 1** -> base BRONCE -> **ETL grupo 2** (procesa) -> DW.
- **Qlik** (BI) lee el DW tambien **por host, sin API**.

![As-is](img/arch_asis.png)

### Puntos unicos de falla (SPOF)

| SPOF | Riesgo | Mitigacion to-be |
|---|---|---|
| Dos servidores sin replica | La caida del server de datos tira base bronce + DW | Separar computo de datos (RDS Multi-AZ) |
| Base bronce y DW en el mismo host | Ingesta y consultas compiten por CPU/disco | RDS dedicado + staging en S3 |
| PostgreSQL single instance | Perdida de datos ante fallo de disco/AZ | RDS Multi-AZ con standby en otra AZ |
| Sin backups gestionados | Recuperacion manual y lenta | Backups automaticos RDS + snapshots a S3 |
| Credenciales en el server  | Secrets Manager + IAM |
| Config manual no versionada | No reproducible | IaC / script AWS CLI + Git |
| Escala fija del hosting | No absorbe picos de carga ETL/BI | Instancias dimensionadas + margen elastico |

## Situacion objetivo (to-be)

![To-be](img/arch_tobe.png)

Arquitectura de 3 capas dentro de una **VPC 10.0.0.0/16** en **us-east-1**:

- **Subred publica**: ALB (HTTPS) + NAT Gateway.
- **Subred privada app (serverless, sin EC2)**: ECS Fargate con Airflow dockerizado (tasks scheduler/webserver/worker) + EFS + Lambda (API DW).
- **Subred privada datos (2 AZ)**: RDS PostgreSQL db.t3.medium **Multi-AZ** (aloja base cruda + DW).
- **Transversal**: IAM (roles minimos), S3 (staging/backups/data lake),
  Secrets Manager (credenciales de los 4 origenes + RDS), CloudWatch (logs/metricas).

## Mapeo local → cloud (continuidad con el repo del curso)

| Local (lab) | Cloud (to-be) |
|---|---|
| MiniStack RDS (Postgres real, bronce + DW) | RDS PostgreSQL Multi-AZ (2 bases) |
| Airflow (Docker) | ECS Fargate + EFS (sin EC2) |
| MinIO | S3 |
| MiniStack (IAM/RDS/S3/Secrets/ELB) | Servicios AWS reales |
| Script AWS CLI | Provisioning reproducible (`iac/aws-cli`) |
