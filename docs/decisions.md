# Decision log — justificaciones de la arquitectura to-be

Formato: **Decision / Contexto / Alternativas / Tradeoff / Resultado.**

Relacionado: [`finops.md`](finops.md) · [`Solution_Architecture.md`](Solution_Architecture.md) · [`Infraestructure_Architecture.md`](Infraestructure_Architecture.md).

---

### 001 — Soluciones locales emulando AWS

**Decision:** emular el to-be con **Docker Compose + LocalStack Hobby + MiniStack + MinIO + OpenTofu**, no con una cuenta AWS de desarrollo permanente.

**Contexto:** TP académico. Evitar costos accidentales (NAT/RDS 24/7), reducir fricción de setup (Windows + token Hobby) y poder destruir/recrear sin factura.

**Alternativas:**

1. Cuenta AWS real para todo el ciclo.  
2. Solo scripts Python/boto3 contra emuladores (sin IaC).  
3. **Emuladores + un solo árbol IaC** (elegida).

**Tradeoff:**

- (+) Costo AWS del entorno local ≈ **USD 0**; el to-be se **estima** (FinOps) en **275,78 USD/mes** OD.  
- (+) Reproduce IAM, VPC, S3, RDS, Secrets, Lambda, logs.  
- (−) Hobby **no** trae ECS, EFS, ELBv2 ni Budgets → hay que *stand-inear* (decisión 003).  
- (−) Tres backends (4566 / 4567 / 9000): hay que no mezclar endpoints.

**Resultado:** `docker compose up -d` + `cd infra && tofu apply`. Budget AWS solo cuando `create_budget=true` en cuenta real. Estimación siempre local (`python labs/finops/pricing.py`).

---

### 002 — MinIO como object storage local (no LocalStack S3)

**Decision:** usar **MinIO** (`s3-soporte`, `:9000` / consola `:9001`) como data lake / S3 del pipeline y del IaC de buckets. LocalStack queda para IAM, VPC, Lambda, Logs — **no** como storage del flujo.

**Contexto:** ambos hablan API S3, pero no son el mismo producto ni el mismo rol en este TP. Políticas IAM de AWS no se aplican 1:1 sobre MinIO.

**Alternativas:**

1. **Solo MinIO** para el lake (elegida).  
2. Solo LocalStack S3 para scripts + Terraform.  
3. Ambos activos como S3 a la vez (descartada: doble estado).

**Tradeoff:**

- MinIO es liviano, tiene consola, se siente a object storage de producto; no emula IAM/SQS/Lambda.  
- LocalStack imita mejor AWS end-to-end, pero es pesado si solo se sube/lista objetos.  
- Credenciales del CLI: **`minioadmin` / `minioadmin`**, no `test`/`test` (eso es LocalStack/MiniStack).  
- Policies avanzadas de MinIO → provider nativo `aminueza/minio` a futuro; el provider AWS alcanza para buckets + bucket policies básicas.

**Resultado:**

- Pipeline + IaC de buckets → MinIO (`infra` apunta a `:9000`).  
- LocalStack → IAM / EC2-VPC / Lambda / CloudWatch.  
- MiniStack → RDS + Secrets.  
- No mezclar los tres como destino S3 del mismo flujo.

---

### 003 — Stand-ins Hobby (ECS / EFS / ALB / Budgets)

**Decision:** modelar en IaC lo que Hobby sí soporta (IAM execution/task, SG, marcador EFS, Lambda, inventario FinOps) y **emular runtime** con Compose: Airflow ≈ Fargate+EFS, `alb-standin` `:8088` ≈ ALB, `pricing.py` ≈ Budgets.

**Contexto:** LocalStack Hobby no expone APIs `ecs`, `efs`, `elbv2` ni Budgets usable. El to-be del Solution §4–5 sí las usa.

**Alternativas:**

1. LocalStack Pro (paga) para ECS/EFS/ELB.  
2. No declarar nada de Fargate/ALB en el TP Hobby.  
3. **Híbrido IaC (modelo) + Compose (runtime)** (elegida).

