# Lab extra TP — ERP → Bronce → Gold (ETL real)

Extiende el arco **08-tp (RDS) + 09b (Airflow)** con un origen ERP de verdad y
los dos grupos de ETL del to-be:

| Grupo | Flujo | DAG | Código |
|---|---|---|---|
| **1** | ERP Postgres → schema `bronce` | `etl_erp_to_bronce` | `extract` → `transform.normalize` → `load.to_cruda` |
| **2** | `bronce` → schema `gold` | `etl_bronce_to_gold` | `extract.from_bronce` → `transform.to_gold` → `load.to_dw` |

```text
postgres-erp (Clientes / Productos / Ventas)
        │  DAG etl_erp_to_bronce
        ▼
RDS MiniStack  schema bronce  (erp_clientes / erp_productos / erp_ventas)
        │  DAG etl_bronce_to_gold
        ▼
RDS MiniStack  schema gold    (dim_* + fact_venta_linea)
```

> **Por qué este lab**  
> El DAG demo de 09b (`etl_bronce_origen_demo`) solo prueba conectividad.  
> Acá el paquete `etl/` deja de ser stub: extract/transform/load reales,
> tablas con ≥10 columnas y ≥10 filas, y carga dimensional al Modelo_DW.

---

## Prerequisitos

```powershell
# Labs previos
# 04 IAM · 07-v2 VPC · 08-tp RDS (dw + dw/rds-etl) · 09b Airflow (opcional pero recomendado)

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

aws --endpoint-url http://localhost:4567 secretsmanager describe-secret `
  --secret-id dw/rds-etl --query "Name" --output text
```

---

## Paso 1 — Levantar Postgres ERP en Docker

**Qué:** servicio `postgres-erp` con DB `erp` y tablas `Clientes`, `Productos`, `Ventas`.  
**Por qué:** simula el origen on-prem / VPC del to-be (Solution §5 — ETL grupo 1 por host).

El seed vive en [`erp/seed_erp.sql`](./erp/seed_erp.sql) (≥10 campos y ≥12 filas por tabla).
Se monta en `docker-entrypoint-initdb.d` (solo corre en el **primer** arranque del volumen).

```powershell
# Desde la raíz del repo
docker compose up -d postgres-erp

# Health
docker exec postgres-erp pg_isready -U postgres -d erp

# Contar filas
docker exec -i postgres-erp psql -U postgres -d erp -c `
  "SELECT 'Clientes' t, count(*) FROM \"Clientes\" UNION ALL
   SELECT 'Productos', count(*) FROM \"Productos\" UNION ALL
   SELECT 'Ventas', count(*) FROM \"Ventas\";"
```

| Host (desde Airflow) | Host (desde tu PC) | User / pass / DB |
|---|---|---|
| `postgres-erp:5432` | `localhost:5434` | `postgres` / `postgres` / `erp` |

Si el volumen ya existía vacío:  
`docker compose down` **sin** `-v`, borrá solo el volumen ERP, o aplicá el seed a mano:

```powershell
Get-Content etl\erp\seed_erp.sql -Raw | docker exec -i postgres-erp psql -U postgres -d erp
```

---

## Paso 2 — Secret `dw/erp` + Airflow con paquete `etl/`

**Qué:** publicar credenciales del ERP en MiniStack y recrear Airflow montando `etl/`.  
**Por qué:** el DAG no hardcodea passwords; usa el mismo patrón que Fargate + Secrets Manager.

```powershell
# JSON válido (evitar ConvertTo-Json en PowerShell — rompe comillas)
$tmp = "$PWD\etl\_erp_secret.json"
[System.IO.File]::WriteAllText(
  $tmp,
  '{"host":"postgres-erp","port":5432,"dbname":"erp","username":"postgres","password":"postgres","engine":"postgres"}'
)
aws --endpoint-url http://localhost:4567 secretsmanager create-secret `
  --name dw/erp --secret-string "file://$tmp" 2>$null
aws --endpoint-url http://localhost:4567 secretsmanager put-secret-value `
  --secret-id dw/erp --secret-string "file://$tmp"
Remove-Item $tmp -Force

