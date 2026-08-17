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
IaC (módulos): [`infra/modules/README.md`](infra/modules/README.md).

## Estructura

```
.
├── compose.yaml               # runtime local (un solo up -d)
├── docker/                    # imagen toolbox OpenTofu (tp-integrador-iac)
├── infra/                     # única fuente IaC (tofu apply)
│   ├── modules/               # iam, vpc, s3, rds, secrets, lambda, ecs, …
│   └── scripts/post_rds.py    # seed RDS post-apply
├── apps/
│   ├── pipeline/              # ETL Python + tests + flake8/pytest
│   ├── api/                   # Lambda + vendor/pg8000 + ALB stand-in
│   └── airflow/               # DAGs + logs (≈ EFS)
├── labs/ecs/ecs.py            # opcional: automatiza Compose + trigger DAGs
├── scripts/                   # cleanup-hobby, sync-rds-port
├── data/rds/                  # seed_tp.sql
├── ops/                       # pgAdmin
└── test/                      # evidencia smoke / IaC
```

## Datos: esquemas y procesamiento

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

Todo se corre desde la **raíz del repo**. Orden obligatorio:

```text
0–2  Prereqs + .env + (opcional) pip
  3  docker compose up -d          ← emuladores + Airflow + ALB + ERP
  4  tofu apply                    ← IAM/VPC/RDS/secrets/Lambda/seed
 4b  sync-rds-port                 ← alinea puerto MiniStack en .env + Lambda
  5  smoke (opcional)
  6  DAGs camino B                 ← pipeline ERP → bronce → gold
  7  Postman / curl                ← GET /gold/query
  9  cleanup-hobby (bajar todo)    ← destroy + wipe volúmenes emuladores
```

**Arranque limpio (después de cleanup o primera vez):**

```powershell
# Windows — desde la raíz del repo
Remove-Item Env:LOCALSTACK_AUTH_TOKEN -ErrorAction SilentlyContinue   # evita token corto del shell
docker compose up -d
docker compose --profile iac run --rm tp-iac apply
.\scripts\sync-rds-port.ps1 -RecreateAirflow
docker compose --profile iac run --rm tp-iac apply   # solo si sync cambió el puerto
# luego paso 6 (DAGs) y paso 7 (API)
```

```bash
# Linux / macOS / Git Bash
unset LOCALSTACK_AUTH_TOKEN
docker compose up -d
docker compose --profile iac run --rm tp-iac apply
./scripts/sync-rds-port.sh --recreate-airflow
docker compose --profile iac run --rm tp-iac apply   # solo si sync cambió el puerto
```

`labs/ecs/ecs.py` es un **atajo** del paso 6 (levanta/triggerea Airflow).  
Infra = solo `tofu apply`. Pipeline = DAGs. API = ALB `:8088` → Lambda.  
Empaquetar / correr sin instalar `tofu` en el host: **§8** (imagen `tp-integrador-iac`).

## 0. Prerequisitos

| Herramienta | Para qué | ¿Obligatorio? |
|-------------|----------|----------------|
| **Docker Desktop** (o Engine) + Compose v2 | Emuladores, Airflow, ALB, pgAdmin | Sí |
| Cuenta **LocalStack Hobby** + token | IAM / VPC / Lambda / Logs | Sí |
| **OpenTofu** (`tofu`) ≥ 1.6 | `cd infra && tofu apply` en el host | No, si usás la imagen toolbox |
| **Python** 3.11+ + `pip` | `labs/ecs/ecs.py`, smoke/checks y AWS CLI-like | Recomendado (no si solo Compose + toolbox) |
| **AWS CLI v2** (opcional) | `aws --endpoint-url …` de verificación | No |

**Puertos libres en el host**

| Puerto | Servicio |
|--------|----------|
| 4566 | LocalStack |
| 4567 | MiniStack (RDS + Secrets) |
| 9000 / 9001 | MinIO API / consola |
| 5432 / 5433 / 5434 | postgres-bronce / dw / erp |
| 15432–15434 | Postgres real de MiniStack (RDS; puerto dinámico) |
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

**Windows:** si tenés `LOCALSTACK_AUTH_TOKEN` exportado en el shell (token corto viejo), borralo antes del `compose up` para que Compose use solo `.env`:

```powershell
Remove-Item Env:LOCALSTACK_AUTH_TOKEN -ErrorAction SilentlyContinue
```

`RDS_PORT_OVERRIDE` en `.env` se sincroniza automáticamente en el **paso 4b** (`scripts/sync-rds-port.*`); no hace falta editarlo a mano salvo diagnóstico.

## 2. Dependencias Python (host)

Hace falta si vas a correr `labs/ecs/ecs.py` o checks con `aws`/`awscli-local`.  
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
RDS MiniStack (`host.docker.internal`, user `dwadmin`) aparece después del `tofu apply`; el **puerto host** lo asigna MiniStack (suele ser `15432`, a veces `15433`/`15434`) — ver **paso 4b**. La password es el secret `dw/rds-master` (no va en pgpass).

## 4. Aplicar la infraestructura (OpenTofu)

**Única fuente IaC:** carpeta [`infra/`](infra/).

Qué crea el apply (idempotente: el 2º run no debería recrear recursos):

1. IAM — roles (`app-role`, `api-role`, `ecsTaskExecutionRole`, `db-role`), grupos, users, policies  
2. VPC Multi-AZ + SGs + NAT (opcional) + endpoint S3 modelo  
3. Buckets lake en MinIO + versioning + policies  
4. CloudWatch log groups  
5. RDS `tp-dw-db` en MiniStack + secrets (`dw/rds-master`, `dw/rds-etl`, `dw/rds-api`, `dw/origen-demo`, `dw/erp`)  
6. Seed SQL (`data/rds/seed_tp.sql`) → schemas bronce/gold + roles `etl_writer` / `api_reader`  
7. Lambda `tp-gold-api` (zip: handler + query_gold + `apps/api/vendor/` con pg8000)  
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

Si **ya existían** roles/buckets/RDS de corridas anteriores, usá el script de cleanup (§9) en lugar de un `down` a medias:

```powershell
.\scripts\cleanup-hobby.ps1 -Yes
# luego pasos 3 → 4 → 4b
```

### Opción B — Imagen toolbox (sin instalar `tofu`)

Detalle extra: [`docker/DOCKER.md`](docker/DOCKER.md).

```bash
# Build (una vez, o cuando cambie docker/Dockerfile / requirements.txt)
docker compose --profile iac build tp-iac

# Apply (espera health internos de Compose y corre tofu en /workspace/infra)
docker compose --profile iac run --rm tp-iac apply

# Plan / output / destroy / shell
docker compose --profile iac run --rm tp-iac plan
docker compose --profile iac run --rm tp-iac tofu output
docker compose --profile iac run --rm tp-iac destroy
docker compose --profile iac run --rm tp-iac shell
```

El state queda en el host: `infra/terraform.tfstate` (volumen bind). No lo commitees.

Detalle de empaquetado y arranque: **§8** y [`docker/DOCKER.md`](docker/DOCKER.md).

## 4b. Sincronizar puerto RDS (MiniStack)

**Obligatorio** después del primer `tofu apply` (y tras cada cleanup/re-apply).  
MiniStack levanta un sidecar `ministack-rds-*-tp-dw-db` con un **puerto host dinámico**. Airflow (ETL) y Lambda (API) deben apuntar al mismo puerto vía `RDS_PORT_OVERRIDE` / `rds_port_override`.

```powershell
# Windows
.\scripts\sync-rds-port.ps1 -RecreateAirflow
```

```bash
# Linux / macOS / Git Bash
chmod +x scripts/sync-rds-port.sh   # una vez
./scripts/sync-rds-port.sh --recreate-airflow
```

Qué hace el script:

1. Lee el puerto de `docker ps --filter name=ministack-rds`
2. Escribe `RDS_PORT_OVERRIDE` en `.env`
3. Escribe `rds_port_override` en `infra/terraform.tfvars`
4. Con `-RecreateAirflow` / `--recreate-airflow`: recrea scheduler + webserver de Airflow

Si el puerto **cambió** respecto al apply anterior, re-aplicá la Lambda:

```bash
docker compose --profile iac run --rm tp-iac apply
# o: cd infra && tofu apply
```