**Tradeoff:**

- (+) Un `tofu apply` deja roles, secrets, RDS y Lambda iguales al to-be.  
- (+) Airflow y Postman funcionan en la notebook.  
- (−) `enable_ecs_api=false`: no hay cluster Fargate real.  
- (−) ALB stand-in no es ELB (ni WAF ni TLS terminado en AWS).  
- (−) FinOps no crea `aws_budgets_budget` hasta AWS real.

**Resultado:** `ecs_mode = hobby-standin`. `apps/airflow/` ≈ EFS. IaC solo en `infra/`. `create_budget=false` por defecto.

---

### 004 — Una sola raíz IaC (`infra/`)

**Decision:** consolidar todo el OpenTofu en [`infra/`](../infra/) + `infra/modules/{iam,vpc,s3,rds,secrets,lambda,ecs,cloudwatch,finops}`.

**Contexto:** varios árboles IaC en paralelo chocaban en nombres (`app-role`, `tp-dw-db`, buckets lake) → `EntityAlreadyExists` y pérdida de idempotencia.

**Alternativas:**

1. Un state por componente suelto.  
2. Workspaces / prefijos por componente.  
3. **Un state del TP** (elegida).

**Tradeoff:**

- (+) `tofu apply` idempotente sobre el producto.  
- (+) Policies y comentarios viven en los módulos.  
- (−) Demos Python (`ecs.py`, etc.) usan `--skip-infra` si el apply ya corrió.

**Resultado:** única fuente IaC: `cd infra && tofu apply`.

---

### 005 — FinOps: estimar local, Budget solo en AWS real

**Decision:** el costo del stack se calcula con `services.json` + `pricing.py` (100% local). El recurso `aws_budgets_budget` es **opt-in** (`create_budget=true` + email real).

**Contexto:** techo SMART ≤ **USD 300**/mes. Hobby no factura AWS; inventar un Budget contra LocalStack no aporta señal.

**Alternativas:**

1. Crear Budget siempre (falla o no-op en Hobby).  
2. Solo planilla Excel.  
3. **Estimador versionado en git + Budget en AWS real** (elegida).

**Tradeoff:**

- (+) Números reproducibles en CI (`pricing.py`).  
- (+) Alertas 80/100 cuando importen (cuenta AWS real).  
- (−) El inventario Hobby (`finops_inventory.json`) no es un control de gasto real.

**Resultado:** baseline **275,78 OD / 262,26 SP** → entra en 300 (92% / 87%). Detalle en [`finops.md`](finops.md). Gateway VPCE S3 ya en el diseño (0 USD); NAT se mantiene para orígenes on-host.

---

### 006 — Zip Lambda lite (sin `pg8000` en el apply Hobby)

**Decision:** el zip de `tp-gold-api` lleva solo `handler.py` + `query_gold.py`. No se corre `pip` en cada `tofu plan`/`apply`.

**Contexto:** incluir `pg8000` vía `pip install` en `local-exec` rompía idempotencia (hash del zip / mtimes) y alargaba el apply en Windows.

**Alternativas:**

1. `pip` + layer/zip en cada apply.  
2. Vendor `pg8000`+`scramp` commiteados en `apps/api/`.  
3. **Zip lite ahora** (elegida); driver cuando se pule la API/ETL.

**Tradeoff:**

- (+) Apply Hobby estable: Lambda **Active**, ALB `/health` OK.  
- (−) `GET /gold/query` → **500 `No module named 'pg8000'`** hasta empaquetar el driver.  
- (−) No es bloqueo de infra; sí de consulta gold (Qlik/Postman SQL).

**Resultado:** documentado en README §5.5 y [`finops.md`](finops.md) §3. No se considera crítico para “la infra levantó”. Se revisa junto con el ETL.

---

### 007 — NAT + Gateway endpoint S3 (no apagar NAT)