# Recrear Airflow para tomar PYTHONPATH + volumen ../etl
cd ecs
docker compose -f docker-compose.airflow.yaml up -d --force-recreate
# UI http://localhost:8080  admin / admin
```

Variables relevantes en [`../ecs/docker-compose.airflow.yaml`](../ecs/docker-compose.airflow.yaml):

| Env | Valor | Uso |
|---|---|---|
| `PYTHONPATH` | `/opt/airflow/packages` | Importa `etl.*` |
| `ERP_SECRET` | `dw/erp` | Extract grupo 1 |
| `RDS_ETL_SECRET` | `dw/rds-etl` | Load bronce / gold |
| `SECRETS_ENDPOINT` | `http://ministack-integrador:4566` | MiniStack en red Docker |

---

## Paso 3 — DDL de tablas ERP en schema `bronce`

**Qué:** crear `bronce.erp_clientes`, `bronce.erp_productos`, `bronce.erp_ventas` si no existen.  
**Por qué:** el lab 08-tp solo deja `ingest_batch` / `raw_record`. El landing estructurado es de este lab.

SQL: [`sql/bronce_erp_ddl.sql`](./sql/bronce_erp_ddl.sql).

Se aplica solo:

```powershell
# Opción A — el DAG lo hace en la task ensure_bronce_ddl
# Opción B — a mano (como dwadmin)
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
Get-Content etl\sql\bronce_erp_ddl.sql -Raw | docker exec -i $c psql -U dwadmin -d dw
```

O desde Python (misma ruta que el DAG):

```powershell
$env:SECRETS_ENDPOINT = "http://localhost:4567"
$env:RDS_HOST_OVERRIDE = "localhost"
$env:RDS_PORT_OVERRIDE = "15432"
python -c "from etl.load.to_cruda import ensure_bronce_erp_ddl; ensure_bronce_erp_ddl()"
```

---

## Paso 4 — Adaptación del paquete `etl/` (grupo 1)

| Módulo | Rol |
|---|---|
| [`extract/erp_foxpro.py`](./extract/erp_foxpro.py) | `SELECT` a `Clientes` / `Productos` / `Ventas` vía `dw/erp` |
| [`transform/normalize.py`](./transform/normalize.py) | `normalize_erp_*` — strip / metadatos (sin modelar DW) |
| [`load/to_cruda.py`](./load/to_cruda.py) | DDL + UPSERT → `bronce.erp_*` + `ingest_batch` |
| [`config.py`](./config.py) / [`db.py`](./db.py) | Secrets MiniStack + `psycopg2` |
| [`pipelines.py`](./pipelines.py) | Atajo `run_erp_to_bronce()` |

DAG: [`../ecs/efs-standin/dags/etl_erp_to_bronce.py`](../ecs/efs-standin/dags/etl_erp_to_bronce.py)

```text
ensure_bronce_ddl → extract_erp → transform_normalize → load_bronce
```

### Trigger

```powershell
docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_erp_to_bronce
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_erp_to_bronce
```

### Verificar bronce

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM bronce.erp_clientes;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM bronce.erp_productos;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT nro_orden, id_cliente, id_producto, importe_neto FROM bronce.erp_ventas LIMIT 5;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT * FROM bronce.ingest_batch WHERE origen='erp' ORDER BY batch_id DESC LIMIT 3;"
```

Esperado: ≥12 clientes/productos y ≥12 líneas de venta; `origen='erp'`.

---

## Paso 5 — DAG grupo 2: Bronce → Gold

**Qué:** leer staging, transformar al modelo dimensional y UPSERT en `gold`.  
**Por qué:** cierra el flujo Solution §4–5 (grupo 2 carga analytics; Lambda solo lee gold).

| Módulo | Rol |
|---|---|
| [`extract/from_bronce.py`](./extract/from_bronce.py) | Lee `bronce.erp_*` |
| [`transform/to_gold.py`](./transform/to_gold.py) | Arma `dim_cliente`, `dim_producto`, `fact_venta_linea`, dims de apoyo |
| [`load/to_dw.py`](./load/to_dw.py) | UPSERT en `gold.*` |
| [`pipelines.py`](./pipelines.py) | `run_bronce_to_gold()` |

DAG: [`../ecs/efs-standin/dags/etl_bronce_to_gold.py`](../ecs/efs-standin/dags/etl_bronce_to_gold.py)

```text
extract_bronce → transform_to_gold → load_gold
```

Mapeo principal:

| Bronce | Gold |
|---|---|
| `erp_clientes` | `dim_cliente` + `dim_geografia` |
| `erp_productos` | `dim_producto` + `dim_categoria` |
| `erp_ventas` | `fact_venta_linea` + `dim_fecha` / `dim_canal` / `dim_metodo_pago` / `dim_moneda` |

SKs del lab = IDs del ERP (simple y trazable). En producción usarías surrogates + SCD2 reales.

### Trigger

```powershell
docker exec ecs-airflow-scheduler-1 airflow dags unpause etl_bronce_to_gold
docker exec ecs-airflow-scheduler-1 airflow dags trigger etl_bronce_to_gold
```

### Verificar gold

```powershell
$c = (docker ps --filter "name=ministack-rds" --format "{{.Names}}" | Select-Object -First 1)
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM gold.dim_cliente;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT count(*) FROM gold.dim_producto;"
docker exec -i $c psql -U dwadmin -d dw -c "SELECT nro_orden, cliente_sk, producto_sk, importe_neto, margen_bruto FROM gold.fact_venta_linea ORDER BY venta_sk LIMIT 5;"
```

---

## Test sin Airflow (opcional)

```powershell
$env:SECRETS_ENDPOINT = "http://localhost:4567"
$env:RDS_HOST_OVERRIDE = "localhost"
$env:RDS_PORT_OVERRIDE = "15432"
$env:ERP_SECRET = "dw/erp"

