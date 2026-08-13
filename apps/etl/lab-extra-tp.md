# Lab extra TP — Origen ERP + paquete `etl/` (lógica de negocio)

<!--
  Frontera de este lab vs lab 09b
  ────────────────────────────────
  ESTE LAB (etl/):  el ORIGEN y el CÓDIGO que transforma datos.
    - Postgres ERP (Clientes / Productos / Ventas)
    - Seed ficticio
    - Secret dw/erp (credencial del origen)
    - Módulos extract / transform / load (qué hace cada uno y por qué)

  LAB 09b (ecs/):   el ECOSISTEMA DE CÓMPUTO (stand-in Fargate + EFS).
    - IAM execution/task role, compose Airflow, efs-standin
    - DDL de tablas en schema bronce (landing)
    - Trigger de DAGs → bronce y → gold
    - Verificación en RDS MiniStack

  Por qué separar:
    En el to-be, el origen ERP vive fuera de AWS (o en otra VPC) y el código
    ETL es un artefacto versionado. ECS/Fargate solo ORQUESTA. Mezclar ambas
    cosas en un solo lab confunde “dato de origen” con “plataforma de cómputo”.
-->

Extiende el TP con un **origen ERP real** (Postgres en Docker) y el paquete
Python que los DAGs de Airflow importan. La ejecución en Airflow / DDL Bronce /
carga Gold está en [`../../labs/ecs/lab-09b-tp.md`](../../labs/ecs/lab-09b-tp.md).

```text
┌─ ESTE LAB (etl/) ─────────────────────┐     ┌─ LAB 09b (ecs/) ──────────────────┐
│  postgres-erp                         │     │  Airflow ≈ Fargate                 │
│  seed Clientes/Productos/Ventas       │────►│  DDL bronce.erp_*                   │
│  secret dw/erp                        │     │  DAG etl_erp_to_bronce → bronce    │
│  paquete extract/transform/load       │     │  DAG etl_bronce_to_gold → gold     │
└───────────────────────────────────────┘     └────────────────────────────────────┘
```

> **Por qué este lab**  
> Sin un origen con tablas y filas reales, el lab 09b solo puede demo de
> conectividad (`etl_bronce_origen_demo`). Acá nace el dataset ERP y el
> código reutilizable; 09b lo orquesta como haría ECS.

---

## Script de ejecución (recomendado)

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

python apps/etl/etl_demo.py
# Opcional (escribe RDS sin Airflow):
#   python apps/etl/etl_demo.py --with-pipelines
# Orquestación EFS/Airflow (lab 09b):
#   python ecs/ecs_demo.py --erp
```

`etl_demo.py` automatiza Pasos 1–2 (ERP + secret). Los DAGs viven en lab 09b.

---

## Paso 1 — Levantar Postgres ERP en Docker

<!--
  Qué: un Postgres dedicado llamado "ERP" con 3 tablas de negocio.
  Por qué: en Solution Architecture el grupo 1 lee orígenes por HOST (no API).
  El contenedor simula ese host on-prem / en VPC alcanzable vía NAT desde Fargate.
-->

**Qué hace:** crea el servicio `postgres-erp` (DB `erp`) e inicializa tablas.  
**Para qué:** tener un origen estable que Airflow (lab 09b) pueda consultar.  
**Por qué no va en 09b:** no es cómputo ECS; es el sistema fuente.

Seed: [`erp/seed_erp.sql`](./erp/seed_erp.sql) — ≥10 columnas y ≥12 filas por tabla.
Se monta en `docker-entrypoint-initdb.d` (solo en el **primer** arranque del volumen).

```powershell
# Desde la raíz del repo
docker compose up -d postgres-erp

# Health — ¿acepta conexiones?
docker exec postgres-erp pg_isready -U postgres -d erp

