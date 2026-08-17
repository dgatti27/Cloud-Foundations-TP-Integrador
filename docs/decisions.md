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
- (−) En Windows/OneDrive, `tofu` en el host a veces falla al cargar providers → conviene la imagen toolbox `tp-integrador-iac` (perfil Compose `iac`).

**Resultado:** `docker compose up -d` + `cd infra && tofu apply` (o `docker compose --profile iac run --rm tp-iac apply`). Budget AWS solo cuando `create_budget=true` en cuenta real. Estimación siempre local (`python labs/finops/pricing.py`). Bajar limpio: decisión 011.

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

**Resultado:** `ecs_mode = hobby-standin`. `apps/airflow/` ≈ EFS. IaC solo en `infra/`. `create_budget=false` por defecto. Orquestación ETL: UI Airflow o atajo opcional `labs/ecs/ecs.py --skip-infra --erp`.

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

**Resultado:** única fuente IaC: `cd infra && tofu apply` (o toolbox `tp-iac`).

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

**Resultado:** baseline **275,78 OD / 262,26 SP** → entra en 300 (92% / 87%). Detalle en [`finops.md`](finops.md). Gateway VPCE S3 ya en el diseño (0 USD); NAT se mantiene para orígenes on-host. Inventario IaC: `infra/generated/finops_inventory.json` con `filename` bajo `path.root` (evita replace cosmético por `modules/finops/../../…` entre apply/plan).

---

### 006 — Zip Lambda con `pg8000` vendorizado (sin pip en el apply)

**Decision:** el zip de `tp-gold-api` incluye `handler.py`, `query_gold.py` y `apps/api/vendor/` (`pg8000` + deps transitivas **commiteadas**). No se corre `pip` en cada `tofu plan`/`apply`.

**Contexto:** incluir el driver vía `pip` en `local-exec` rompía idempotencia (hash del zip / mtimes) y alargaba el apply en Windows. El zip lite sin driver devolvía `500 No module named 'pg8000'` en `GET /gold/query`.

**Alternativas:**

1. `pip` + layer/zip en cada apply.  
2. **Vendor `pg8000` (+ deps) en `apps/api/vendor/`** (elegida).  
3. Zip lite sin driver (rechazada: bloquea consultas gold).

**Tradeoff:**

- (+) Apply Hobby estable e idempotente.  
- (+) `GET /gold/query` puede hablar con RDS (`api_reader`).  
- (−) Vendor ocupa espacio en el repo; hay que actualizarlo a mano si sube la versión.  
- (−) CI/lint no debe escanear `vendor/` (ruido F821 en libs de terceros).

**Resultado:** `infra/modules/lambda` zippea `source_dir` de `apps/api` (excluye `alb_standin`). Rebuild: `pip install -r apps/api/requirements.txt -t apps/api/vendor`. Ruff en GitHub Actions usa `--exclude apps/api/vendor`.

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

**Decision:** Postgres “RDS” del TP es **MiniStack** (`:4567` API, container `ministack-rds-*-tp-dw-db`). El puerto **publicado en el host** no está fijo en 15432: MiniStack puede usar 15433 / 15434, etc.

**Contexto:** Airflow (Compose), Lambda y pgAdmin en el host usan `host.docker.internal` + puerto override. El secret guarda el IP interno Docker `:5432`. Si el override queda en 15432 y MiniStack publicó otro, DAGs/API fallan al conectar.

**Alternativas:**

1. Forzar siempre `-p 15432:5432` (MiniStack no lo garantiza).  
2. Descubrir el puerto en cada apply (frágil en plan).  
3. **Default 15432 + override explícito** en dos capas (elegida):  
   - IaC / Lambda: `rds_port_override` (`TF_VAR_…` / `infra/terraform.tfvars`)  
   - Runtime Airflow: `RDS_PORT_OVERRIDE` en `.env` → `compose.yaml`

**Tradeoff:**

- (+) Seed `post_rds.py` usa `docker exec` (no depende del puerto host).  
- (−) Hay que alinear `.env` + `terraform.tfvars` tras recrear la RDS.  
- No bloquea el apply ni el health de ALB.

**Resultado:** chequear con `docker ps --filter name=ministack-rds`. README §6.4 / troubleshooting. Query gold OK con vendor `pg8000` (decisión 006) cuando el puerto coincide.

---

### 009 — pgAdmin: email con TLD válido

**Decision:** usuario pgAdmin **`admin@example.com`** (no `@tp.local`). Contenedor pgAdmin corre como `root` solo para preparar `pgpass` (`chown 5050`).

**Contexto:** pgAdmin 8 rechaza `.local` (`CHECK_EMAIL_DELIVERABILITY` / validador). La imagen no-root no puede `chown` el pgpass copiado.

**Alternativas:** dominio inventado `.local` (fallaba) vs TLD reservado de documentación (`example.com`).

**Tradeoff:** email de entorno local, no de producción. Login simple para el TP.

**Resultado:** Compose + `.env.example` + README. **Ajuste aplicado** tras el smoke test (era el único blocker de UI).

---

### 010 — Gold acotado al TP (6 dims + 2 facts)

**Decision:** schema `gold` con **6 dimensiones** y **2 hechos**, no un Modelo_DW de 19 tablas. Paquete ETL en **`apps/pipeline/`** (no `apps/etl`).

**Contexto:** el entregable demuestra ERP → bronce → gold → API. Un modelo completo diluye el TP.

**Modelo:**
- Dims: `dim_fecha`, `dim_cliente`, `dim_producto`, `dim_canal`, `dim_metodo_pago`, `dim_moneda`
- Facts: `fact_venta_linea` (carga el ETL), `fact_venta_devolucion` (creada, carga opcional)
- Geo y categoría embebidas en cliente/producto

**Resultado:** `data/rds/seed_tp.sql` + `apps/pipeline/transform/to_gold.py` + allowlist en `apps/api/query_gold.py`. Tests: `pytest` bajo `apps/pipeline/tests/` (mock, sin DB).

---

### 011 — Cleanup Hobby: destroy IaC + wipe de volúmenes

**Decision:** bajar el entorno local con **`scripts/cleanup-hobby(.ps1|.sh)`** (o equivalente manual), no solo `tofu destroy`. Secrets Hobby con **`recovery_window_in_days = 0`**.

**Contexto:** `tofu destroy` limpia state/API, pero persisten volúmenes Docker (`localstack-data`, `ministack-data`, `minio-data`, `ministack-rds-*-data`). Eso generaba ghosts: secrets soft-deleted (`ResourceExistsException` con lista vacía), IAM/S3 huérfanos y schema RDS viejo (p. ej. falta `pais` en `dim_cliente`).

**Alternativas:**

1. Solo `tofu destroy` + `compose down` (insuficiente).  
2. `compose down -v` a ciegas (borra también ERP/Airflow DB sin destroy ordenado).  
3. **Script de cleanup (destroy + sidecars RDS + wipe emuladores)** + soft-delete inmediato de secrets (elegida).

**Tradeoff:**

- (+) Próximo `compose up` + `tofu apply` parte limpio.  
- (+) `-Full` / `--full` opcional para resetear también postgres/redis/pgAdmin.  
- (−) Es **manual** (no se dispara solo al destroy); documentado en README §9.

**Resultado:** [`scripts/cleanup-hobby.ps1`](../scripts/cleanup-hobby.ps1) / [`.sh`](../scripts/cleanup-hobby.sh); secrets en `infra/modules/secrets`. Arranque limpio: Compose → apply → DAGs → Postman.
