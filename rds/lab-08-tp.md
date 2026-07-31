# Lab 08 TP — RDS del Integrador: schemas `bronce` + `gold`

Adapta el modelo del [lab-08.md](./lab-08.md) del curso a la arquitectura del **TP Integrador**.

Una instancia RDS PostgreSQL Multi-AZ (`tp-dw-db`), base `dw`, con:

| Schema | Quién escribe | Quién lee | Uso |
|---|---|---|---|
| `bronce` | ECS ETL (`etl_writer`) | Solo ETL | Datos crudos desde data sources |
| `gold` | ECS ETL grupo 2 (`etl_writer`) | Lambda API (`api_reader`) | Analytics / DW procesado |

> **Engine real vía MiniStack + object storage MinIO**  
> MiniStack (`:4567`) levanta Postgres real con `create-db-instance`.  
> MinIO (`:9000`) guarda el dump del snapshot (`snapshot-data-lake`) — decisión 002.  
> LocalStack (`:4566`) = VPC lab 07-v2 / IAM. **S3 de LocalStack queda comentado** en `compose.yaml`.

---

## Prerequisitos

```bash
# Emuladores + MinIO
docker compose up -d localstack-integrador ministack-integrador s3-soporte

# Lab 04 — roles IAM (LocalStack)
awslocal iam get-role --role-name app-role --query "Role.Arn"

# Bucket de snapshots en MinIO (:9000)
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls | findstr snapshot-data-lake

# Lab 07-v2 — VPC + SG + subnets RDS (LocalStack)
awslocal ec2 describe-vpcs --filters Name=tag:Name,Values=tp-integrador-vpc \
  --query "Vpcs[0].VpcId"
awslocal ec2 describe-security-groups --filters Name=group-name,Values=sg-rds \
  --query "SecurityGroups[0].GroupId"

# MiniStack arriba
curl -s http://localhost:4567/_ministack/health
```

Si falta el bucket:

```bash
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 mb s3://snapshot-data-lake
```

---

## Paso 1 — Plan declarativo

```bash
cat rds/rds_tp_config.json
cat rds/seed_tp.sql
```

Decisiones respecto al lab-08 del curso:

| Parámetro | Lab 08 curso | TP Integrador | Por qué |
|---|---|---|---|
| VPC | `course-vpc` | `tp-integrador-vpc` | Red Multi-AZ del TP |
| SG | crea `db-sg` | **reusa** `sg-rds` | Ya cableado a `sg-api` / `sg-ecs-etl` |
| Subnets | 1 privada genérica | `private-rds-a` + `private-rds-b` | Multi-AZ real |
| Instance | `db.t3.micro` / Single-AZ | `db.t3.medium` / **MultiAZ=true** | To-be del TP |
| Schemas | `public` + `analytics` | **`bronce` + `gold`** | Medallón del DW |
| Snapshot | solo API RDS | API MiniStack + **dump a MinIO** | Bucket `snapshot-data-lake` |
| Endpoint | uno solo `:4566` | **MinIO `:9000` + LocalStack `:4566` + MiniStack `:4567`** | lake / VPC / RDS |

---

## Paso 2 — Correr el demo end-to-end

```bash
python rds/rds_tp_demo.py
```

Secuencia:

1. Secret master `dw/rds-master`
2. Lookup VPC / subnets RDS / `sg-rds` (sin recrear)
3. DB subnet group `tp-rds-subnets`
4. `create-db-instance` → container postgres
5. Wait `available`
6. `seed_tp.sql` (schemas, roles, bronce staging + Modelo_DW en gold)
7. Secrets app: `dw/rds-etl`, `dw/rds-api`
8. Verificar privilegios
9. Snapshot RDS (MiniStack) + `pg_dump` → **MinIO** `s3://snapshot-data-lake/...`

Output esperado (extracto):

```text
8. Verificar privilegios y filas demo
    schemas=bronce,gold
    bronce.ingest_batch=1
    gold.tables=19
    gold.dim_producto=1
    gold.dim_fecha=1
    api_can_select_gold=true
    api_can_insert_gold=false
    api_can_select_bronce=false
    etl_can_insert_bronce=true
    etl_can_insert_gold=true

9. Snapshot RDS + dump a MinIO s3://snapshot-data-lake
  ✓ RDS snapshot: tp-dw-db-snap-...
  ✓ dump en s3://snapshot-data-lake/rds/tp-dw-db/...
```

---

## Paso 3 — Modelo de datos y permisos

```text
dw/
├── bronce/                 ← crudo / staging (ETL escribe)
│   ├── ingest_batch
│   └── raw_record
└── gold/                   ← DW Modelo_DW (API lee)
    ├── dim_* / bridge_*
    └── fact_*
```

### Capas de control

1. **Red (SG):** solo ENIs con `sg-api` o `sg-ecs-etl` llegan al puerto 5432 de `sg-rds`. Internet no.
2. **Credencial (Secrets Manager):**
   - ECS lee `dw/rds-etl` → usuario `etl_writer`
   - Lambda lee `dw/rds-api` → usuario `api_reader`