**Decision:** VPC con **NAT en public-alb-a** (`enable_nat=true`) **y** Gateway endpoint S3 (0 USD) en RT compute + RDS.

**Contexto:** Solution §5: ETL habla con orígenes **por host** (ERP/Mongo/scraping) y con S3/Secrets en AWS. NAT es caro y sin SP/Spot; el tráfico hacia S3 no debería pagarlo.

**Alternativas:**

1. Solo NAT (todo egress por NAT).  
2. Solo endpoints (rompe extract a Internet/on-prem).  
3. **NAT (orígenes) + VPCE Gateway S3** (elegida). Interface endpoints Secrets/ECR se evalúan aparte (~7,3 USD/AZ): hoy el ahorro de GB de NAT **no** los justifica.

**Tradeoff:**

- NAT base ≈ **32,85** + data 100 GB ≈ **4,50** → ~37 USD/mes (top-3 de costo).  
- Escenario endpoints (25 GB NAT): ahorra **~3,38** USD.  
- Apagar NAT rompería el extract on-host.

**Resultado:** modelo en `infra/modules/vpc`. Costo en [`finops.md`](finops.md) §2.1.

---

### 008 — RDS MiniStack + puerto host dinámico

**Decision:** Postgres “RDS” del TP es **MiniStack** (`:4567` API, container `ministack-rds-*-tp-dw-db`). El puerto **publicado en el host** no está fijo en 15432: MiniStack puede usar 15434, etc.

**Contexto:** Lambda/pgAdmin en el host usan `host.docker.internal` + `rds_port_override` (default 15432). El secret guarda el IP interno Docker `:5432`.

**Alternativas:**

1. Forzar siempre `-p 15432:5432` (MiniStack no lo garantiza).  
2. Descubrir el puerto en cada apply (frágil en plan).  
3. **Default 15432 + override explícito** `TF_VAR_rds_port_override` / `terraform.tfvars` (elegida).

**Tradeoff:**

- (+) Seed `post_rds.py` usa `docker exec` (no depende del puerto host).  
- (−) pgAdmin `servers.json` y el env de Lambda pueden quedar desfasados si MiniStack eligió otro puerto.  
- No bloquea el apply ni el health de ALB.

**Resultado:** chequear con `docker ps --filter name=ministack-rds`. No es crítico para el funcionamiento del IaC; sí para SQL desde el host / query gold cuando exista `pg8000`.

---

### 009 — pgAdmin: email con TLD válido

**Decision:** usuario pgAdmin **`admin@example.com`** (no `@tp.local`). Contenedor pgAdmin corre como `root` solo para preparar `pgpass` (`chown 5050`).

**Contexto:** pgAdmin 8 rechaza `.local` (`CHECK_EMAIL_DELIVERABILITY` / validador). La imagen no-root no puede `chown` el pgpass copiado.

**Alternativas:** dominio inventado `.local` (fallaba) vs TLD reservado de documentación (`example.com`).

**Tradeoff:** email de entorno local, no de producción. Login simple para el TP.

**Resultado:** Compose + `.env.example` + README. **Ajuste aplicado** tras el smoke test (era el único blocker de UI).

---

### 010 — Gold acotado al TP (6 dims + 2 facts)

**Decision:** schema `gold` con **6 dimensiones** y **2 hechos**, no un Modelo_DW de 19 tablas.

**Contexto:** el entregable demuestra ERP → bronce → gold → API. Un modelo completo diluye el TP.

**Modelo:**
- Dims: `dim_fecha`, `dim_cliente`, `dim_producto`, `dim_canal`, `dim_metodo_pago`, `dim_moneda`
- Facts: `fact_venta_linea` (carga el ETL), `fact_venta_devolucion` (creada, carga opcional)
- Geo y categoría embebidas en cliente/producto

**Resultado:** `data/rds/seed_tp.sql` + `apps/pipeline/transform/to_gold.py` + allowlist en `apps/api/query_gold.py`.