**Síntoma si omitís este paso:** DAGs fallan al conectar a RDS; `GET /gold/query` responde error de conexión a `host.docker.internal:15433` (u otro puerto viejo) aunque `/health` siga en 200.

Verificación manual (opcional):

```bash
docker ps --filter name=ministack-rds --format "{{.Names}}  {{.Ports}}"
grep RDS_PORT_OVERRIDE .env
grep rds_port_override infra/terraform.tfvars
```

## 5. Verificar que la infra respondió (smoke test)

Correr **después** de `docker compose up -d` + `tofu apply` + **paso 4b**. No hace falta ETL.  
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
El sidecar `ministack-rds-…-tp-dw-db` debe estar **Up** con un puerto tipo `0.0.0.0:15432->5432/tcp`. Ese número debe coincidir con `.env` y `terraform.tfvars` (paso **4b**).

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

Esperado **sin ETL** (solo cableado):

- `hecho_ventas` → 400 `Tabla no permitida en gold`
- `dim_cliente` → 200 con `row_count: 0` (o filas si ya corriste el pipeline)

Con pipeline (paso 6) → `dim_cliente` / `fact_venta_linea` con filas > 0.

### 5.6 Idempotencia

```bash
cd infra && tofu plan
```

Esperado: **0 to add, 0 to destroy**. Puede haber `update in-place` cosméticos en descriptions de SG (LocalStack Hobby); no recrea VPC/IAM/RDS/Lambda. El inventario FinOps (`local_file.finops_inventory`) queda estable tras apply (ruta `generated/` + content tipado).

## 6. Ejecutar el pipeline (ERP → bronce → gold)

Prerrequisitos: pasos **3** (Compose healthy) + **4** (`tofu apply` OK) + **4b** (`sync-rds-port`).

### 6.1 Qué debe existir ya

| Pieza | Quién la creó |
|-------|----------------|
| `postgres-erp` con Clientes/Productos/Ventas | Compose + `apps/pipeline/erp/seed_erp.sql` (initdb) |
| Secret `dw/erp` | `tofu apply` → `modules/secrets` |
| Secret `dw/rds-etl` + schemas bronce/gold | `tofu apply` + `post_rds.py` / `seed_tp.sql` |
| Airflow UI `:8080` | Compose (`admin` / `admin`) |
| DAGs en `apps/airflow/dags/` | montados en el contenedor |

Si el volumen ERP nació vacío (sin seed), recrealo:

```powershell
docker compose stop postgres-erp
docker volume rm cloud-foundations-tp-integrador_postgres-data-erp
# el nombre exacto: docker volume ls | findstr erp
docker compose up -d postgres-erp
```

### 6.2 Opción A — UI Airflow (recomendado para entender el flujo)

1. Abrí http://localhost:8080 → login `admin` / `admin`.
2. Activá (toggle) los DAGs:
   - `etl_erp_to_bronce`
   - `etl_bronce_to_gold`
3. En **`etl_erp_to_bronce`** → Trigger DAG (play). Esperá estado **success**.
   - Tasks: `ensure_bronce_ddl` → `extract_erp` → `transform_normalize` → `load_bronce`
4. En **`etl_bronce_to_gold`** → Trigger. Esperá **success**.
   - Tasks: `extract_bronce` → `transform_to_gold` → `load_gold`
5. (Opcional) Camino A de conectividad: trigger `etl_rds_comprobation`.

Logs: UI Airflow o `apps/airflow/logs/`.

### 6.3 Opción B — atajo `ecs.py` (opcional)

Automatiza Compose Airflow + triggers (no reemplaza `tofu apply`):

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

python labs/ecs/ecs.py --skip-infra --erp
```

- `--skip-infra` → asume IaC ya aplicada  
- `--erp` → camino B (ambos DAGs)  
- sin `--erp` → solo camino A (`etl_rds_comprobation`)

### 6.4 Verificar datos en gold (SQL / pgAdmin)

http://localhost:5050 → `admin@example.com` / `admin`.

RDS MiniStack: host `host.docker.internal`, puerto = el de `docker ps --filter name=ministack-rds` (debe coincidir con el paso **4b**), DB `dw`, user `dwadmin`.  
Password = JSON de `dw/rds-master`:

```powershell
aws --endpoint-url http://localhost:4567 secretsmanager get-secret-value `
  --secret-id dw/rds-master --query SecretString --output text
