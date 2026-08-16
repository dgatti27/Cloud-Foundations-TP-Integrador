# Migración Datawarehouse → AWS (TP Integrador)

Plan de migración de un Datawarehouse on-host hacia AWS, emulado de forma
reproducible con **LocalStack Hobby + MiniStack + MinIO + OpenTofu**.

## Qué se migra

- **Bronce + gold** (PostgreSQL) → **RDS PostgreSQL Multi-AZ** (una instancia, dos schemas). Gold del TP: **6 dims + 2 facts**.
- **ETLs** (Airflow / DAGs Python) desde origen ERP (Postgres) → **ECS Fargate + EFS** (sin EC2). En Hobby: Compose Airflow + `apps/airflow/` ≈ EFS.
- **API** de solo lectura sobre gold → **Lambda detrás de ALB**. En Hobby: Lambda LocalStack + ALB stand-in `:8088`.

Red: **VPC**, subnets privadas, **IAM**, security groups. Cómputo ETL serverless (**Fargate + EFS**).

Guía Docker/toolbox: [`docker/DOCKER.md`](docker/DOCKER.md).  
Arquitectura: [`docs/`](docs/) · FinOps: [`docs/finops.md`](docs/finops.md) · Decisiones: [`docs/decisions.md`](docs/decisions.md).

## Estructura

```
.
├── compose.yaml               # runtime local (un solo up -d)
├── docker/                    # imagen toolbox OpenTofu
├── infra/                     # única fuente IaC (tofu apply)
│   └── modules/               # iam, vpc, s3, rds, secrets, lambda, ecs, cloudwatch, finops
├── apps/
│   ├── pipeline/              # paquete Python ETL (extract/transform/load)
│   ├── api/                   # Lambda handler + ALB stand-in
│   └── airflow/               # DAGs + logs (≈ EFS)
├── data/rds/                  # seed_tp.sql
├── ops/                       # pgAdmin + scripts
└── test/                      # evidencia / logs de smoke + IaC
```

## Datos: esquemas y procesamiento

### Flujo (camino ERP)

```text
postgres-erp          Airflow (≈ Fargate + EFS)              RDS MiniStack (db dw)
(Compose :5434)       apps/airflow/dags/                     schemas bronce + gold
─────────────────     ──────────────────────────            ─────────────────────
Clientes              etl_erp_to_bronce                     bronce.erp_*
Productos    ──────►  extract → normalize → load   ──────►  bronce.ingest_batch
Ventas                                                      │
                      etl_bronce_to_gold                    ▼
                      extract → to_gold → load     ──────►  gold.dim_* / fact_*
                                                            │
Lambda tp-gold-api ◄────────────────────────────────────────┘
(ALB :8088 /gold/query)   solo SELECT (api_reader)
```

Orquestación: `python labs/ecs/ecs.py --skip-infra --erp` (o Trigger en la UI Airflow `:8080`).  
Origen ERP: Compose (`postgres-erp` + seed) · secret `dw/erp`: OpenTofu (`tofu apply`).

### Bases y schemas

| Dónde | Rol | Quién escribe | Quién lee |
|-------|-----|---------------|-----------|
| **`postgres-erp`** (Compose) | Origen externo simulado | seed `apps/pipeline/erp/seed_erp.sql` | ETL extract |
| **`postgres-bronce`** (Compose) | Stub de conectividad (camino A) | — | DAG `etl_rds_comprobation` |
| **RDS `dw`** schema **`bronce`** | Landing / crudo | `etl_writer` (DAGs grupo 1) | ETL grupo 2 |
| **RDS `dw`** schema **`gold`** | DW dimensional (TP) | `etl_writer` (DAG grupo 2) | Lambda `api_reader` |

El seed IaC (`data/rds/seed_tp.sql`, con `apply_rds_seed=true`) crea schemas, roles, tablas gold y staging bronce genérico.

### Schema `bronce` (RDS)

