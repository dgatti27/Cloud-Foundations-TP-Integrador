# Lab 09b TP — Airflow ETL → Bronce (stand-in Fargate + EFS)

<!--
  Este lab materializa la CAPA DE CÓMPUTO del to-be (Airflow en Fargate + EFS)
  sobre LocalStack Hobby, donde las APIs ecs/efs NO existen.

  Lectura recomendada:
    1) Este archivo (qué / por qué de cada paso)
    2) ecs/ecs_demo.py   → automatiza pasos 0–4 con los mismos comentarios
    3) ecs/IAM-NOTES.md  → detalle execution role vs task role
    4) docs/Infraestructure_Architecture.md + docs/Solution_Architecture.md §4–5

  Atajo reproducible:
    python ecs/ecs_demo.py
-->

## Qué implementa (y qué NO)

Implementa en **LocalStack Hobby** la capa de cómputo del to-be de:

| Documento | Qué fija |
|---|---|
| [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md) | App privada = Airflow (scheduler/webserver/worker) + storage compartido DAGs/logs; datos = RDS |
| [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §4–5 | ETL grupo 1 → **Bronce**; EFS para DAGs/logs; NAT a orígenes; Secrets + IAM |

> **Alcance Hobby (este lab)**  
> LocalStack Hobby incluye IAM, EC2/VPC, logs, etc. **No** incluye `ecs` ni `efs` (licencia Pro).  
> Por eso **no** hay pasos `create-cluster` / `register-task-definition` / `create-file-system`.  
>
> | To-be AWS (`docs/`) | Hobby (este lab) | Por qué esa equivalencia |
> |---|---|---|
> | ECS Fargate (Airflow) | `docker-compose.airflow.yaml` | Misma imagen/proceso; sin API ECS |
> | EFS (DAGs + logs) | `ecs/efs-standin/` montado en el compose | Mismo contrato: árbol compartido entre procesos |
> | Task role / execution role | Roles IAM en LocalStack | Documentan privilegio mínimo; Compose usa keys `test` |
> | RDS Bronce | MiniStack `tp-dw-db` + secret `dw/rds-etl` | Ya provisionado en lab 08-tp |
>
> En AWS / Learner Lab se materializa Fargate + EFS reales con el **mismo** diseño de VPC/IAM.

Cierra el arco: **IAM (04) → VPC (07-v2) → RDS (08-tp) → cómputo ETL (hoy)**.

### Mapeo docs → lab

| To-be (`docs/`) | TP local | Nota |
|---|---|---|
| Bronce + DW en RDS Multi-AZ | `tp-dw-db`, schemas `bronce` + `gold` | Datos viven en Postgres, no en EFS |
| Airflow → Fargate + EFS | Compose Airflow + `efs-standin` | Stand-in pedagógico |
| Orígenes por host | Secret `dw/origen-demo` + `postgres-bronce` | Un secret por origen (patrón to-be) |
| Staging S3 | MinIO (decisión 002) | Opcional en este lab |
| Credencial ETL | `dw/rds-etl` → `etl_writer` | Solo escribe bronce/gold; no es master |

```text
Origen demo (postgres-bronce)
        │
        ▼
┌─ Stand-in app (≈ Fargate + EFS) ─────────────────────────┐
│  Docker: Airflow webserver + scheduler                   │
│  Volumen efs-standin → /opt/airflow/dags + logs          │
│       └── :15432 ──► MiniStack RDS  schema bronce        │
└──────────────────────────────────────────────────────────┘
        ▲
        │ IAM modelo: app-role + ecsTaskExecutionRole (LocalStack)
        │ Secrets: dw/rds-etl + dw/origen-demo (MiniStack :4567)
```

---

## Por qué este lab

| Pieza to-be | Fuente | Qué hacemos en Hobby | Por qué importa |
|---|---|---|---|
| Roles Fargate (execution + task) | Solution §4.1 | Paso 1 — IAM en LocalStack | Separar boot vs runtime (least privilege) |
| EFS DAGs/logs | Solution §5.2 | Paso 2 — carpeta `efs-standin` | Varias tasks ven el mismo DAG/código |
| Airflow orquesta ETL grupo 1 | Infra flujo | Paso 3 — compose + DAG → `bronce` | Demuestra el camino de datos real |
| SG / NAT / subnets | Lab 07-v2 | Ya existen | En AWS el compose se “mueve” a esas subnets |

---

## Cómo ejecutarlo

### Opción A — Script (recomendado)

```powershell
# Prereqs: docker compose base up + labs 04, 07-v2, 08-tp
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

python ecs/ecs_demo.py
# Flags útiles:
#   python ecs/ecs_demo.py --skip-runtime   # solo IAM + secret + dirs
#   python ecs/ecs_demo.py --cleanup        # apaga Airflow al final
```

`ecs_demo.py` hace los pasos 0–4 con comentarios inline (qué / por qué). Preferilo a copiar/pegar PowerShell: evita el bug de JSON con comillas en Windows.

### Opción B — Manual (abajo)

Los bloques PowerShell sirven para entender cada API; el resultado esperado es el mismo que el script.

---

## Prerequisitos

```powershell
docker compose up -d localstack-integrador ministack-integrador s3-soporte redis postgres-bronce postgres-dw

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

# Lab 04 — task role base (app-role). Sin esto el Paso 1.2 no tiene dónde colgar InlineEtlSecrets.
awslocal iam get-role --role-name app-role --query "Role.Arn" --output text
# Si falta: python iam/iam_demo.py

# Lab 07-v2 — VPC + SGs del diseño. Filtros entrecomillados: PowerShell parte mal los Values= si no.
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc" --query "Vpcs[0].VpcId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-ecs-etl" --query "SecurityGroups[0].GroupId" --output text
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" --query "SecurityGroups[0].GroupId" --output text

# Lab 08-tp — RDS + secret ETL. El DAG escribe con etl_writer (dw/rds-etl), no con master.
curl.exe -s http://localhost:4567/_ministack/health
# Solo Name (no imprimas SecretString en demos / logs compartidos)
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret --secret-id dw/rds-etl --query "Name" --output text
```

### Endpoints (no mezclar)

| Servicio | URL | Uso | Error típico si mezclás |
|---|---|---|---|
| LocalStack | `:4566` | IAM + VPC | Buscar secrets aquí → no existen |
| MiniStack | `:4567` | Secrets + RDS lógica | IAM aquí → no existe |
| MinIO | `:9000` | Staging opcional | — |
| postgres-bronce | `:5432` | Source demo | — |
| RDS MiniStack (host) | `:15432` | Destino `bronce` | Usar el IP del secret sin override desde el host |

> MiniStack publica `4567:4566`: **desde el host** Secrets = `:4567`; **entre contenedores** = `ministack-integrador:4566` (así está `SECRETS_ENDPOINT` en el compose).

---

## Paso 1 — IAM: execution role + task role (Hobby ✅)

<!--
  En Fargate hay SIEMPRE dos roles. Mezclarlos es el error más común:
  - Execution = lo que necesita el agente ECS antes/durante el arranque.
  - Task     = lo que necesita TU código (Airflow/DAG) ya corriendo.
  Detalle ampliado: IAM-NOTES.md
-->

En Fargate hay **dos** roles. Los creamos en LocalStack aunque el runtime sea Docker: documentan el privilegio mínimo del to-be.

```text
Agente (boot) → ecsTaskExecutionRole   |  Contenedor (ETL) → app-role
  pull imagen, awslogs                   |    Secrets ETL/orígenes, S3 staging
```

Detalle: [`IAM-NOTES.md`](./IAM-NOTES.md). Automatizado en `ecs_demo.py` → `step_iam()`.

### 1.1 Execution role

```powershell
# Quién: agente ECS al arrancar (modelo AWS). En Hobby solo queda el rol creado.
# Trust: solo ecs-tasks.amazonaws.com puede AssumeRole (trust_ecs.json).
awslocal iam create-role `
  --role-name ecsTaskExecutionRole `
  --assume-role-policy-document file://ecs/trust_ecs.json 2>$null

# Policy: ECR pull + CloudWatch Logs. NO incluye Secrets ni S3 de negocio.
awslocal iam put-role-policy `
  --role-name ecsTaskExecutionRole `
  --policy-name InlineEcsExecution `
  --policy-document file://ecs/execution_policy.json

awslocal iam get-role --role-name ecsTaskExecutionRole --query "Role.Arn" --output text
```

### 1.2 Task role — Secrets en `app-role`

```powershell
# Quién: código Airflow/DAG. Amplía app-role (lab 04) sin tocar master/api.
# InlineEtlSecrets permite GetSecretValue solo sobre dw/rds-etl* y dw/origen* …
awslocal iam put-role-policy `
  --role-name app-role `
  --policy-name InlineEtlSecrets `
  --policy-document file://ecs/task_secrets_policy.json

awslocal iam list-role-policies --role-name app-role
# Esperado: InlineS3Read + InlineEtlSecrets
```

| | 1.1 Execution | 1.2 Task (`app-role`) |
|---|---|---|
| Momento (AWS) | Boot de la task | Runtime del ETL |
| ECR / awslogs | Sí | No |
| `dw/rds-etl` / orígenes | No | Sí |
| S3 staging | No | Sí (lab 04) |

> El compose del Paso 3 **no asume** estos roles (LocalStack no inyecta credenciales en Docker). Usa `AWS_ACCESS_KEY_ID=test` contra MiniStack. Los roles quedan como **modelo IAM** alineado a `docs/`.

---

## Paso 2 — “EFS” local: DAGs + logs compartidos (Hobby ✅)

<!--
  En AWS, varias tasks Fargate montan el mismo EFS vía access points
  (/airflow/dags, /airflow/logs). Sin eso, cada task tendría su propio
  filesystem efímero y no compartirían DAGs ni logs.
  Hobby: un directorio del repo bind-mounted en todos los servicios Airflow.
-->

En AWS, EFS comparte DAGs/logs entre tasks Fargate. En Hobby usamos un directorio montado en todos los contenedores Airflow.

**Access point (concepto to-be):** puerta a un subpath del EFS (`/airflow/dags` o `/airflow/logs`) con uid del user `airflow`. Aquí: subcarpetas de `efs-standin`.

```powershell
# SG del diseño 07-v2 (existe aunque no haya NFS). En AWS abriría :2049 desde sg-ecs-etl.
awslocal ec2 describe-security-groups --filters "Name=group-name,Values=sg-efs" `
  --query "SecurityGroups[0].{Id:GroupId,Name:GroupName}" --output table

New-Item -ItemType Directory -Force -Path ecs\efs-standin\dags, ecs\efs-standin\logs | Out-Null
Get-ChildItem ecs\efs-standin\dags
# Esperado: etl_bronce_origen_demo.py

# Inventario stand-in vs to-be (mode=stand-in)
Get-Content ecs\efs_config.json
```

| AWS (to-be) | Hobby |
|---|---|
| EFS + access points | `ecs/efs-standin/{dags,logs}` |
| Mount en Fargate | Bind mounts del compose |
| `sg-efs` :2049 | Documentado; runtime = red Docker |

**EFS/stand-in no guarda el DW** — solo orquestación. Datos → RDS `bronce`.

Automatizado en `ecs_demo.py` → `step_efs_standin()`.

---

## Paso 3 — Airflow + ETL grupo 1 → `bronce` (Hobby ✅)

Runtime ejecutable: Compose ≈ Fargate; volumen ≈ EFS.

### 3.1 Secret de origen (MiniStack)

<!--
  Patrón to-be: un secret por origen (dw/erp, dw/ecommerce, …).
  app-role solo puede leer esos ARNs (task_secrets_policy.json).
  El DAG no hardcodea host/password: los lee de Secrets Manager.
-->

**Preferí el script** (`step_origen_secret`): en PowerShell, `ConvertTo-Json` + CLI suele guardar JSON **sin comillas dobles** y el DAG muere con `JSONDecodeError`.

Si lo hacés a mano, usá un archivo UTF-8 **sin BOM**:

```powershell
# Escribí JSON válido a archivo (evita que PowerShell strippee comillas)
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

# Verificar existencia (no imprimir SecretString)
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret `
  --secret-id dw/origen-demo --query "Name" --output text
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret `
  --secret-id dw/rds-etl --query "Name" --output text

docker ps --filter "name=ministack-rds" --format "{{.Names}} {{.Ports}}"
# Destino desde el host / compose: localhost:15432 (RDS_HOST_OVERRIDE)
```

### 3.2 DAG y compose (ya en el repo)

| Archivo | Rol | Por qué |
|---|---|---|
| [`efs-standin/dags/etl_bronce_origen_demo.py`](./efs-standin/dags/etl_bronce_origen_demo.py) | EXTRACT origen → INSERT `bronce.*` | Mismo código que llevarías a Fargate |
| [`docker-compose.airflow.yaml`](./docker-compose.airflow.yaml) | webserver + scheduler + mounts | Sustituto Hobby de ECS service |
| [`ecs_demo.py`](./ecs_demo.py) | Orquesta pasos 0–4 | Reproducible; JSON seguro |

El DAG: lee `dw/origen-demo` y `dw/rds-etl` en MiniStack → escribe `bronce.ingest_batch` / `bronce.raw_record`.

### 3.3 Levantar Airflow

```powershell
cd ecs
docker compose -f docker-compose.airflow.yaml up -d
# UI http://localhost:8080  → admin / admin
# Trigger DAG: etl_bronce_origen_demo
#
# O desde el script (espera parse + success):
#   python ../ecs/ecs_demo.py
```

> Metastore Airflow: `postgres-dw` (DB `gold` del compose) — solo metadata de Airflow, **no** es el schema `gold` del DW en MiniStack.

Primera vez: Docker descarga `apache/airflow:2.9.3-python3.12` (puede tardar).

Trigger CLI (equivalente a lo que hace `ecs_demo.py`):

```powershell
docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_bronce_origen_demo
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_bronce_origen_demo
```

### 3.4 Verificar `bronce`

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT * FROM bronce.ingest_batch ORDER BY batch_id DESC LIMIT 5;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT id, batch_id, origen, payload FROM bronce.raw_record ORDER BY id DESC LIMIT 5;"
```

Esperado: filas con `origen = origen-demo`.

---

## Paso 4 — Flujo end-to-end

<!--
  Este paso no crea recursos: consolida el relato del camino de datos
  y las capas de control ya construidas en labs 04/07/08.
-->

```text
1. Scheduler lee DAG desde efs-standin/dags          (≈ EFS)
2. Task usa secrets MiniStack (modelo: app-role)
3. Connect SOURCE (postgres-bronce)
4. INSERT bronce.ingest_batch + bronce.raw_record    (etl_writer)
5. Logs en efs-standin/logs                          (≈ EFS logs)
```

Capas de control (lab 08): red SG → IAM secrets → GRANTs SQL (`api_reader` no ve `bronce`).

`ecs_demo.py` → `step_e2e_narrative()` imprime este checklist tras verificar.

---

## Paso 5 — Decisión (opcional)

En [`docs/decisions.md`](../docs/decisions.md):

```
### 012 — Airflow (Fargate to-be) + EFS; datos en RDS Bronce

Decision: orquestar ETL con Airflow; DAGs/logs en storage compartido (EFS en AWS;
volumen en Hobby); crudos en schema bronce vía dw/rds-etl.
Justificación: docs/Solution_Architecture.md §5.2.

Tradeoff: Hobby no tiene API ECS/EFS — lab 09b usa Docker stand-in.
Resultado: IAM roles + compose Airflow + DAG → bronce.
```

---

## Paso 6 — Cleanup

```powershell
cd ecs
docker compose -f docker-compose.airflow.yaml down
# No borres VPC ni RDS (labs 07/08)
# Equivalente: python ecs/ecs_demo.py --cleanup  (si también corriste el demo)
```

---

## Checkpoint

- [ ] `ecsTaskExecutionRole` + `app-role` con `InlineEtlSecrets`
- [ ] `ecs/efs-standin/dags` con el DAG demo
- [ ] Airflow UI en `:8080` y DAG triggereado (`python ecs/ecs_demo.py` o UI)
- [ ] Filas en `bronce.ingest_batch` / `bronce.raw_record`
- [ ] Claro: Hobby = stand-in; AWS = Fargate + EFS reales (`docs/`)

---

## Hobby vs AWS real

| Acción | Hobby (este lab) | AWS real |
|---|---|---|
| IAM execution + task role | ✅ LocalStack | ✅ |
| VPC / SG (`sg-ecs-etl`, `sg-efs`) | ✅ lab 07-v2 | ✅ |
| EFS / ECS API | ❌ fuera de licencia | ✅ |
| Airflow + DAGs/logs compartidos | ✅ Compose + `efs-standin` | ✅ Fargate + EFS |
| ETL → `bronce` | ✅ MiniStack | ✅ RDS |
| Automatización | ✅ `ecs/ecs_demo.py` | Task definition + CI |

---

## Archivos

| Archivo | Rol |
|---|---|
| `lab-09b-tp.md` | Este lab (solo Hobby) — guía comentada |
| `ecs_demo.py` | Script Python pasos 0–4 (recomendado) |
| `IAM-NOTES.md` | Detalle roles 1.1 / 1.2 |
| `trust_ecs.json`, `execution_policy.json`, `task_secrets_policy.json` | IAM |
| `efs-standin/` | ≈ EFS |
| `efs_config.json` | Inventario stand-in |
| `docker-compose.airflow.yaml` | ≈ Fargate |
| `etl/` | Lógica reutilizable por DAGs |

---

## Relación con labs / docs

| Fuente | Aporte |
|---|---|
| `docs/` Infra + Solution | To-be Fargate + EFS + flujo Bronce |
| 04 IAM | `app-role` trust ECS |
| 07-v2 VPC | SG / subnets / NAT (diseño) |
| 08-tp RDS | `bronce` + `dw/rds-etl` |
| 09 IaC | Declarar infra; 09b declara cómputo ETL ejecutable en Hobby |
| `ecs_demo.py` | Ejecuta 09b de punta a punta en Hobby |
