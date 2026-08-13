# Lab 09b TP — Cómputo ETL (stand-in Fargate + EFS + Airflow)

<!--
  Este lab = ECOSISTEMA DE CÓMPUTO del to-be (Airflow en Fargate + EFS).
  LocalStack Hobby NO tiene APIs ecs/efs → usamos Docker Compose + efs-standin.

  Lectura recomendada:
    1) Este archivo (qué / por qué de cada paso)
    2) ecs/ecs_demo.py        → automatiza el camino “demo conectividad” (pasos 0–4)
    3) ecs/IAM-NOTES.md       → execution role vs task role
    4) etl/lab-extra-tp.md    → ORIGEN ERP + código extract/transform/load
    5) docs/Infra + Solution §4–5

  Frontera con lab-extra:
    lab-extra  = origen postgres-erp + secret dw/erp + paquete etl/
    lab-09b    = IAM, EFS stand-in, Airflow, DDL bronce.erp_*, DAGs → bronce/gold
-->

## Qué implementa (y qué NO)

Implementa en **LocalStack Hobby** la capa de cómputo del to-be de:

| Documento | Qué fija |
|---|---|
| [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md) | App privada = Airflow + storage compartido DAGs/logs; datos = RDS |
| [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §4–5 | ETL grupo 1 → **Bronce**; grupo 2 → **Gold**; EFS; Secrets + IAM |

> **Alcance Hobby**  
> No hay `create-cluster` / `create-file-system` (licencia Pro). Equivalencias:
>
> | To-be AWS | Hobby (este lab) | Por qué |
> |---|---|---|
> | ECS Fargate (Airflow) | `docker-compose.airflow.yaml` | Mismo proceso; sin API ECS |
> | EFS (DAGs + logs) | `ecs/efs-standin/` | Árbol compartido entre webserver/scheduler |
> | Task / execution role | IAM LocalStack | Modelo least-privilege; Compose usa keys `test` |
> | RDS bronce/gold | MiniStack `tp-dw-db` + `dw/rds-etl` | Lab 08-tp |

Arco: **IAM (04) → VPC (07-v2) → RDS (08-tp) → cómputo (09b)**.  
Origen ERP rico: **[`../etl/lab-extra-tp.md`](../etl/lab-extra-tp.md)** (prerequisito de los Pasos 5–7).

### Dos caminos en este lab

| Camino | Objetivo | Pasos |
|---|---|---|
| **A — Demo conectividad** | Probar secrets + INSERT mínimo en bronce | 1–4 (`ecs_demo.py`, DAG `etl_bronce_origen_demo`) |
| **B — ETL real ERP** | Landing estructurado + carga dimensional | 5–7 (DAGs `etl_erp_to_bronce`, `etl_bronce_to_gold`) |

```text
                    ┌─ Stand-in ≈ Fargate + EFS (ESTE LAB) ─────────────┐
  origen-demo  ───►│  Airflow + efs-standin/dags                        │──► bronce.raw_record
  (camino A)       │                                                    │
                   │                                                    │
  postgres-erp ───►│  + paquete etl/ montado (PYTHONPATH)               │──► bronce.erp_*
  (lab-extra)      │  DAG etl_erp_to_bronce  (camino B grupo 1)         │
                   │  DAG etl_bronce_to_gold (camino B grupo 2)         │──► gold.dim_* / fact_*
                   └────────────────────────────────────────────────────┘
                         ▲ IAM modelo · Secrets MiniStack
```

---

## Cómo ejecutarlo

### Opción A — Script (recomendado)

```powershell
# Prereqs: docker compose base up + labs 04, 07-v2, 08-tp
# Camino B además: python etl/etl_demo.py
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

python ecs/ecs_demo.py           # camino A (demo conectividad)
python ecs/ecs_demo.py --erp     # camino A + B (ERP→bronce→gold vía EFS)
# Flags:
#   python ecs/ecs_demo.py --skip-infra     # tras tofu apply en ecs/iac
#   python ecs/ecs_demo.py --skip-runtime
#   python ecs/ecs_demo.py --cleanup
```

`ecs_demo.py` automatiza IAM, EFS stand-in, Compose, triggers y (con `--erp`) los DAGs del camino B.

**Alternativa OpenTofu** (modelo IAM + stand-in + secret; runtime en Python):

| Capa | Herramienta |
|---|---|
| Infra (pasos 1–2 + secret origen) | `cd ecs/iac && tofu apply` |
| Runtime (Compose / DAG / verify / `--erp`) | `python ecs/ecs_demo.py --skip-infra` |

Detalle en `ecs/iac/README.md`. No mezcles IAM Python y OpenTofu sin limpiar.

### Opción B — Manual + camino ERP

Seguí los pasos numerados abajo. Para Pasos 5–7 completá antes el lab-extra (ERP + `dw/erp`).

---

## Prerequisitos

```powershell
docker compose up -d localstack-integrador ministack-integrador s3-soporte redis postgres-bronce postgres-dw

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

# Lab 04 — sin app-role no hay dónde colgar InlineEtlSecrets
awslocal iam get-role --role-name app-role --query "Role.Arn" --output text

# Lab 07-v2 — diseño de red (filtros entrecomillados en PowerShell)
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc" --query "Vpcs[0].VpcId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-ecs-etl" --query "SecurityGroups[0].GroupId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" --query "SecurityGroups[0].GroupId" --output text

# Lab 08-tp — destino de los DAGs
curl.exe -s http://localhost:4567/_ministack/health
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret --secret-id dw/rds-etl --query "Name" --output text

# Lab-extra (solo si vas al camino B / Pasos 5–7)
docker exec postgres-erp pg_isready -U postgres -d erp
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret --secret-id dw/erp --query "Name" --output text
```

### Endpoints (no mezclar)

| Servicio | URL | Uso |
|---|---|---|
| LocalStack | `:4566` | IAM + VPC |
| MiniStack | `:4567` host / `:4566` en Docker | Secrets + RDS lógica |
| postgres-bronce | `:5432` | Origen demo (camino A) |
| postgres-erp | `:5434` host / `:5432` en Docker | Origen ERP (camino B; lab-extra) |
| RDS MiniStack | `:15432` | Destino bronce/gold |

> MiniStack `4567:4566`: host → `:4567`; contenedores → `ministack-integrador:4566`.

---

## Paso 1 — IAM: execution role + task role (Hobby ✅)

<!--
  En Fargate SIEMPRE hay dos roles:
  - Execution = agente ECS al boot (ECR, awslogs)
  - Task     = tu código en runtime (Secrets, S3)
  Mezclarlos es el error más común de least-privilege.
-->

**Qué hace:** crea/actualiza `ecsTaskExecutionRole` y amplía `app-role` con `InlineEtlSecrets`.  
**Para qué:** documentar el privilegio mínimo del to-be Fargate.  
**Por qué aunque Compose use `test/test`:** LocalStack no inyecta roles en Docker; el modelo queda alineado a `docs/` y reusable en AWS real.

```text
Agente (boot) → ecsTaskExecutionRole   |  Contenedor (ETL) → app-role
  pull imagen, awslogs                   |    Secrets ETL/orígenes, S3 staging
```

Detalle: [`IAM-NOTES.md`](./IAM-NOTES.md). Script: `ecs_demo.py` → `step_iam()`.

### 1.1 Execution role

```powershell
# Trust: solo ecs-tasks.amazonaws.com (trust_ecs.json)
awslocal iam create-role `
  --role-name ecsTaskExecutionRole `
  --assume-role-policy-document file://ecs/trust_ecs.json 2>$null

# Solo ECR + Logs — NO Secrets de negocio
awslocal iam put-role-policy `
  --role-name ecsTaskExecutionRole `
  --policy-name InlineEcsExecution `
  --policy-document file://ecs/execution_policy.json

awslocal iam get-role --role-name ecsTaskExecutionRole --query "Role.Arn" --output text
```

### 1.2 Task role — Secrets en `app-role`

```powershell
# Amplía lab 04: GetSecretValue sobre dw/rds-etl*, dw/origen*, dw/erp*, …
awslocal iam put-role-policy `
  --role-name app-role `
  --policy-name InlineEtlSecrets `
  --policy-document file://ecs/task_secrets_policy.json

awslocal iam list-role-policies --role-name app-role
# Esperado: InlineS3Read + InlineEtlSecrets
```

| | 1.1 Execution | 1.2 Task (`app-role`) |
|---|---|---|
| Momento (AWS) | Boot | Runtime DAG |
| ECR / awslogs | Sí | No |
| Secrets origen / ETL | No | Sí |
| S3 staging | No | Sí (lab 04) |

---

## Paso 2 — “EFS” local: DAGs + logs compartidos (Hobby ✅)

<!--
  Sin EFS (o stand-in), cada task tendría filesystem efímero y no compartirían DAGs/logs.
  Access point to-be = subpath (/airflow/dags, /airflow/logs) con uid airflow.

  REGLA DEL LAB: todo DAG nuevo de Airflow (demo, ERP→bronce, bronce→gold)
  se agrega SOLO bajo ecs/efs-standin/dags/. Eso ES el EFS del TP.
-->

**Qué hace:** asegura `efs-standin/{dags,logs}` y muestra `sg-efs` del diseño 07-v2.  
**Para qué:** scheduler y webserver ven el mismo árbol de DAGs (contrato EFS).  
**Por qué no guarda el DW:** EFS es orquestación; los datos van a RDS.

```powershell
# SG del diseño 07-v2 (en AWS abriría NFS :2049 desde sg-ecs-etl)
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" `
  --query "SecurityGroups[0].{Id:GroupId,Name:GroupName}" --output table

New-Item -ItemType Directory -Force -Path ecs\efs-standin\dags, ecs\efs-standin\logs | Out-Null

# Inventario del “access point” /airflow/dags — los TRES DAGs del lab deben estar acá
Get-ChildItem ecs\efs-standin\dags -Filter "*.py" | Select-Object Name
# Esperado:
#   etl_bronce_origen_demo.py   (camino A)
#   etl_erp_to_bronce.py        (camino B grupo 1)  ← mismo EFS, no otra carpeta
#   etl_bronce_to_gold.py       (camino B grupo 2)  ← mismo EFS

# Inventario stand-in vs to-be (incluye lista de DAGs)
Get-Content ecs\efs_config.json
```

| AWS (to-be) | Hobby (obligatorio en este lab) |
|---|---|
| EFS + access point `/airflow/dags` | `ecs/efs-standin/dags/*.py` |
| EFS + access point `/airflow/logs` | `ecs/efs-standin/logs/` |
| Mount en cada task Fargate | Bind mounts del compose (`./efs-standin/...`) |
| `sg-efs` :2049 | Documentado; runtime = red Docker |

**Contrato:** si un DAG no está en `efs-standin/dags`, **no forma parte del lab 09b** (Airflow no lo ve). El paquete `etl/` (PYTHONPATH) es librería; **no** sustituye al EFS de DAGs/logs.

Automatizado en `ecs_demo.py` → `step_efs_standin()`.

---

## Paso 3 — Airflow + demo conectividad → `bronce` (camino A)

<!--
  Camino A: un DAG mínimo que prueba el cableado secrets→Postgres→INSERT.
  No reemplaza el ETL ERP (camino B / Pasos 5–7).
-->

**Qué hace:** levanta Compose ≈ Fargate, publica `dw/origen-demo`, corre el DAG demo.  
**Para qué:** validar el stand-in antes del flujo ERP completo.  
**Por qué un origen “bronce” aparte:** `postgres-bronce` es el stub de conectividad del TP; el ERP rico es lab-extra.

### 3.1 Secret `dw/origen-demo`

```powershell
# Archivo UTF-8 sin BOM — PowerShell ConvertTo-Json suele romper el JSON
$tmp = "$PWD\ecs\_origen_secret.json"
[System.IO.File]::WriteAllText(
  $tmp,
  '{"host":"postgres-bronce","port":5432,"dbname":"bronce","username":"postgres","password":"postgres","engine":"postgres"}'
)
aws --endpoint-url http://localhost:4567 secretsmanager create-secret `
  --name dw/origen-demo --secret-string "file://$tmp" 2>$null
aws --endpoint-url http://localhost:4567 secretsmanager put-secret-value `
  --secret-id dw/origen-demo --secret-string "file://$tmp"
Remove-Item $tmp -Force
```

### 3.2 Compose Airflow (≈ Fargate)

| Archivo | Rol | Por qué |
|---|---|---|
| [`docker-compose.airflow.yaml`](./docker-compose.airflow.yaml) | webserver + scheduler | Sustituto Hobby de ECS service |
| [`efs-standin/dags/etl_bronce_origen_demo.py`](./efs-standin/dags/etl_bronce_origen_demo.py) | Demo INSERT | Prueba cableado |
| [`ecs_demo.py`](./ecs_demo.py) | Automatiza 0–4 | Evita bugs PowerShell |

```powershell
cd ecs
docker compose -f docker-compose.airflow.yaml up -d
# UI http://localhost:8080  → admin / admin
```

> Metastore Airflow: `postgres-dw` DB `gold` del compose = **metadata de Airflow**,  
> no el schema `gold` del DW en MiniStack.

Env relevantes del yaml:

| Env | Para qué |
|---|---|
| `PYTHONPATH=/opt/airflow/packages` | Importar paquete `etl/` (camino B) |
| `SECRETS_ENDPOINT` | MiniStack en red Docker |
| `RDS_HOST_OVERRIDE` + `RDS_PORT_OVERRIDE` | Llegar a RDS en `:15432` desde el contenedor |
| `ERP_SECRET=dw/erp` | Extract ERP (camino B; secret lo crea lab-extra) |

Volumen `./efs-standin/dags` + `./efs-standin/logs` — **qué / por qué:** es el EFS del lab (access points DAGs/logs). Todo DAG nuevo (incluido ERP→bronce y bronce→gold) va ahí.  
Volumen `../etl:/opt/airflow/packages/etl` — **qué / por qué:** librería importable (`PYTHONPATH`); en AWS iría en la imagen o también en EFS, pero **no** reemplaza el access point de DAGs.

### 3.3 Trigger demo + verificar

```powershell
docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_bronce_origen_demo
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_bronce_origen_demo

$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT * FROM bronce.ingest_batch ORDER BY batch_id DESC LIMIT 5;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT id, batch_id, origen FROM bronce.raw_record ORDER BY id DESC LIMIT 5;"
```

Esperado: `origen = origen-demo`.

---

## Paso 4 — Flujo end-to-end (camino A)

<!-- Checklist conceptual; no crea recursos. -->

```text
1. Scheduler lee DAG desde efs-standin/dags          (≈ EFS)
2. Task usa secrets MiniStack (modelo: app-role)
3. Connect SOURCE (postgres-bronce)
4. INSERT bronce.ingest_batch + bronce.raw_record    (etl_writer)
5. Logs en efs-standin/logs                          (≈ EFS logs)
```

Capas de control (lab 08): red SG → IAM secrets → GRANTs SQL (`api_reader` no ve `bronce`).

---

## Paso 5 — DDL de tablas ERP en schema `bronce` (camino B)

<!--
  MOVIDO desde lab-extra: crear estructuras en la RDS es trabajo del cómputo/ETL
  que aterriza datos (ECS task / DAG), no del sistema origen.
  El SQL vive en etl/sql/ porque describe el landing de datos; se APLICA acá.

  El DAG que aplica/asegura este DDL vive en EFS stand-in (Paso 6).
-->

**Qué hace:** crea `bronce.erp_clientes`, `bronce.erp_productos`, `bronce.erp_ventas` (+ reusa `ingest_batch`).  
**Para qué:** el lab 08 solo dejó staging genérico (`raw_record`); el ERP necesita landing **columnar**.  
**Por qué en 09b y no en lab-extra:** el DDL corre en la instancia RDS destino, tipicamente como paso del pipeline/orquestador (task `ensure_bronce_ddl` del DAG en EFS).

SQL: [`../etl/sql/bronce_erp_ddl.sql`](../etl/sql/bronce_erp_ddl.sql).

**Prereq:** lab-extra Pasos 1–2 (`postgres-erp` + `dw/erp`) + Paso 2 de este lab (EFS con los DAGs).

```powershell
# Antes del DDL/DAG: confirmar que el DAG grupo 1 YA está en el EFS stand-in
Test-Path ecs\efs-standin\dags\etl_erp_to_bronce.py
# True  → Airflow lo verá vía mount ./efs-standin/dags:/opt/airflow/dags

# Opción A — a mano (dwadmin), útil la primera vez
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
Get-Content etl\sql\bronce_erp_ddl.sql -Raw | docker exec -i $c psql -U dwadmin -d dw

# Opción B — misma función que usa el DAG (credencial etl_writer)
$env:SECRETS_ENDPOINT = "http://localhost:4567"
$env:RDS_HOST_OVERRIDE = "localhost"
$env:RDS_PORT_OVERRIDE = "15432"
python -c "from etl.load.to_cruda import ensure_bronce_erp_ddl; ensure_bronce_erp_ddl()"
```

> Si recreaste Airflow **antes** de montar `../etl` o el stand-in, forzalo:  
> `docker compose -f ecs/docker-compose.airflow.yaml up -d --force-recreate`  
> Los volúmenes EFS (`./efs-standin/dags` y `logs`) deben seguir en el yaml.

---

## Paso 6 — DAG grupo 1: ERP → `bronce` (via EFS + Airflow ≈ Fargate)

<!--
  El CÓDIGO (extract/normalize/load) está en etl/ (lab-extra).
  El ARCHIVO del DAG vive en efs-standin/dags (≈ EFS). Ese es el contrato 09b:
  varias tasks Fargate montan el mismo EFS y leen el mismo .py.
-->

**Qué hace:** ejecuta `etl_erp_to_bronce` desde el DAG montado en **EFS stand-in**.  
**Para qué:** materializar el grupo 1 del to-be sobre el stand-in Fargate+EFS.  
**Por qué EFS acá:** el scheduler descubre el DAG solo porque está en `/opt/airflow/dags` ← bind de `efs-standin/dags`. Los logs del run quedan en `efs-standin/logs` (mismo EFS, access point logs).

| Capa | Dónde | Rol |
|---|---|---|
| DAG `.py` | `ecs/efs-standin/dags/etl_erp_to_bronce.py` | ≈ EFS `/airflow/dags` |
| Logs run | `ecs/efs-standin/logs/dag_id=etl_erp_to_bronce/...` | ≈ EFS `/airflow/logs` |
| Librería | `etl/` vía `PYTHONPATH` | Imagen/código; no reemplaza EFS |
| Datos | RDS `bronce.erp_*` | No van al EFS |

| Task Airflow | Llama a | Por qué |
|---|---|---|
| `ensure_bronce_ddl` | `load.ensure_bronce_erp_ddl` | Idempotencia: tablas listas antes del load |
| `extract_erp` | `extract.erp_foxpro` | Lee origen vía `dw/erp` |
| `transform_normalize` | `transform.normalize` | Limpieza pre-landing |
| `load_bronce` | `load.load_erp_to_bronce` | UPSERT `bronce.erp_*` |

```powershell
# 1) El DAG debe existir en el stand-in EFS (si no, Airflow no lo parsea)
Get-Item ecs\efs-standin\dags\etl_erp_to_bronce.py

# 2) Trigger (Airflow ya montó efs-standin en Paso 3)
docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_erp_to_bronce
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_erp_to_bronce

# 3) Logs en EFS stand-in (no solo en la UI)
Get-ChildItem -Recurse ecs\efs-standin\logs -Filter "attempt=*.log" |
  Where-Object { $_.FullName -match "etl_erp_to_bronce" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3 FullName
```

### Verificar bronce (datos en RDS, no en EFS)

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM bronce.erp_clientes;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM bronce.erp_productos;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT nro_orden, id_cliente, id_producto, importe_neto FROM bronce.erp_ventas LIMIT 5;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT * FROM bronce.ingest_batch WHERE origen='erp' ORDER BY batch_id DESC LIMIT 3;"
```

Esperado: ≥12 clientes/productos, ≥12 ventas; `origen='erp'`.

---

## Paso 7 — DAG grupo 2: `bronce` → `gold` (via EFS + Airflow ≈ Fargate)

<!--
  Grupo 2 NO vuelve al ERP: lee el landing (desacopla origen de analytics).
  Mismo EFS que el grupo 1: otro .py en efs-standin/dags, mismos mounts del compose.
  Lambda API (labs siguientes) solo SELECT gold — por eso api_reader no ve bronce.
-->

**Qué hace:** ejecuta `etl_bronce_to_gold` cuyo `.py` también vive en el **EFS stand-in**.  
**Para qué:** cargar el Modelo_DW (dims + `fact_venta_linea`) del lab 08.  
**Por qué mismo EFS:** en AWS, varias task definitions montan el mismo filesystem; agregar un DAG = subir un archivo al access point `/airflow/dags`, no redeployar otra “carpeta Airflow”.

| Capa | Dónde | Rol |
|---|---|---|
| DAG `.py` | `ecs/efs-standin/dags/etl_bronce_to_gold.py` | ≈ EFS `/airflow/dags` |
| Logs run | `ecs/efs-standin/logs/dag_id=etl_bronce_to_gold/...` | ≈ EFS `/airflow/logs` |
| Librería | `etl.transform.to_gold` / `etl.load.to_dw` | Código |
| Datos | RDS `gold.*` | No van al EFS |

| Task Airflow | Llama a | Por qué |
|---|---|---|
| `extract_bronce` | `extract.from_bronce` | Fuente = landing, no ERP |
| `transform_to_gold` | `transform.to_gold` | Mapeo dimensional |
| `load_gold` | `load.load_gold_bundle` | UPSERT `gold.*` |

```powershell
# Confirmar DAG en EFS stand-in
Get-Item ecs\efs-standin\dags\etl_bronce_to_gold.py

docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_bronce_to_gold
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_bronce_to_gold

# Logs EFS
Get-ChildItem -Recurse ecs\efs-standin\logs -Filter "attempt=*.log" |
  Where-Object { $_.FullName -match "etl_bronce_to_gold" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3 FullName
```

### Verificar gold (RDS)

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM gold.dim_cliente;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM gold.dim_producto;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT nro_orden, cliente_sk, producto_sk, importe_neto, margen_bruto FROM gold.fact_venta_linea ORDER BY venta_sk LIMIT 5;"
```

### Flujo EFS end-to-end (camino B)

```text
1. DAGs .py en efs-standin/dags          (≈ EFS /airflow/dags)
2. Compose monta ese árbol en Fargate-stand-in
3. Scheduler parsea etl_erp_to_bronce + etl_bronce_to_gold
4. Tasks escriben logs en efs-standin/logs (≈ EFS /airflow/logs)
5. Datos → RDS bronce/gold               (EFS NUNCA guarda el DW)
```

---

## Paso 8 — Decisión (opcional)

En [`docs/decisions.md`](../docs/decisions.md):

```
### 012 — Airflow (Fargate to-be) + EFS; datos en RDS Bronce/Gold

Decision: orquestar ETL con Airflow; DAGs/logs en storage compartido;
grupo 1 → bronce; grupo 2 → gold vía paquete etl/.
Justificación: docs/Solution_Architecture.md §5.2.

Tradeoff: Hobby sin API ECS/EFS — stand-in Docker.
```

---

## Paso 9 — Cleanup

```powershell
cd ecs
docker compose -f docker-compose.airflow.yaml down
# No borres VPC, RDS ni postgres-erp (labs 07/08/extra)
# python ecs/ecs_demo.py --cleanup
```

---

## Checkpoint

**Camino A (demo)**  
- [ ] `ecsTaskExecutionRole` + `app-role` con `InlineEtlSecrets`  
- [ ] Airflow en `:8080`; DAG `etl_bronce_origen_demo` success  
- [ ] Filas en `bronce.ingest_batch` / `bronce.raw_record`

**Camino B (ERP — requiere lab-extra)**  
- [ ] Los DAGs ERP/gold están en `ecs/efs-standin/dags/` (contrato EFS)  
- [ ] DDL `bronce.erp_*` aplicado  
- [ ] DAG `etl_erp_to_bronce` success + logs en `efs-standin/logs`  
- [ ] DAG `etl_bronce_to_gold` success + logs en `efs-standin/logs`  
- [ ] Filas en `gold.dim_cliente` / `dim_producto` / `fact_venta_linea`  
- [ ] Claro: EFS = DAGs/logs; RDS = datos bronce/gold  

**Concepto**  
- [ ] Hobby = stand-in; AWS = Fargate + EFS reales  
- [ ] Origen/código en lab-extra; orquestación/DDL/DAGs en este lab  

---

## Hobby vs AWS real

| Acción | Hobby | AWS real |
|---|---|---|
| IAM execution + task | ✅ LocalStack | ✅ |
| VPC / SG | ✅ 07-v2 | ✅ |
| EFS / ECS API | ❌ | ✅ |
| Airflow + DAGs compartidos | ✅ Compose + stand-in | ✅ Fargate + EFS |
| DDL landing + DAGs grupo 1/2 | ✅ Pasos 5–7 | ✅ mismas tasks |
| Automatización demo | ✅ `ecs_demo.py` | Task def + CI |

---

## Archivos

| Archivo | Rol |
|---|---|
| `lab-09b-tp.md` | Esta guía (cómputo ECS) |
| `ecs_demo.py` | Demo camino A (pasos 0–4) |
| `IAM-NOTES.md` | Roles 1.1 / 1.2 |
| `trust_ecs.json`, `*_policy.json` | IAM |
| `efs-standin/` | ≈ EFS (DAGs + logs) |
| `docker-compose.airflow.yaml` | ≈ Fargate (+ mount `etl/`) |
| `efs-standin/dags/etl_bronce_origen_demo.py` | Camino A |
| `efs-standin/dags/etl_erp_to_bronce.py` | Camino B grupo 1 |
| `efs-standin/dags/etl_bronce_to_gold.py` | Camino B grupo 2 |
| `../etl/` | Lógica (documentada en lab-extra) |
| `../etl/sql/bronce_erp_ddl.sql` | DDL aplicado en Paso 5 |

---

## Relación con labs / docs

| Fuente | Aporte |
|---|---|
| `docs/` Infra + Solution | To-be Fargate + EFS + Bronce/Gold |
| 04 IAM | `app-role` trust ECS |
| 07-v2 VPC | SG / subnets / NAT |
| 08-tp RDS | schemas + `dw/rds-etl` |
| **lab-extra** | ERP + `dw/erp` + módulos `etl/` |
| 09 IaC | Declarar infra; 09b ejecuta cómputo en Hobby |