| Tabla | Origen | Contenido |
|-------|--------|-----------|
| `ingest_batch` | seed + DAGs | Metadatos de cada carga |
| `raw_record` | DAG `etl_rds_comprobation` | Payload JSON de prueba de conectividad |
| `erp_clientes` / `erp_productos` / `erp_ventas` | DAG `etl_erp_to_bronce` | Landing columnar del ERP (DDL en `apps/pipeline/sql/bronce_erp_ddl.sql`) |

### Schema `gold` (RDS) — modelo TP

**6 dimensiones + 2 hechos** (acotado al integrador; geo y categoría van embebidas en cliente/producto):

| Tipo | Tabla | Notas |
|------|-------|--------|
| Dim | `dim_fecha` | SK `AAAAMMDD` |
| Dim | `dim_cliente` | + `pais` / `provincia` / `ciudad` |
| Dim | `dim_producto` | + `rubro` / `familia` |
| Dim | `dim_canal` | web / marketplace / tienda_fisica |
| Dim | `dim_metodo_pago` | tarjeta / efectivo / … |
| Dim | `dim_moneda` | ISO (ARS, …) |
| Fact | `fact_venta_linea` | Grano: línea de pedido (carga el ETL ERP) |
| Fact | `fact_venta_devolucion` | Lista para el TP; carga opcional |

Allowlist API: esas 8 tablas (`apps/api/query_gold.py`). No existe `hecho_ventas`.

### DAGs y módulos Python

| DAG (`apps/airflow/dags/`) | Qué hace | Código de negocio (`apps/pipeline/`) |
|----------------------------|----------|----------------------------------|
| `etl_rds_comprobation` | Camino A: secrets + INSERT mínimo en `raw_record` | (lógica inline en el DAG) |
| `etl_erp_to_bronce` | Grupo 1: ERP → `bronce.erp_*` | `extract/erp_foxpro.py` → `transform/normalize.py` → `load/to_cruda.py` |
| `etl_bronce_to_gold` | Grupo 2: bronce → dims + `fact_venta_linea` | `extract/from_bronce.py` → `transform/to_gold.py` → `load/to_dw.py` |

Conexiones vía Secrets Manager (MiniStack `:4567`):

| Secret | Uso |
|--------|-----|
| `dw/erp` | Extract desde `postgres-erp` |
| `dw/origen-demo` | Camino A (`postgres-bronce`) |
| `dw/rds-etl` | Escritura bronce/gold (`etl_writer`) |
| `dw/rds-api` | Lectura gold (`api_reader`, Lambda) |

Detalle del paquete ETL: [`apps/pipeline/README.md`](apps/pipeline/README.md).

---

# Cómo levantar el proyecto completo

Todo se corre desde la **raíz del repo**. Orden: emuladores → IaC → verificar → runtime (Airflow / API).

## 0. Prerequisitos

| Herramienta | Para qué | ¿Obligatorio? |
|-------------|----------|----------------|
| **Docker Desktop** (o Engine) + Compose v2 | Emuladores, Airflow, ALB, pgAdmin | Sí |
| Cuenta **LocalStack Hobby** + token | IAM / VPC / Lambda / Logs | Sí |
| **OpenTofu** (`tofu`) ≥ 1.6 | `cd infra && tofu apply` en el host | No, si usás la imagen toolbox |
| **Python** 3.11+ + `pip` | Demos ETL/Airflow y checks AWS CLI-like | Recomendado |
| **AWS CLI v2** (opcional) | `aws --endpoint-url …` de verificación | No |

**Puertos libres en el host**

| Puerto | Servicio |
|--------|----------|
| 4566 | LocalStack |
| 4567 | MiniStack (RDS + Secrets) |
| 9000 / 9001 | MinIO API / consola |
| 5432 / 5433 / 5434 | postgres-bronce / dw / erp |
| 15432 | Postgres real de MiniStack (RDS) |
| 8080 | Airflow UI |
| 8088 | ALB stand-in → Lambda |
| 5050 | pgAdmin |
| 6379 | Redis |

En Windows: Docker Desktop con WSL2 integration. Cloná el repo en una ruta corta (evitá OneDrive si el build de Airflow/logs falla por symlinks).

## 1. Token LocalStack y `.env`