# Contar filas (PowerShell: pipe por stdin; -c con \" rompe las comillas)
@"
SELECT 'Clientes' t, count(*) FROM "Clientes"
UNION ALL SELECT 'Productos', count(*) FROM "Productos"
UNION ALL SELECT 'Ventas', count(*) FROM "Ventas";
"@ | docker exec -i postgres-erp psql -U postgres -d erp
# Esperado: Clientes 12 · Productos 12 · Ventas 13
```

| Contexto | Host:puerto | User / pass / DB |
|---|---|---|
| Desde Airflow (red Docker) | `postgres-erp:5432` | `postgres` / `postgres` / `erp` |
| Desde tu PC | `localhost:5434` | igual |

Si el volumen ya existía sin seed:

```powershell
Get-Content etl\erp\seed_erp.sql -Raw | docker exec -i postgres-erp psql -U postgres -d erp
```

### Tablas (qué representan)

| Tabla | Rol de negocio | Por qué ≥10 campos |
|---|---|---|
| `Clientes` | Maestro de clientes (identidad, geo, segmento) | Fuerza un extract “ancho” como en un ERP real |
| `Productos` | Catálogo (SKU, EAN, jerarquía, precios) | Alimenta dims de producto/categoría en gold |
| `Ventas` | Líneas de orden (hechos) | Grano de `fact_venta_linea` |

---

## Paso 2 — Secret `dw/erp` (credencial del origen)

<!--
  Qué: JSON en MiniStack Secrets Manager con host/user/password del ERP.
  Por qué: mismo patrón to-be (Fargate lee secrets; no hardcode en la imagen).
  Dónde se CONSUME: lab 09b (env ERP_SECRET en el compose Airflow).
-->

**Qué hace:** publica `dw/erp` en MiniStack (`:4567`).  
**Para qué:** que el extract del paquete `etl/` (y luego el DAG) obtenga la conexión sin passwords en el código.  
**Por qué en este lab:** el secreto describe el **origen**; 09b solo lo referencia.

```powershell
# JSON válido vía archivo (ConvertTo-Json en PowerShell suele romper comillas)
$tmp = "$PWD\etl\_erp_secret.json"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText(
  $tmp,
  '{"host":"postgres-erp","port":5432,"dbname":"erp","username":"postgres","password":"postgres","engine":"postgres"}',
  $utf8
)
aws --endpoint-url http://localhost:4567 secretsmanager create-secret `
  --name dw/erp --secret-string "file://$tmp" 2>$null
aws --endpoint-url http://localhost:4567 secretsmanager put-secret-value `
  --secret-id dw/erp --secret-string "file://$tmp"
Remove-Item $tmp -Force

# Solo Name — no imprimas SecretString
aws --endpoint-url http://localhost:4567 secretsmanager describe-secret `
  --secret-id dw/erp --query "Name" --output text
```

> `host=postgres-erp` es correcto **dentro de Docker**. Para pruebas del paquete
> desde el host usá `ORIGEN_ERP_CONN=postgresql://postgres:postgres@localhost:5434/erp`
> (ver Paso 4).

---

## Paso 3 — Paquete `etl/`: qué hace cada módulo y por qué

<!--
  La lógica vive FUERA de los DAGs a propósito:
  - testeable sin Airflow
  - misma librería en Fargate real
  - DAGs = orquestación fina (lab 09b)
-->

**Qué hace:** implementa extract → transform → load de los dos grupos ETL.  
**Para qué:** los DAGs de 09b solo importan y llaman; no duplican SQL/negocio.  
**Por qué dos grupos:** Solution §4–5 — grupo 1 aterriza crudo en Bronce; grupo 2 modela Gold.

### Grupo 1 — ERP → Bronce (landing)

| Módulo | Qué hace | Por qué |
|---|---|---|
| [`extract/erp_foxpro.py`](./extract/erp_foxpro.py) | `SELECT *` de Clientes/Productos/Ventas vía `dw/erp` | Nombre histórico “foxpro”; en el TP el origen es Postgres ERP |
| [`transform/normalize.py`](./transform/normalize.py) | Strip, metadatos `_origen` / `_tabla` | Limpieza ligera **sin** modelar el DW (eso es grupo 2) |
| [`load/to_cruda.py`](./load/to_cruda.py) | UPSERT a `bronce.erp_*` + `ingest_batch` | “Cruda” = schema bronce del lab 08; nombre legacy del paquete |
| [`config.py`](./config.py) / [`db.py`](./db.py) | Secrets + `psycopg2` | Un solo lugar para endpoints MiniStack / overrides RDS |

Pipeline atajo: [`pipelines.py`](./pipelines.py) → `run_erp_to_bronce()`  
(útil para test local; en producción lo dispara el DAG de 09b).

### Grupo 2 — Bronce → Gold (dimensional)

| Módulo | Qué hace | Por qué |
|---|---|---|
| [`extract/from_bronce.py`](./extract/from_bronce.py) | Lee `bronce.erp_*` con `dw/rds-etl` | El grupo 2 **no** vuelve al ERP; lee el landing |
| [`transform/to_gold.py`](./transform/to_gold.py) | Arma dims + `fact_venta_linea` | Mapeo al Modelo_DW (seed lab 08) |
| [`load/to_dw.py`](./load/to_dw.py) | UPSERT en `gold.*` | Cierra analytics; Lambda solo lee gold |

