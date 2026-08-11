# Lab API TP — Lambda GET sobre GOLD (privada) + ALB stand-in (público)

**Clase / módulo:** API del TP Integrador · **Tiempo estimado:** 45–75 min · **Entregable:** evidencia en el informe del TP (o `NombreApellido-api.md`)

> **Objetivo:** exponer el schema `gold` con una Lambda de solo lectura detrás de una entrada “pública” (ALB stand-in en Hobby).
> Al terminar tenés que poder responder con evidencia:
> 1. ¿Con qué permisos corre el código (rol) y quién puede invocarlo (grupo BI) — y qué **no** puede hacer cada uno?
> 2. ¿Por qué la Lambda vive en compute **privada** y el ALB (stand-in) en el borde **público**?
> 3. ¿Cómo el contrato GET evita SQL libre / bronce y qué pasa si pedís una tabla fuera de allowlist?
> 4. ¿Dónde quedan los logs de cada evento (CloudWatch) y cómo se persisten en el lake (MinIO/S3)?

<!--
  Frontera
  ────────
  ESTE LAB (lambda/): capa API del to-be.
    - Lambda en subnets private-compute (Role=ecs-lambda-efs) + sg-api
    - Solo lectura schema gold vía secret dw/rds-api (rol SQL api_reader)
    - Entrada externa: ALB HTTPS en public-alb-* (Hobby = alb-standin :8088)
    - IAM: api-role (Lambda) + grupo bi-api / bi-ops (Invoke, sin secretos DB)
    - Observabilidad: CW Logs + export a MinIO (backup-data-lake/logs/...)

  NO hace: ETL, EFS, Airflow → labs extra / 09b.
  NO es lab-14 (cold start / costo por invocación) — ahí se mide frío/caliente;
  acá el foco es API + red + least privilege sobre gold (+ persistir logs en el lake).
  Prereq datos gold: lab-extra + ecs_demo.py --erp (o pipelines).

  Script de ejecución:
    python lambda/lambda_demo.py
-->

---

## Qué implementa (y qué NO)

