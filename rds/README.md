# `rds/` — Bases de datos RDS (curso + TP Integrador)

## TP Integrador (usar esto)

Provisiona la RDS del proyecto: **una instancia PostgreSQL Multi-AZ** con schemas **`bronce`** (ETL escribe) y **`gold`** (Lambda API lee). Reusa la VPC/`sg-rds`/subnets del lab 07-v2 y deja el dump del snapshot en `s3://snapshot-data-lake`.

| Archivo | Rol |
|---|---|
| [`lab-08-tp.md`](./lab-08-tp.md) | Guía paso a paso del TP |
| [`rds_tp_config.json`](./rds_tp_config.json) | Parámetros declarativos |
| [`seed_tp.sql`](./seed_tp.sql) | Schemas, roles, GRANTs, tablas demo |
| [`rds_tp_demo.py`](./rds_tp_demo.py) | Orquestación end-to-end |

```bash
# Prereqs: lab 04 + 06 + 07-v2 en LocalStack :4566, MiniStack :4567
docker compose up -d localstack-integrador ministack-integrador
python rds/rds_tp_demo.py
```

### Endpoints (importante)

| Emulador | Puerto | Servicios en este lab |
|---|---|---|
| LocalStack | `:4566` | S3 (`snapshot-data-lake`), EC2/VPC (lab 07-v2) |
| MiniStack | `:4567` | RDS (Postgres real), Secrets Manager (credenciales DB) |

El dump del snapshot **siempre** va al S3 de LocalStack, no al de MiniStack.

### Decisiones del TP

- `db.t3.medium` + `MultiAZ: true` — alineado al to-be
- `PubliclyAccessible: false` + `sg-rds` — solo `sg-api` y `sg-ecs-etl`
- Credenciales en Secrets Manager: `dw/rds-master`, `dw/rds-etl`, `dw/rds-api`
- Snapshot API + `pg_dump` → bucket `snapshot-data-lake` (en AWS real: export task)

---

## Lab 08 del curso (referencia)

Modelo pedagógico del curso (`app-db`, schemas `public` + `analytics`). No lo uses para el TP.

| Archivo | Rol |
|---|---|
| [`lab-08.md`](./lab-08.md) | Guía del curso |
| [`rds_config.json`](./rds_config.json) | Config curso |
| [`seed.sql`](./seed.sql) | Seed curso |
| [`rds_demo.py`](./rds_demo.py) | Demo curso |