Pipeline atajo: `run_bronce_to_gold()`.

### Mapeo conceptual (lo ejecuta 09b)

| Bronce | Gold |
|---|---|
| `erp_clientes` | `dim_cliente` + `dim_geografia` |
| `erp_productos` | `dim_producto` + `dim_categoria` |
| `erp_ventas` | `fact_venta_linea` + dims fecha/canal/pago/moneda |

SKs del lab = IDs del ERP (trazable). En prod: surrogates + SCD2 reales.

---

## Paso 4 — Test del paquete **sin** Airflow (opcional)

<!--
  Qué: validar extract/load en tu máquina antes de meter orquestación.
  Por qué: fallos de SQL/secret se detectan más rápido que vía UI de Airflow.
  Importante: esto NO reemplaza el lab 09b; solo prueba la librería.
-->

**Qué hace:** corre los pipelines en proceso local.  
**Para qué:** debug del código `etl/` sin scheduler.  
**Por qué no alcanza:** no ejercita compose, EFS stand-in, IAM modelo ni DAGs.

```powershell
$env:SECRETS_ENDPOINT = "http://localhost:4567"
$env:RDS_HOST_OVERRIDE = "localhost"
$env:RDS_PORT_OVERRIDE = "15432"
# Desde el host no uses DNS postgres-erp; usá DSN local:
$env:ORIGEN_ERP_CONN = "postgresql://postgres:postgres@localhost:5434/erp"

python -c "from etl.pipelines import run_erp_to_bronce, run_bronce_to_gold; print('g1', run_erp_to_bronce()); print('g2', run_bronce_to_gold())"
```

> Si vas por el camino “oficial” del TP: **no hace falta este paso**.  
> Seguí en lab 09b (DDL + DAGs).

---

## Siguiente: lab 09b (ecosistema ECS + EFS)

Todo lo que sigue es **cómputo / orquestación** sobre el stand-in Fargate+EFS:

1. IAM + **EFS stand-in** (`ecs/efs-standin/{dags,logs}`) + Compose Airflow
2. Los DAGs `etl_erp_to_bronce` / `etl_bronce_to_gold` **viven en ese EFS** (no en `etl/`)
3. Mount del paquete `etl/` como librería (`PYTHONPATH`) + env secrets
4. **DDL** `bronce.erp_*` en la RDS
5. Trigger de los DAGs (Airflow los lee desde el mount EFS)
6. Verificar filas en bronce/gold **y** logs bajo `efs-standin/logs`

→ Abrí [`../../labs/ecs/lab-09b-tp.md`](../../labs/ecs/lab-09b-tp.md) (Pasos 5–7 del flujo ERP, anclados a EFS).

---

## Checkpoint (solo este lab)

- [ ] `postgres-erp` up; counts Clientes/Productos/Ventas OK
- [ ] Secret `dw/erp` existe en MiniStack
- [ ] Entendés qué hace cada módulo de `extract` / `transform` / `load` y por qué hay dos grupos
- [ ] Claro: **origen + código acá; Airflow/DDL/DAGs en 09b**

---

## Archivos de este lab

| Ruta | Rol | Por qué está acá |
|---|---|---|
| `lab-extra-tp.md` | Esta guía | Origen + lógica |
| `etl_demo.py` | Script de ejecución | ERP + secret (+ pipelines opcionales) |
| `erp/seed_erp.sql` | Datos ERP | Pertenece al origen |
| `extract/*.py`, `transform/*.py`, `load/*.py` | Código ETL | Artefacto de negocio |
| `pipelines.py`, `config.py`, `db.py` | Glue del paquete | Sin orquestador |
| `sql/bronce_erp_ddl.sql` | DDL landing | **Archivo vive en etl/** (SQL de datos); **se aplica en lab 09b** |
| `compose.yaml` → `postgres-erp` | Contenedor origen | No es Fargate |

DAGs y compose Airflow: ver carpeta `ecs/`.

---

## Relación con labs / docs

| Fuente | Aporte |
|---|---|
| Solution §4–5 | Grupo 1 (origen→Bronce) y grupo 2 (Bronce→Gold) |
| 08-tp | Destino RDS `dw` (schemas ya creados) |
| **09b** | Orquesta este paquete en el stand-in ECS |
| Modelo_DW (seed_tp) | Forma de las tablas gold que escribe `to_gold` / `to_dw` |