| Documento | Qué fija |
|---|---|
| [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §5.3 | API Lambda detrás de ALB; Qlik/BI por HTTPS; RDS no pública |
| [`docs/Infraestructure_Architecture.md`](../docs/Infraestructure_Architecture.md) | Lambda en app privada; ALB en pública |
| Lab 07-v2 | Subnets `public-alb-*` / `private-compute-*`; SG `sg-alb` → `sg-api` → `sg-rds` |
| Lab 08-tp | Secret `dw/rds-api` + rol SQL `api_reader` (SELECT gold; sin bronce) |
| Lab 14 (`lambda_lab/`) | Anatomía Lambda / cold start / costo — **otro alcance**; no sustituye este lab |

```text
Postman / BI (Internet)
        │  HTTPS :443  (Hobby: HTTP :8088 alb-standin)
        ▼
┌─ Pública (ALB / stand-in) ──────────────┐
│  sg-alb · subnets public-alb-a/b        │
└──────────────────┬──────────────────────┘
                   │ solo hacia sg-api
                   ▼
┌─ Privada compute (Lambda) ──────────────┐
│  sg-api · Role=ecs-lambda-efs           │
│  api-role → secret dw/rds-api           │
└──────────────────┬──────────────────────┘
                   │ :5432 solo desde sg-api
                   ▼
              RDS gold (api_reader)
```

> **Hobby vs AWS**  
> LocalStack Hobby tiene **Lambda** en `SERVICES`, **no** ELBv2.  
> Por eso el “ALB HTTPS público” se simula con `docker-compose.alb.yaml`  
> (`alb-standin` en la red del compose, puerto host **8088**).  
> En AWS Learner Lab: ALB real :443 + certificado + target Lambda.

---

## Prerrequisitos

- Labs **04** (grupos `bi-*`), **07-v2** (`vpc/vpc_config.json`), **08-tp** (`dw/rds-api` + `api_reader`)
- Datos en **gold** (ETL / `ecs_demo.py --erp` o `etl_demo.py`)
- Emuladores: LocalStack `:4566`, MiniStack `:4567`, MinIO si aplica al resto del TP
- Desde la **raíz del repo** (las rutas `file://lambda/...` y `python lambda/...` asumen eso)

Verificar secret (MiniStack):

```powershell
# En PowerShell, comillas en --filters / query evitan el error "filter 'null'"
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret `
  --secret-id dw/rds-api --query Name --output text
```

| Endpoint | Uso |
|---|---|
| LocalStack `:4566` | IAM + Lambda + CloudWatch Logs + (modelo) VPC |
| MiniStack `:4567` | Secret `dw/rds-api` |
| RDS host (port map MiniStack) | Destino gold |
| MinIO `:9000` | Lake S3 — export de logs (`backup-data-lake`) |
| ALB stand-in `:8088` | Entrada Postman (Hobby) |

> **Si `awslocal` no está disponible**, usá  
> `aws --endpoint-url http://localhost:4566 --region us-east-1`  
> para IAM/Lambda en LocalStack. Secrets DB → siempre MiniStack `:4567`.

### Notas PowerShell (cosas que suelen romper el lab)

| Situación | Qué hacer |
|---|---|
| `export VAR=...` | `$env:VAR = "..."` o `$VAR = "..."` |
| Continuación `\` | Usar `` ` `` al final de línea, o comando en una línea |
| `&&` / `time` / `zip` | `;`, `Measure-Command`, `Compress-Archive` (o usá el script Python) |
| `echo '{...}' > file.json` | Puede escribir UTF-16 → payloads rotos. Preferí `[System.IO.File]::WriteAllText(...)` o el script |
| Filtros EC2/IAM con comas | Siempre entre comillas: `--filters "Name=tag:Name,Values=..."` |

---

## Script de ejecución (recomendado)

Automatiza los pasos 1–3 (IAM → deploy Lambda → ALB → invoke de prueba). Es el camino canónico del TP; los pasos siguientes son para **entender** y **verificar**.

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

# Datos en gold (si aún no):
#   python etl/etl_demo.py
#   python ecs/ecs_demo.py --erp

python lambda/lambda_demo.py
# python lambda/lambda_demo.py --skip-alb
# python lambda/lambda_demo.py --skip-logs-export
# python lambda/lambda_demo.py --logs-export-only
# python lambda/lambda_demo.py --cleanup
```

El script hace: prereqs → IAM → zip/deploy Lambda (VpcConfig) → ALB stand-in → invoke + GET de prueba → **export CloudWatch Logs → MinIO**.

---

## Paso 0 — Leer el código antes de deployarlo

```powershell
Get-Content lambda\handler.py
Get-Content lambda\query_gold.py
Get-Content lambda\trust_lambda.json
Get-Content lambda\task_api_policy.json
Get-Content lambda\group_bi_api_policy.json
```

Tres capas deliberadas (análogas a lab-14, aplicadas a este diseño):

| Pieza | Pregunta | En este lab |
|---|---|---|
| **Trust policy** | ¿Quién puede *asumir* el rol? | `trust_lambda.json` → `lambda.amazonaws.com` |
| **Permissions policy** | ¿Qué puede hacer el *código*? | `execution_policy.json` (logs/ENI) + `task_api_policy.json` (solo `dw/rds-api*`) |
| **Quién invoca** | ¿Quién puede *llamar* la función? | Grupo `bi-api` / `bi-ops` + `group_bi_api_policy.json` (`InvokeFunction`; **Deny** secrets ETL/master) |

Además, en SQL: `api_reader` solo SELECT en **gold** (lab 08). La API no usa `dw/rds-etl` ni master.

- **Fuera / init del handler:** clientes y lectura de secret (amortizable entre invocaciones del mismo entorno).
- **Dentro del handler:** parseo del event (ALB / invoke) → `query_gold` → respuesta HTTP.

> **Para el entregable:** no confundas trust, permissions e invoke/group policy. No son lo mismo que la *resource policy* de la función en AWS real; acá el control de “quién invoca” lo modelamos con el grupo IAM BI.

---

## Paso 1 — IAM: `api-role` + grupo `bi-api`

<!--
  Dos capas de privilegio:
  1) api-role → lo asume Lambda (secrets dw/rds-api + logs + ENI modelo)
  2) bi-api / bi-ops → InvokeFunction; Deny GetSecretValue de ETL/master
  SQL api_reader ya limitó SELECT a gold en lab 08.
-->

**Qué hace:** crea el rol de ejecución de la función y un grupo de consumidores BI.  
**Para qué:** least privilege — la API no ve `dw/rds-etl` ni bronce; BI no recibe passwords DB.  
**Por qué “subgrupo” en bi-ops:** IAM no tiene subgrupos; se replica la policy de invoke en `bi-ops` (lab 04) para que ops también pueda invocar sin secretos.

| Artefacto | Quién | Permiso |
|---|---|---|
| [`trust_lambda.json`](./trust_lambda.json) | Lambda service | AssumeRole |
| [`execution_policy.json`](./execution_policy.json) | api-role | Logs + ENI (modelo VPC) |
| [`task_api_policy.json`](./task_api_policy.json) | api-role | Solo `dw/rds-api*` |
| [`group_bi_api_policy.json`](./group_bi_api_policy.json) | bi-api (+ bi-ops) | `lambda:InvokeFunction` `tp-gold-api`; Deny secrets ETL/master |

Automatizado en `lambda_demo.py` → `step_iam()`.

Verificación sugerida:

```powershell
awslocal iam get-role --role-name api-role --query "Role.Arn"
awslocal iam list-attached-role-policies --role-name api-role
awslocal iam get-group --group-name bi-api
```

---

## Paso 2 — Lambda en subnet privada (compute / ECS)

<!--
  Misma Role=ecs-lambda-efs que Fargate (lab 07-v2): app privada compartida.
  VpcConfig en create_function documenta el diseño; en Hobby el runtime Docker
  de LocalStack alcanza MiniStack vía host.docker.internal (override env).
-->

**Qué hace:** despliega `tp-gold-api` con handler GET → SELECT gold.  
**Para qué:** cómputo serverless de la API (Solution §5.3).  
**Por qué VPC compute:** no vive en pública; solo recibe tráfico desde ALB / `sg-alb` → `sg-api`.

Código:

| Archivo | Rol |
|---|---|
| [`handler.py`](./handler.py) | Adapta event ALB/API GW / invoke → respuesta HTTP |
| [`query_gold.py`](./query_gold.py) | Allowlist tablas gold + condition parametrizada |

Anatomía (pegá en el entregable, como en lab-14):

```powershell
awslocal lambda get-function-configuration --function-name tp-gold-api `
  --query "{Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,Handler:Handler,Role:Role,VpcConfig:VpcConfig}"
```

### Contrato de la API (Postman)

```http
GET /gold/query?table=dim_cliente&columns=cliente_sk,nombre,email&condition=segmento=retail&limit=5
```

| Parámetro | Alias | Qué hace | Por qué restringido |
|---|---|---|---|
| `table` | `tabla` | Tabla en schema **gold** | Allowlist; nunca bronce |
| `columns` | `columnas` | Lista CSV o `*` | Solo identificadores `[A-Za-z_][A-Za-z0-9_]*` |
| `condition` | `condicion` | `col=valor` / `!=` / `>` / `LIKE` … | Sin `;` ni comentarios; valor por placeholder |
| `limit` | `limite` | Máx filas (cap 500) | Evita scans enormes |

Detrás: `SELECT … FROM gold."<table>" WHERE … LIMIT n` con `api_reader`.

Invoke de prueba (sin pasar por el stand-in), útil para aislar fallos:

```powershell
# Payload UTF-8 (no uses echo > en PowerShell)
[System.IO.File]::WriteAllText("$PWD\event-gold.json", '{"table":"dim_cliente","columns":"nombre,email","condition":"segmento=retail","limit":5}')
awslocal lambda invoke --function-name tp-gold-api --payload fileb://event-gold.json out-gold.json
Get-Content out-gold.json
```

---

## Paso 3 — ALB stand-in (entrada pública)

**Qué hace:** contenedor alcanzable desde el host (`:8088`) que invoca la Lambda en LocalStack.  
**Para qué:** simular “BI en Internet → ALB HTTPS → Lambda”.  
**Por qué no ELB real:** fuera de licencia Hobby; el yaml documenta el mapeo a `public-alb-*` / `sg-alb`.

```powershell
docker compose -f lambda/docker-compose.alb.yaml up -d --build
curl.exe "http://localhost:8088/health"
curl.exe "http://localhost:8088/gold/query?table=dim_cliente&columns=nombre,email&condition=segmento=retail"
```

### Postman

1. Método **GET**
2. URL: `http://localhost:8088/gold/query`
3. Params: `table`, `columns`, `condition`, `limit`
4. Send → JSON `{ ok, table, row_count, rows, sql_preview }`

En AWS real la URL sería `https://<alb-dns>/gold/query` (TLS en el ALB).

---

## Paso 4 — Verificar least privilege

```powershell
# api_reader puede SELECT gold; no bronce
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c `
  "SELECT has_table_privilege('api_reader','gold.dim_cliente','SELECT') AS gold_sel,
          has_table_privilege('api_reader','bronce.erp_clientes','SELECT') AS bronce_sel;"
# Esperado: gold_sel=t  bronce_sel=f
```

Intentar `table=erp_clientes` o tabla fuera de allowlist → **400** desde la API.

```powershell
curl.exe "http://localhost:8088/gold/query?table=erp_clientes&limit=1"
# Esperado: error de validación / 400 (no SQL a bronce)
```

---

## Paso 5 — CloudWatch Logs → MinIO (S3 del lake)

La función ya escribe en **CloudWatch Logs** vía `execution_policy.json` (`logs:CreateLogGroup/Stream`, `PutLogEvents`). El handler hace `print` JSON de cada request/response (`gold_query_request` / `gold_query_response`).

```text
Invoke / ALB GET
      │
      ▼
Lambda  ──print──►  CloudWatch Logs   /aws/lambda/tp-gold-api   (LocalStack :4566)
                          │
                          │  export (demo)
                          ▼
                   MinIO S3   s3://backup-data-lake/logs/lambda/tp-gold-api/*.jsonl
```

**Qué hace el demo:** lee los eventos del log group y sube un JSONL a MinIO (`step_export_logs_to_s3`).  
**Por qué no CreateExportTask/Firehose acá:** en Hobby el camino fiable es get-log-events → PutObject.  
**En AWS real:** subscription filter → Kinesis Firehose → S3, o `CreateExportTask` a un bucket de logs.

Automatizado al final de `python lambda/lambda_demo.py` (salvo `--skip-logs-export`).

Ver logs en LocalStack:

```powershell
$stream = (awslocal logs describe-log-streams `
  --log-group-name /aws/lambda/tp-gold-api `
  --order-by LastEventTime --descending --max-items 1 `
  --query "logStreams[0].logStreamName" --output text).Trim().Split("`n")[0]
awslocal logs get-log-events --log-group-name /aws/lambda/tp-gold-api `
  --log-stream-name $stream --query "events[].message" --output text
```

Ver export en MinIO:

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
aws --endpoint-url http://localhost:9000 s3 ls s3://backup-data-lake/logs/lambda/tp-gold-api/ --recursive
# opcional: bajar el último .jsonl y mirar gold_query_request / REPORT
```

Solo re-exportar (después de haber invocado):

```powershell
python lambda/lambda_demo.py --logs-export-only
```

> Relación con lab 14: ahí aprendés a **leer** REPORT/cold start. Acá cerrás el circuito **persistir** esos logs en el data lake (backup).

---

## Checkpoint

- [ ] `api-role` + policies execution/secrets
- [ ] Grupo `bi-api` (y policy en `bi-ops`) sin secretos DB
- [ ] Lambda `tp-gold-api` con VpcConfig compute + `sg-api`
- [ ] ALB stand-in `:8088` /health OK
- [ ] Postman GET (o curl) devuelve filas de `gold.*`
- [ ] Pedido fuera de allowlist → 400
- [ ] Log group `/aws/lambda/tp-gold-api` con eventos `gold_query_*`
- [ ] Objeto en `s3://backup-data-lake/logs/lambda/tp-gold-api/` (MinIO)
- [ ] Claro: Hobby stand-in ≠ ALB real; mismo diseño de subnets/SG
- [ ] Claro: trust ≠ permissions ≠ quién puede Invoke
- [ ] Claro: CW Logs (LocalStack) ≠ bucket lake (MinIO)

---

## Entregable — evidencia mínima

1. Salida de `get-function-configuration` (anatomía + VpcConfig).
2. Un GET exitoso a `/gold/query` (Postman screenshot o curl + JSON).
3. Evidencia de rechazo (tabla no allowlist / bronce) → 400.
4. Evidencia SQL: `gold_sel=t`, `bronce_sel=f` para `api_reader`.
5. Evidencia de logs: fragmento CW **o** listado/contenido del JSONL en MinIO.
6. Tres líneas de cierre:
   - ¿Qué pieza del least privilege te parece más crítica (IAM rol, grupo BI, o SQL `api_reader`)?
   - ¿Qué cambiaría al pasar del stand-in `:8088` a un ALB real `:443`?
   - ¿En AWS real exportarías logs con Firehose, Export Task, o escritura directa a S3 — y por qué?

### Criterios de corrección

| # | Criterio | Peso |
|---|---|---|
| 1 | Lambda desplegada con rol/secret correctos y VpcConfig de compute | 20% |
| 2 | Entrada vía ALB stand-in responde GET gold | 20% |
| 3 | Least privilege demostrado (BI sin secrets; API sin bronce; 400 fuera de allowlist) | 25% |
| 4 | CloudWatch Logs + export a MinIO evidenciado | 15% |
| 5 | Explicación trust vs permissions vs invoke + frontera Hobby/AWS | 10% |
| 6 | Checkpoint completo / cleanup si aplica | 10% |

---

## Limpieza

```powershell
python lambda/lambda_demo.py --cleanup
# o bajar solo el stand-in:
# docker compose -f lambda/docker-compose.alb.yaml down
```

> Serverless también deja basura si no la limpiás: funciones, roles, log groups y el contenedor ALB stand-in.

---

## Archivos

| Archivo | Rol |
|---|---|
| `lab-api-tp.md` | Esta guía |
| `lambda_demo.py` | Script de ejecución (pasos 1–5, incl. export logs) |
| `handler.py` / `query_gold.py` | Código Lambda (+ audit `print` a CW) |
| `trust_lambda.json`, `execution_policy.json`, `task_api_policy.json` | IAM rol (logs + secret) |
| `group_bi_api_policy.json` | IAM grupo consumidores |
| `docker-compose.alb.yaml` + `alb_standin/` | ALB Hobby |

---

## Límites del entorno

| Qué sí | Qué no (acá) |
|---|---|
| Lambda en LocalStack + VpcConfig como **modelo** de diseño | Enforcement de red igual que AWS (ENI/SG end-to-end en Hobby) |
| Secret `dw/rds-api` en MiniStack + Postgres real | ELBv2 / ALB HTTPS real (usar stand-in `:8088`) |
| Allowlist + `api_reader` como control de datos | Cold start / costo GB-s → eso es **lab 14** (`lambda_lab/`) |
| Grupo `bi-api` como modelo de quién invoca | Resource-based policy avanzada / IAM Identity Center |
| CW Logs en LocalStack + export JSONL a MinIO | Firehose / CreateExportTask end-to-end como en AWS |

Los tiempos absolutos de invoke **no** son representativos de AWS. El diseño de capas (pública → privada → RDS), least privilege y **persistencia de logs en el lake** **sí** son el aprendizaje de este lab.

---

## Relación con labs

| Lab | Aporte |
|---|---|
| 04 IAM | Grupos bi-ops / bi-admin |
| 07-v2 | Subnets + sg-alb / sg-api / sg-rds |
| 08-tp | `dw/rds-api` + `api_reader` |
| 14 (`lambda_lab/`) | Cold start, REPORT, costo — alcance distinto |
| extra + 09b `--erp` | Datos en gold para consultar |
| **api (este)** | Exponer gold por GET controlado |

---

## Referencias

- Lambda execution role: https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html
- Lambda en VPC: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html
- Application Load Balancer + Lambda: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/lambda-functions.html
- LocalStack Lambda: https://docs.localstack.cloud/aws/services/lambda/
- CloudWatch Logs: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html
- Export logs to S3: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/S3Export.html
- Lab 14 (cold start / costo): [`../lambda_lab/lab-14.md`](../lambda_lab/lab-14.md)
