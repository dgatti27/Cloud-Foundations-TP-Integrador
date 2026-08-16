# Paquete `pipeline`

Lógica de negocio del DW, **separada de la orquestación** (DAGs en `apps/airflow/dags/`).

Esquemas generales del TP: [README raíz — Datos](../../README.md#datos-esquemas-y-procesamiento).

---

## Flujo completo: PostgreSQL ERP → gold

Camino B del TP. Dos DAGs en serie; cada uno llama funciones de este paquete.

```text
postgres-erp                    RDS MiniStack (db dw)
─────────────                   ─────────────────────
"Clientes"                      schema bronce
"Productos"  ── DAG grupo 1 ──►  erp_clientes
"Ventas"        etl_erp_to_bronce  erp_productos
                                  erp_ventas
                                       │
                                       │  DAG grupo 2
                                       │  etl_bronce_to_gold
                                       ▼
                                  schema gold
                                    dim_fecha
                                    dim_cliente
                                    dim_producto
                                    dim_canal
                                    dim_metodo_pago
                                    dim_moneda
                                    fact_venta_linea
```

### Antes de arrancar (preparación)

| Paso | Qué | Dónde |
|---|---|---|
| 0a | Semilla del origen (`Clientes` / `Productos` / `Ventas`) | `erp/seed_erp.sql` (Compose o `pipeline_demo.py`) |
| 0b | Secret `dw/erp` con host `postgres-erp` | MiniStack ← `pipeline_demo.py` |
| 0c | Secret `dw/rds-etl` (`etl_writer`) + schemas bronce/gold | IaC + `data/rds/seed_tp.sql` |
| 0d | Airflow con `PYTHONPATH` → paquete `pipeline` | Compose monta `./apps/pipeline` |

```powershell
python apps/pipeline/pipeline_demo.py
python labs/ecs/ecs.py --skip-infra --erp
```

Luego, en Airflow UI (orden obligatorio):

1. Trigger **`etl_erp_to_bronce`**
2. Cuando termine OK → trigger **`etl_bronce_to_gold`**

---

### Grupo 1 — DAG `etl_erp_to_bronce`

Origen: Postgres ERP → landing en `bronce.erp_*`.

| # | Task Airflow | Función del paquete | Qué pasa |
|---|---|---|---|
| 1 | `ensure_bronce_ddl` | `load.to_cruda.ensure_bronce_erp_ddl` | Aplica `sql/bronce_erp_ddl.sql` (`CREATE TABLE IF NOT EXISTS` de `ingest_batch` + `erp_*`). Credencial: `dw/rds-etl`. |
| 2 | `extract_erp` | `extract.erp_foxpro.extract_erp_all` | Abre `dw/erp`, hace `SELECT *` de `"Clientes"`, `"Productos"`, `"Ventas"`. Devuelve un dict `{clientes, productos, ventas}` en memoria. El DAG lo guarda en XCom (`erp_raw`). |
| 3 | `transform_normalize` | `transform.normalize.normalize_erp_bundle` | Limpieza ligera: `strip` en strings, metadatos `_tabla` / `_origen`. **No** modela el DW todavía. XCom: `erp_clean`. |
| 4 | `load_bronce` | `load.to_cruda.load_erp_to_bronce` | Inserta fila en `bronce.ingest_batch` → obtiene `batch_id` → UPSERT a `bronce.erp_clientes`, `erp_productos`, `erp_ventas` (`ON CONFLICT` por PK). |

**Resultado del grupo 1:** datos del ERP copiados de forma columnar en el schema `bronce` de la RDS, con trazabilidad por `batch_id`.

---

### Grupo 2 — DAG `etl_bronce_to_gold`

Origen: landing bronce → modelo dimensional `gold`.

| # | Task Airflow | Función del paquete | Qué pasa |
|---|---|---|---|
| 1 | `extract_bronce` | `extract.from_bronce.extract_bronce_all` | Lee `bronce.erp_clientes`, `erp_productos`, `erp_ventas` con `dw/rds-etl`. XCom: `bronce_raw`. |
| 2 | `transform_to_gold` | `transform.to_gold.transform_to_gold` | Mapea filas a dims/fact: cliente/producto (geo y rubro embebidos); de cada venta deriva `dim_fecha`, `dim_canal`, `dim_metodo_pago`, `dim_moneda` y arma `fact_venta_linea` (SKs ≈ IDs ERP). XCom: `gold_bundle`. |
| 3 | `load_gold` | `load.to_dw.load_gold_bundle` | UPSERT en orden: dims de apoyo → maestros → `fact_venta_linea` (tablas ya creadas por el seed RDS). |

**Resultado del grupo 2:** el DW consultable por la API (`gold.*`) queda cargado.

---

### Resumen de datos en cada capa

| Capa | Dónde | Contenido |
|---|---|---|
| Origen | `postgres-erp` / DB `erp` | Tablas operativas `"Clientes"`, `"Productos"`, `"Ventas"` |
| Bronce | RDS `dw` / schema `bronce` | Landing + `ingest_batch` (casi 1:1 con el ERP) |
| Gold | RDS `dw` / schema `gold` | 6 dims + `fact_venta_linea` |

Credenciales usadas en el camino:

| Secret | Usado por | Rol |
|---|---|---|
| `dw/erp` | extract ERP (grupo 1) | Lectura del origen |
| `dw/rds-etl` | load bronce, extract bronce, load gold | Escritura/lectura del DW (`etl_writer`) |

---

## Qué hace cada pieza del paquete

| Pieza | Rol |
|---|---|
| [`__init__.py`](./__init__.py) | Marca el paquete; resume extract → transform → load |
| [`config.py`](./config.py) | Resuelve credenciales (env / Secrets Manager) |
| [`db.py`](./db.py) | `connect` + `fetch_dicts` (psycopg2) |
| [`pipeline_demo.py`](./pipeline_demo.py) | Solo preparación: ERP + secret (no corre el ETL) |
| [`erp/seed_erp.sql`](./erp/seed_erp.sql) | Semilla del origen Compose |
| [`extract/erp_foxpro.py`](./extract/erp_foxpro.py) | Grupo 1: lee ERP → memoria |
| [`extract/from_bronce.py`](./extract/from_bronce.py) | Grupo 2: lee `bronce.erp_*` |
| [`transform/normalize.py`](./transform/normalize.py) | Grupo 1: limpieza ligera |
| [`transform/to_gold.py`](./transform/to_gold.py) | Grupo 2: modelo dimensional |
| [`load/to_cruda.py`](./load/to_cruda.py) | Grupo 1: DDL + UPSERT bronce |
| [`load/to_dw.py`](./load/to_dw.py) | Grupo 2: UPSERT gold |
| [`sql/bronce_erp_ddl.sql`](./sql/bronce_erp_ddl.sql) | DDL de las tablas landing |

Los comentarios detallados por sección están **dentro de cada archivo**.