```

Ejemplo:

```sql
SELECT count(*) FROM gold.dim_cliente;
SELECT count(*) FROM gold.fact_venta_linea;
```

### 6.5 FinOps (opcional)

```bash
python labs/finops/pricing.py --services services.json --budget 300
```

## 7. Llamar a la API gold (Postman / curl)

Tras el **paso 6** (gold con filas). Cableado: Postman → ALB stand-in `:8088` → Lambda `tp-gold-api` → RDS (`api_reader`).

### 7.1 Health (sin SQL)

| | |
|--|--|
| Method | `GET` |
| URL | `http://localhost:8088/health` |

Esperado: `{"ok":true,"stand_in":"alb","target":"tp-gold-api"}`.

### 7.2 Query gold — Postman

1. Abrí Postman → **New** → **HTTP Request** (o Collection → Add request).
2. Method: **GET** (no POST; el body no se usa).
3. Auth: **No Auth**. Headers: ninguno obligatorio.
4. URL base: `http://localhost:8088/gold/query`
5. Pestaña **Params** (Query Params):

| Key | Value | Notas |
|-----|-------|--------|
| `table` | `dim_cliente` | **Obligatorio.** Solo allowlist gold (no `bronce.*`, no `hecho_ventas`) |
| `limit` | `20` | Opcional; default bajo, máx. **500** |
| `columns` | `cliente_sk,nombre` | Opcional (`*` o vacío = todas) |
| `condition` | `pais=Argentina` | Opcional: `col=valor`, `col!=valor`, `col>valor`, `col LIKE valor` |

6. **Send**.

Esperado tras el paso 6:

- Status **200**
- Body JSON con `ok: true`, `table`, `row_count` (> 0), `sql_preview`, `rows` (array)

Ejemplos de URL listos para pegar en Postman:

```text
http://localhost:8088/gold/query?table=dim_cliente&limit=20
http://localhost:8088/gold/query?table=fact_venta_linea&limit=50
http://localhost:8088/gold/query?table=dim_producto&columns=producto_sk,nombre,marca&limit=10
http://localhost:8088/gold/query?table=dim_cliente&condition=pais=Argentina&limit=20
```

Allowlist: `dim_fecha`, `dim_cliente`, `dim_producto`, `dim_canal`, `dim_metodo_pago`, `dim_moneda`, `fact_venta_linea`, `fact_venta_devolucion`.

### 7.3 curl / PowerShell (pruebas validadas)

Mismas llamadas que en Postman; útiles para smoke rápido tras el paso 6:

```bash
curl -s http://localhost:8088/health

curl -s "http://localhost:8088/gold/query?table=dim_cliente&limit=20"

curl -s "http://localhost:8088/gold/query?table=fact_venta_linea&limit=10"

curl -s "http://localhost:8088/gold/query?table=dim_producto&limit=10"
```

Esperado: health con `"ok":true`; queries con `"ok":true` y `row_count` > 0.

PowerShell:

```powershell
Invoke-RestMethod http://localhost:8088/health
Invoke-RestMethod "http://localhost:8088/gold/query?table=dim_cliente&limit=20"
Invoke-RestMethod "http://localhost:8088/gold/query?table=fact_venta_linea&limit=10"
Invoke-RestMethod "http://localhost:8088/gold/query?table=dim_producto&limit=10"
```

Invoke directo a LocalStack (sin ALB):

```bash
aws --endpoint-url http://localhost:4566 lambda invoke \
  --function-name tp-gold-api \
  --cli-binary-format raw-in-base64-out \
  --payload "{\"table\":\"dim_cliente\",\"limit\":10}" \
  out-gold.json
```

### 7.4 Errores frecuentes API

| Respuesta | Causa |
|-----------|--------|
| 502 | Lambda no aplicada o LocalStack caído → `tofu apply` |
| 400 `Tabla no permitida` | Nombre fuera de allowlist |
| 500 `No module named 'pg8000'` | Zip sin `apps/api/vendor/` → re-apply tras vendor |
| 200 `row_count: 0` | Pipeline no corrió o gold vacío → paso 6 |
| 500 connection / `InterfaceError` puerto | Omitiste paso **4b** o Lambda con puerto viejo → `sync-rds-port` + `tofu apply` |