3. **SQL (GRANT):** aunque alguien robe el secret de la API, `api_reader` **no** puede leer `bronce` ni escribir `gold`.

```text
Data sources ──NAT──► ECS ETL (etl_writer)
                         │ INSERT bronce.*
                         │ ETL grupo 2 → INSERT/UPDATE gold.*
                         ▼
                      RDS tp-dw-db
                         ▲
                         │ SELECT gold.*
BI ──HTTPS──► ALB ──► Lambda (api_reader)
```

---

## Paso 4 — Verificar MiniStack y explorar la DB

Credenciales API MiniStack: `test` / `test`. Endpoint: `http://localhost:4567`.

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

# Health (en PowerShell usá curl.exe, no el alias curl)
curl.exe -s http://localhost:4567/_ministack/health

# Instancia RDS
aws --endpoint-url http://localhost:4567 rds describe-db-instances `
  --query "DBInstances[].{Id:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}" `
  --output table

# Secrets del lab
aws --endpoint-url http://localhost:4567 secretsmanager list-secrets `
  --query "SecretList[].Name" --output table

# Snapshots RDS (API MiniStack)
aws --endpoint-url http://localhost:4567 rds describe-db-snapshots `
  --db-instance-identifier tp-dw-db --output table
```

Entrar a Postgres (MiniStack nombra el container `ministack-rds-<hash>-instance-tp-dw-db`):

```powershell
# Descubrir el nombre real
docker ps --filter "name=ministack-rds" --format "{{.Names}}"

# Ejemplo (ajustá el nombre si cambia el hash):
docker exec -it ministack-rds-281afe4a44d7-instance-tp-dw-db psql -U dwadmin -d dw
```

Dentro de `psql`:

```sql
\dn
\dt bronce.*
\dt gold.*

-- Simular ETL (escritura bronce)
SET ROLE etl_writer;
INSERT INTO bronce.ingest_batch (origen, row_count) VALUES ('ecommerce', 10);
SELECT * FROM bronce.ingest_batch;

-- Simular API (solo gold)
SET ROLE api_reader;
SELECT * FROM gold.dim_producto;        -- OK (fila SK=-1)
SELECT * FROM bronce.raw_record;        -- ERROR: permission denied
INSERT INTO gold.dim_producto ("producto_sk","producto_bk","categoria_sk","fecha_desde","es_vigente")
  VALUES (99,'x',-1,CURRENT_DATE,true); -- ERROR: permission denied
```

---

## Paso 5 — Verificar MinIO (S3) y snapshot

Credenciales MinIO: `minioadmin` / `minioadmin`. Endpoint: `http://localhost:9000`. UI: http://localhost:9001

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"

# Listar buckets del lake
aws --endpoint-url http://localhost:9000 s3 ls

# Dump del lab 08 (tras el paso 9 del demo)
aws --endpoint-url http://localhost:9000 s3 ls s3://snapshot-data-lake/rds/tp-dw-db/ --recursive
```

| En el lab (ministack + MinIO) | En AWS real |
|---|---|
| `create-db-snapshot` (API MiniStack) | Igual (snapshot gestionado RDS) |
| `pg_dump` → `PutObject` a MinIO | `start-export-task` (export a Parquet en S3) con rol `db-role` |

El bucket vive en el volume `minio-data` (sobrevive a `docker compose down` sin `-v`).

> **No mezclar endpoints:** MinIO = `:9000` · LocalStack (VPC/IAM) = `:4566` · MiniStack (RDS/Secrets) = `:4567`.

---

## Paso 6 — Cómo lo consumen ETL y Lambda (siguiente lab)

```python
# ECS ETL
secret = secretsmanager.get_secret_value(SecretId="dw/rds-etl")
# → connect como etl_writer, search_path=bronce,gold

# Lambda API
secret = secretsmanager.get_secret_value(SecretId="dw/rds-api")
# → connect como api_reader, search_path=gold
# SELECT solo sobre gold.* — nunca bronce
```

---

## Checkpoint

- [ ] `python rds/rds_tp_demo.py` termina sin error
- [ ] MiniStack: `tp-dw-db` available + secrets `dw/rds-*`
- [ ] MinIO: buckets lake listables; objeto en `s3://snapshot-data-lake/rds/tp-dw-db/`
- [ ] `\dn` muestra `bronce` y `gold`
- [ ] `api_can_select_gold=true` y `api_can_select_bronce=false`
- [ ] `etl_can_insert_bronce=true`
- [ ] Snapshot RDS `available`
- [ ] SG usado = `sg-rds` (no se creó otro)

---

## Archivos

| Archivo | Rol |
|---|---|
| `rds_tp_config.json` | Parámetros de instancia, secrets, subnet group, bucket snapshot |
| `seed_tp.sql` | Schemas, roles, GRANTs, bronce staging + Modelo_DW en gold |
| `rds_tp_demo.py` | Orquestación end-to-end |
| `lab-08.md` | Lab del curso (referencia; no pisar) |