1. Creá un token Hobby en [app.localstack.cloud](https://app.localstack.cloud).
2. En la raíz del repo:

```bash
# Linux / macOS / Git Bash
cp .env.example .env

# PowerShell
Copy-Item .env.example .env
```

3. Editá `.env` y seteá **obligatoriamente**:

```env
LOCALSTACK_AUTH_TOKEN=ls-...
```

Sin ese valor `docker compose up` falla (`LOCALSTACK_AUTH_TOKEN:?Set …`).  
El resto de variables tiene defaults locales (`test`/`test`, `minioadmin`, `postgres`/`postgres`).

## 2. Dependencias Python (host)

Hace falta si vas a correr demos (`ecs`) o `aws` via `awscli-local`.  
Si solo usás Compose + imagen toolbox, podés saltearlo.

```bash
python -m pip install -r requirements.txt
```

Opcional, solo ETL:

```bash
python -m pip install -r apps/pipeline/requirements.txt
```

Variables dummy para boto3 / AWS CLI en esta sesión:

```bash
# Linux / macOS
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1

# PowerShell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"
```

## 3. Levantar el runtime (Compose)

Un solo archivo: emuladores + Postgres + Airflow + ALB + pgAdmin.

```bash
docker compose up -d
docker compose ps
```

Esperá a que estén **healthy**:

- `localstack-integrador`
- `ministack-integrador`
- `s3-soporte`

Airflow (`airflow-init`) puede tardar la **primera vez** (descarga imagen + `db migrate` + usuario).  
Si `airflow-webserver` no arranca, mirá: `docker compose logs airflow-init`.

### UIs (con Compose up)

| URL | Usuario / clave | Qué es |
|-----|-----------------|--------|
| http://localhost:8080 | `admin` / `admin` | Airflow ≈ Fargate |
| http://localhost:8088/health | — | ALB stand-in (Lambda aún no hasta el paso 4) |
| http://localhost:5050 | `admin@example.com` / `admin` | pgAdmin |
| http://localhost:9001 | `minioadmin` / `minioadmin` | Consola MinIO (lake) |
| http://localhost:4566/_localstack/health | — | Health LocalStack |
| http://localhost:4567 | — | MiniStack (RDS API + Secrets) |

pgAdmin trae servers prearmados: bronce, dw (metastore Airflow), erp.  
RDS MiniStack (`host.docker.internal:15432`, user `dwadmin`) aparece después del `tofu apply`; la password es el secret `dw/rds-master` (no va en pgpass).

## 4. Aplicar la infraestructura (OpenTofu)

**Única fuente IaC:** carpeta [`infra/`](infra/).

Qué crea el apply (idempotente: el 2º run no debería recrear recursos):

1. IAM — roles (`app-role`, `api-role`, `ecsTaskExecutionRole`, `db-role`), grupos, users, policies  
2. VPC Multi-AZ + SGs + NAT (opcional) + endpoint S3 modelo  
3. Buckets lake en MinIO + versioning + policies  
4. CloudWatch log groups  
5. RDS `tp-dw-db` en MiniStack + secrets (`dw/rds-master`, `dw/rds-etl`, `dw/rds-api`, `dw/origen-demo`, `dw/erp`)  
6. Seed SQL (`data/rds/seed_tp.sql`) → schemas bronce/gold + roles `etl_writer` / `api_reader`  
7. Lambda `tp-gold-api`  
8. Marcadores ECS/EFS Hobby (`apps/airflow/.iac-managed`)  
9. Inventario FinOps local (Budget AWS solo si `create_budget=true`)

### Opción A — OpenTofu en el host

```bash
cd infra
tofu init
tofu plan          # revisar el diff
tofu apply         # confirmar con yes
tofu output
```

Para **dejar el log en `test/iac-runs/`** (también si falla):

```powershell
.\test\capture-apply.ps1                 # apply → test/iac-runs/<fecha>-apply-OK|FAIL/
.\test\capture-apply.ps1 -Action plan
```

Overrides locales (opcional):

```bash
cd infra
Copy-Item terraform.tfvars.example terraform.tfvars   # PowerShell
# cp terraform.tfvars.example terraform.tfvars
```

Defaults relevantes: `enable_ecs_api=false` (Hobby), `apply_rds_seed=true`, `create_budget=false`.

Si LocalStack/MiniStack aún no están healthy, el apply falla (timeouts RDS/IAM). Volvé al paso 3.

Si **ya existían** roles/buckets/RDS de corridas anteriores:

```bash
# Limpiá emuladores (CUIDADO: -v borra volúmenes) o destruí state viejo
docker compose down
# docker compose down -v    # reset total de datos
docker compose up -d
cd infra && tofu apply
```

### Opción B — Imagen toolbox (sin instalar `tofu`)

Detalle extra: [`docker/DOCKER.md`](docker/DOCKER.md).

```bash
# Build (una vez, o cuando cambie docker/Dockerfile / requirements.txt)
docker compose --profile iac build tp-iac

# Apply (espera health internos de Compose y corre tofu en /workspace/infra)
docker compose --profile iac run --rm tp-iac apply

# Plan / output / destroy
docker compose --profile iac run --rm tp-iac plan
docker compose --profile iac run --rm tp-iac tofu output
docker compose --profile iac run --rm tp-iac destroy
```

El state queda en el host: `infra/terraform.tfstate` (volumen bind). No lo commitees.

## 5. Verificar que la infra respondió (smoke test)

Correr **después** de `docker compose up -d` + `tofu apply`. No hace falta ETL.  
Evidencia smoke: [`test/2026-08-13-smoke/`](test/2026-08-13-smoke/).  
Errores de IaC: `.\test\capture-apply.ps1` → [`test/iac-runs/`](test/iac-runs/) (`*-FAIL/` + `tofu.log`). Smoke: `.\test\capture-smoke.ps1`.

Credenciales dummy de la sesión (PowerShell):

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Linux / macOS / Git Bash:

```bash
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
```

### 5.1 Contenedores Compose

```bash
docker compose ps
docker ps --filter name=ministack-rds --format "{{.Names}}  {{.Ports}}  {{.Status}}"
```

Esperado: `localstack-integrador`, `ministack-integrador`, `s3-soporte` **healthy**; Airflow `:8080`, ALB `:8088`, pgAdmin `:5050` **Up**.  
El Postgres de MiniStack (`ministack-rds-…-tp-dw-db`) publica un puerto en el host (a veces **15432**, a veces **15434**): anotalo para pgAdmin / `rds_port_override`.

### 5.2 Outputs OpenTofu

```bash
cd infra && tofu output
```

Esperado: `vpc_id`, `iam_roles` (`app-role`, `api-role`, `ecsTaskExecutionRole`, `db-role`), `lake_buckets`, `lambda_function = tp-gold-api`, `secret_names` (`dw/rds-master`, `dw/rds-etl`, `dw/rds-api`, `dw/erp`, `dw/origen-demo`), `ecs_mode = hobby-standin`.

### 5.3 IAM / lake / RDS / secrets / Lambda

```bash
# IAM (LocalStack :4566)
aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role --query Role.RoleName --output text
aws --endpoint-url http://localhost:4566 iam get-role --role-name api-role --query Role.RoleName --output text
aws --endpoint-url http://localhost:4566 iam get-role --role-name ecsTaskExecutionRole --query Role.RoleName --output text
aws --endpoint-url http://localhost:4566 iam get-group --group-name bi-ops --query Group.GroupName --output text

# Lake MinIO (:9000) — credenciales MINIO_ROOT_*, no test/test
AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin \
  aws --endpoint-url http://localhost:9000 s3 ls --region us-east-1

# RDS MiniStack (:4567)
aws --endpoint-url http://localhost:4567 rds describe-db-instances \
  --db-instance-identifier tp-dw-db \
  --query "DBInstances[0].{Id:DBInstanceIdentifier,Status:DBInstanceStatus,Endpoint:Endpoint}" \
  --output json

# Secrets
aws --endpoint-url http://localhost:4567 secretsmanager list-secrets \
  --query "SecretList[].Name" --output text

# Lambda
aws --endpoint-url http://localhost:4566 lambda get-function \
  --function-name tp-gold-api \
  --query "{Name:Configuration.FunctionName,Runtime:Configuration.Runtime,State:Configuration.State}" \
  --output json
```

PowerShell (MinIO):

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
aws --endpoint-url http://localhost:9000 s3 ls --region us-east-1
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
```

Esperado:

| Check | OK |
|-------|----|
| Roles / grupo | `app-role` `api-role` `ecsTaskExecutionRole` `bi-ops` |
| MinIO | `backup-data-lake` `snapshot-data-lake` `staging-data-lake` |
| RDS | `"Id": "tp-dw-db"`, `"Status": "available"` |
| Secrets | `dw/rds-master` `dw/rds-etl` `dw/rds-api` `dw/erp` `dw/origen-demo` |
| Lambda | `"Name": "tp-gold-api"`, `"State": "Active"` |

Si MinIO responde `InvalidAccessKeyId`, estás usando `test`/`test` en vez de `minioadmin`.

### 5.4 UIs / health HTTP (sin ETL)

```bash
# LocalStack
curl -s http://localhost:4566/_localstack/health

# ALB stand-in → Lambda (health no invoca SQL)
curl -s http://localhost:8088/health

# Airflow
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login/

# pgAdmin
curl -s http://localhost:5050/misc/ping
```

PowerShell:

```powershell
Invoke-RestMethod http://localhost:8088/health
(Invoke-WebRequest http://localhost:8080/health -UseBasicParsing).StatusCode
(Invoke-WebRequest http://localhost:8080/login/ -UseBasicParsing).StatusCode
(Invoke-WebRequest http://localhost:5050/misc/ping -UseBasicParsing).Content
(Invoke-WebRequest http://localhost:4566/_localstack/health -UseBasicParsing).StatusCode
```

Esperado: ALB `{"ok":true,"stand_in":"alb","target":"tp-gold-api"}`; Airflow/pgAdmin **200**; pgAdmin ping `PING`.  
Login UI: Airflow `admin`/`admin` · pgAdmin `admin@example.com`/`admin` · MinIO consola `:9001` `minioadmin`/`minioadmin`.

### 5.5 API gold (cableado ALB → Lambda)

Allowlist válida (no existe `hecho_ventas`): `dim_cliente`, `dim_producto`, `dim_fecha`, `dim_canal`, `dim_metodo_pago`, `dim_moneda`, `fact_venta_linea`, `fact_venta_devolucion`.

```bash
# Tabla inválida → 400 (la Lambda está en línea)
curl -s "http://localhost:8088/gold/query?table=hecho_ventas&limit=1"

# Tabla gold válida (sin ETL: vacío o error de driver, no 404 de función)
curl -s "http://localhost:8088/gold/query?table=dim_cliente&limit=2"
```

PowerShell:

```powershell
try { Invoke-RestMethod "http://localhost:8088/gold/query?table=hecho_ventas&limit=1" } catch { $_.ErrorDetails.Message }
try { Invoke-RestMethod "http://localhost:8088/gold/query?table=dim_cliente&limit=2" } catch { $_.ErrorDetails.Message }
```

Esperado **sin ETL**:

- `hecho_ventas` → 400 `Tabla no permitida en gold`
- `dim_cliente` → 200 con filas **o** 500 `No module named 'pg8000'` (zip Hobby lite; la función existe, falta el driver en el zip)

Si sale 502 / función inexistente: no corrió `tofu apply` o LocalStack se recreó sin re-apply.

### 5.6 Idempotencia

```bash
cd infra && tofu plan
```

Esperado: **0 to add, 0 to destroy**. Puede haber 4 `update in-place` cosméticos en descriptions de SG (LocalStack Hobby); no recrea VPC/IAM/RDS/Lambda.

## 6. Runtime: ETL + Airflow + API gold

Esquemas, tablas y DAGs: sección **[Datos: esquemas y procesamiento](#datos-esquemas-y-procesamiento)** arriba.

Compose **ya** tiene Airflow (`:8080`) y ALB stand-in (`:8088`). El IaC dejó roles, RDS, secrets y la Lambda.

### 6.1 Origen ERP + secret `dw/erp`

Con el stack ya arriba no hace falta un script demo:

- **Datos:** `postgres-erp` aplica `apps/pipeline/erp/seed_erp.sql` al crear el volumen.
- **Secret:** `tofu apply` crea `dw/erp` (host `postgres-erp`) en MiniStack.

Si el volumen ERP ya existía vacío, recrealo (`docker compose down` + borrar el volumen `postgres-data-erp`) o aplicá el seed a mano con `psql`.

### 6.2 Orquestación ≈ Fargate (DAGs en EFS stand-in)

Con la infra ya aplicada:

```bash
python labs/ecs/ecs.py --skip-infra           # camino A: conectividad → bronce
python labs/ecs/ecs.py --skip-infra --erp     # camino B: ERP → bronce → gold
```

UI Airflow: http://localhost:8080 (`admin` / `admin`).  
DAGs: `apps/airflow/dags/` · logs: `apps/airflow/logs/`.  
Orden camino B: `etl_erp_to_bronce` → `etl_bronce_to_gold`.

### 6.3 API gold (Qlik / Postman)

Health del stand-in:

```bash
curl http://localhost:8088/health
```

Query (después del seed + algún DAG gold; `table` de la allowlist, p. ej. `dim_cliente` / `fact_venta_linea`):

```bash
curl "http://localhost:8088/gold/query?table=dim_cliente&limit=20"
```

Invoke directo a LocalStack (sin ALB):

```bash
aws --endpoint-url http://localhost:4566 lambda invoke \
  --function-name tp-gold-api \
  --payload "{\"table\":\"dim_cliente\",\"limit\":10}" \
  out-gold.json
```

### 6.4 pgAdmin / SQL

1. http://localhost:5050 → `admin@example.com` / `admin`
2. Servers TP Integrador: bronce, dw, erp (password `postgres`)
3. RDS MiniStack: `host.docker.internal:15432`, DB `dw`, user `dwadmin`  
   Password = valor de `dw/rds-master` (MiniStack Secrets, consola o AWS CLI)

```bash
aws --endpoint-url http://localhost:4567 secretsmanager get-secret-value \
  --secret-id dw/rds-master --query SecretString --output text
```

### 6.5 FinOps (estimación local, no es API Budget)

```bash
python labs/finops/pricing.py --services services.json --budget 300
```

## 7. Cleanup

```bash
# Solo recursos declarados en OpenTofu
cd infra && tofu destroy
# o: docker compose --profile iac run --rm tp-iac destroy

# Emuladores (sin -v conserva volúmenes MinIO/Postgres/LocalStack)
docker compose down

# Reset total de datos locales
# docker compose down -v
```

No apliques IaC fuera de [`infra/`](infra/).

## Troubleshooting

| Síntoma | Qué hacer |
|---------|-----------|
| `LOCALSTACK_AUTH_TOKEN` missing | `.env` en la **raíz** con el token Hobby |
| LocalStack / MiniStack timeout | `docker compose ps` / `logs`; esperá **healthy** antes del apply |
| `BucketAlreadyExists` / role already exists | Restos de corridas anteriores. `tofu destroy` o `compose down -v` y apply limpio |
| `post_rds` no encuentra container RDS | MiniStack debe haber creado `tp-dw-db`; `docker ps --filter name=ministack-rds` |
| Airflow no muestra DAGs | Deben estar en `apps/airflow/dags/`; logs en `apps/airflow/logs/` |
| `InvalidAccessKeyId` en `s3 ls` | MinIO usa `minioadmin`/`minioadmin`, no `test`/`test` |
| ALB `:8088` 502 | Lambda aún no aplicada (`tofu apply`) o LocalStack no healthy |
| `gold/query` → `No module named 'pg8000'` | Zip Hobby lite; la Lambda está up. Falta el driver en el paquete |
| pgAdmin no conecta a RDS | Puerto host MiniStack (`docker ps --filter name=ministack-rds`); a veces 15434 ≠ 15432 |
| Plan con drifts eternos en SG refs | Ya mitigado en HCL (`ignore_changes`); re-aplicá una vez |
| Symlinks Airflow / Docker build en Windows | No copies `apps/airflow/logs` al build; Compose los monta |