## 8. Empaquetar el proyecto en Docker y levantarlo

Hay **dos** capas Docker:

| Capa | Qué es | Cómo |
|------|--------|------|
| **Runtime Hobby** | Emuladores + Airflow + ALB + ERP + pgAdmin | `docker compose up -d` (obligatorio) |
| **Toolbox IaC** | Imagen con OpenTofu + código para `apply` sin instalar `tofu` | build + `docker compose --profile iac run …` (opcional) |

Guía ampliada: [`docker/DOCKER.md`](docker/DOCKER.md).

### 8.1 Empaquetar la imagen toolbox (build)

Desde la **raíz del repo** (context `.`, Dockerfile en `docker/`):

```powershell
# .env hace falta para el runtime Compose, no para el build en sí
Copy-Item .env.example .env   # si aún no existe; editá LOCALSTACK_AUTH_TOKEN

# Opción A — Compose (recomendado; profile iac: tp-iac no arranca con up -d)
docker compose --profile iac build tp-iac

# Opción B — build directo
docker build -f docker/Dockerfile -t tp-integrador-iac:latest .
```

Qué **incluye** la imagen: OpenTofu, AWS CLI, Python, `infra/`, `data/rds/`, `apps/` (API + `vendor/pg8000`, pipeline, DAGs), scripts (`post_rds`).  
Qué **no** incluye: `.tfstate`, `.env`, secretos (se montan o inyectan en runtime).

Verificación:

```powershell
docker run --rm tp-integrador-iac:latest help
docker run --rm --entrypoint tofu tp-integrador-iac:latest version
```

Rebuild cuando cambies `docker/Dockerfile`, `requirements.txt` o archivos que el build copia. Los `.tf` montados desde `./infra` se ven sin rebuild.

### 8.2 Levantar la imagen / stack y aplicar IaC

```powershell
# 1) Runtime Hobby (emuladores + Airflow + ALB + …)
docker compose up -d
docker compose ps
# Esperá healthy: localstack-integrador, ministack-integrador, s3-soporte

# 2) Apply con la imagen toolbox (state en el host: infra/terraform.tfstate)
docker compose --profile iac run --rm tp-iac apply

# 3) Puerto RDS dinámico → .env + Airflow + (si cambió) Lambda
.\scripts\sync-rds-port.ps1 -RecreateAirflow
docker compose --profile iac run --rm tp-iac apply   # solo si sync cambió el puerto

# Otras acciones del entrypoint
docker compose --profile iac run --rm tp-iac plan
docker compose --profile iac run --rm tp-iac tofu output
docker compose --profile iac run --rm tp-iac destroy
docker compose --profile iac run --rm tp-iac shell   # bash interactivo
```

Después: **paso 6** (DAGs) y **paso 7** (Postman), igual que con `tofu` en el host.

### 8.3 Solo runtime Compose (sin toolbox)

Si ya tenés OpenTofu en el host:

```powershell
docker compose up -d
cd infra; tofu init; tofu apply
.\scripts\sync-rds-port.ps1 -RecreateAirflow
cd ..; docker compose --profile iac run --rm tp-iac apply   # o tofu apply en host, si cambió puerto
```

La imagen toolbox es **opcional**; `docker compose up -d` (paso 3) **sí** es obligatorio para Hobby.

## 9. Cleanup

`tofu destroy` solo saca recursos del state/API. En Hobby **persisten** volúmenes Docker
(LocalStack, MiniStack, MinIO, disco de la RDS `ministack-rds-*`). Si no los borrás,
la próxima corrida choca con secrets soft-deleted, roles/buckets huérfanos o schema RDS viejo.

### 9.1 Script recomendado (destroy + wipe emuladores)

Desde la **raíz del repo**:

```powershell
# Windows
.\scripts\cleanup-hobby.ps1 -Yes

# Solo Docker/volúmenes (sin tofu destroy)
.\scripts\cleanup-hobby.ps1 -SkipDestroy -Yes

# También borra postgres ERP/Airflow metastore, redis, pgAdmin
.\scripts\cleanup-hobby.ps1 -Full -Yes
```