# Ojo: desde el host el secret dw/erp apunta a host=postgres-erp (DNS Docker).
# Para probar extract en el host, override temporal:
python -c "
from etl.db import connect, fetch_dicts
import os
cfg={'host':'localhost','port':5434,'dbname':'erp','username':'postgres','password':'postgres'}
conn=connect(cfg)
print(fetch_dicts(conn, 'SELECT count(*) AS n FROM \"Clientes\"'))
conn.close()
"

python -c "from etl.pipelines import run_erp_to_bronce, run_bronce_to_gold; print('g1', run_erp_to_bronce()); print('g2', run_bronce_to_gold())"
```

> Si corrés el pipeline en el host, el secret `dw/erp` debe usar `"host":"localhost","port":5434`.  
> Dejá `postgres-erp:5432` para Airflow (red Docker) y usá el override solo en pruebas locales.

---

## Checkpoint

- [ ] `postgres-erp` up con ≥10 filas en Clientes / Productos / Ventas (≥10 cols)
- [ ] Secret `dw/erp` en MiniStack
- [ ] Tablas `bronce.erp_*` creadas (paso 3 / task DDL)
- [ ] DAG `etl_erp_to_bronce` success
- [ ] DAG `etl_bronce_to_gold` success
- [ ] Filas en `gold.dim_cliente`, `gold.dim_producto`, `gold.fact_venta_linea`
- [ ] Claro: orquestación en Airflow (09b); lógica en paquete `etl/`

---

## Archivos tocados

| Ruta | Rol |
|---|---|
| `etl/lab-extra-tp.md` | Esta guía |
| `etl/erp/seed_erp.sql` | Seed origen ERP |
| `etl/sql/bronce_erp_ddl.sql` | DDL landing bronce |
| `etl/extract/erp_foxpro.py` | Extract grupo 1 |
| `etl/extract/from_bronce.py` | Extract grupo 2 |
| `etl/transform/normalize.py` | Transform grupo 1 |
| `etl/transform/to_gold.py` | Transform grupo 2 |
| `etl/load/to_cruda.py` | Load → bronce |
| `etl/load/to_dw.py` | Load → gold |
| `etl/pipelines.py` | Pipelines invocables |
| `ecs/efs-standin/dags/etl_erp_to_bronce.py` | DAG grupo 1 |
| `ecs/efs-standin/dags/etl_bronce_to_gold.py` | DAG grupo 2 |
| `compose.yaml` | Servicio `postgres-erp` |
| `ecs/docker-compose.airflow.yaml` | Mount `etl/` + env secrets |

---

## Relación con labs / docs

| Fuente | Aporte |
|---|---|
| 08-tp | RDS `dw`, schemas `bronce`/`gold`, secret `dw/rds-etl` |
| 09b | Airflow stand-in + EFS dags/logs |
| Solution §4–5 | Grupo 1 → Bronce; grupo 2 → Gold; secrets + least privilege |
| `docs/Modelo_DW` (vía seed_tp) | Destino dimensional de `to_gold` / `to_dw` |