```bash
# Linux / macOS / Git Bash
chmod +x scripts/cleanup-hobby.sh   # una vez
./scripts/cleanup-hobby.sh --yes
./scripts/cleanup-hobby.sh --skip-destroy --yes
./scripts/cleanup-hobby.sh --full --yes
```

Qué hace el script:

1. `tofu destroy` (imagen `tp-iac` si existe, si no `tofu` en el host)
2. `docker compose down --remove-orphans`
3. Elimina sidecars `ministack-rds-*`
4. Borra volúmenes `localstack-data`, `ministack-data`, `minio-data` y `ministack-rds-*-data`
5. Con `-Full` / `--full`: también `postgres-*`, `redis-data`, `pgadmin-data`

No borra `.env` ni el archivo de state a mano (el destroy ya lo deja vacío/consistente).

Después, arranque limpio:

```powershell
docker compose up -d
docker compose --profile iac run --rm tp-iac apply
.\scripts\sync-rds-port.ps1 -RecreateAirflow
docker compose --profile iac run --rm tp-iac apply   # si sync cambió el puerto
```

(pasos **3**, **4**, **4b** del checklist principal).

### 9.2 Manual (equivalente corto)

```bash
# Solo recursos OpenTofu
cd infra && tofu destroy
# o: docker compose --profile iac run --rm tp-iac destroy

# Emuladores (sin -v conserva volúmenes → riesgo de ghosts)
docker compose down

# Reset total de datos Compose (incluye ERP seed, Airflow DB, etc.)
# docker compose down -v
```

Además, los secrets IaC usan `recovery_window_in_days = 0` (Hobby) para que un destroy no deje nombres reservados 30 días.

No apliques IaC fuera de [`infra/`](infra/).

## Troubleshooting

| Síntoma | Qué hacer |
|---------|-----------|
| `LOCALSTACK_AUTH_TOKEN` missing | `.env` en la **raíz** con el token Hobby |
| LocalStack exit 55 / token inválido | `Remove-Item Env:LOCALSTACK_AUTH_TOKEN` (Windows) y usá solo `.env` |
| LocalStack / MiniStack timeout | `docker compose ps` / `logs`; esperá **healthy** antes del apply |
| `BucketAlreadyExists` / role already exists | Restos de corridas. `.\scripts\cleanup-hobby.ps1 -Yes` (o `--yes`) y apply limpio |
| Secretos `ResourceExistsException` (lista vacía) | Ghosts soft-delete MiniStack → cleanup-hobby (wipe `ministack-data`) |
| Schema RDS viejo / falta columna `pais` | Volumen `ministack-rds-*-data` stale → cleanup-hobby y re-apply |
| `post_rds` no encuentra container RDS | MiniStack debe haber creado `tp-dw-db`; `docker ps --filter name=ministack-rds` |
| DAGs fallan conexión RDS / API puerto incorrecto | Paso **4b**: `.\scripts\sync-rds-port.ps1 -RecreateAirflow` + `tofu apply` |
| Airflow no muestra DAGs | Deben estar en `apps/airflow/dags/`; logs en `apps/airflow/logs/` |
| `InvalidAccessKeyId` en `s3 ls` | MinIO usa `minioadmin`/`minioadmin`, no `test`/`test` |
| ALB `:8088` 502 | Lambda aún no aplicada (`tofu apply`) o LocalStack no healthy |
| `gold/query` → `No module named 'pg8000'` | Zip debe incluir `apps/api/vendor/`. Rebuild vendor + `tofu apply` |
| `gold/query` row_count 0 | Corré camino B (paso 6) antes de Postman |
| pgAdmin no conecta a RDS | Mismo puerto que paso **4b**; host `host.docker.internal` |
| `tofu apply` falla en Windows/OneDrive | Usá toolbox: `docker compose --profile iac run --rm tp-iac apply` |
| Plan con drifts eternos en SG refs | Ya mitigado en HCL (`ignore_changes`); re-aplicá una vez |
| Symlinks Airflow / Docker build en Windows | No copies `apps/airflow/logs` al build; Compose los monta |
| Tests pipeline | `pip install -r apps/pipeline/requirements-dev.txt` · `pytest -c apps/pipeline/pytest.ini --rootdir=apps/pipeline` |
