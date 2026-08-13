# FinOps — costo de esta infra y observaciones de smoke test

**Presupuesto objetivo (to-be AWS):** USD **300**/mes · alerta Budgets 80% ACTUAL + 100% FORECASTED  
**Región:** `us-east-1`  
**Fecha de estimación:** 13 ago 2026 (smoke test local + `pricing.py`)  
**Herramienta:** `python labs/finops/pricing.py --budget 300`  
**Inventario IaC:** `infra/generated/finops_inventory.json` (`create_budget=false` en Hobby)

Este documento cubre dos planos que no hay que mezclar:

| Plano | Qué factura | Costo |
|-------|-------------|------:|
| **Hobby (lo que corre hoy)** | Docker Desktop + LocalStack Hobby + MiniStack + MinIO + Compose | **USD 0 en AWS** (solo CPU/RAM/disco del host) |
| **To-be AWS real** | RDS Multi-AZ, Fargate, NAT, ALB, Lambda, S3, EFS, Secrets, CloudWatch | **USD 275,78**/mes on-demand |

El techo SMART del TP (≤ 300) aplica al **to-be**, no al emulador.

Workbook de estimación: [`labs/finops/estimate.md`](../labs/finops/estimate.md).  
Decisiones: [`decisions.md`](decisions.md).  
Arquitectura §7: [`Solution_Architecture.md`](Solution_Architecture.md).

---

## 1. Costo to-be (esta infra, AWS real)

Baseline: [`labs/finops/services.json`](../labs/finops/services.json) — alineado a `infra/modules/*`.

### 1.1 On-demand (precio de lista)

| Servicio | Tipo | Uso | USD/mes | % del total |
|----------|------|----:|--------:|------------:|
| RDS PostgreSQL db.t3.medium Multi-AZ | db | 730 h | **105,12** | 38,1% |
| ECS Fargate Airflow (~1,25 vCPU + 2,5 GB 24/7) | compute | 730 h | **45,04** | 16,3% |
| NAT Gateway (base) | network | 730 h | **32,85** | 11,9% |
| RDS storage gp3 250 GB | storage | 250 GB | **28,75** | 10,4% |
| ALB (base 730 h) | network | 730 h | **16,43** | 6,0% |
| RDS backup (120 GB extra) | storage | 120 GB | **11,40** | 4,1% |
| Data egress API→Qlik 80 GB | network | 80 GB | **7,20** | 2,6% |
| CloudWatch logs/métricas | storage | 1 mes | **6,00** | 2,2% |
| ALB LCU (~1) | network | 730 LCU-h | **5,84** | 2,1% |
| NAT data procesado 100 GB | network | 100 GB | **4,50** | 1,6% |
| Lambda `tp-gold-api` (agregado) | compute | 1 mes | **4,00** | 1,5% |
| S3 lake 150 GB | storage | 150 GB | **3,45** | 1,3% |
| EFS DAGs/logs 10 GB | storage | 10 GB | **3,00** | 1,1% |
| Secrets Manager (5 secretos) | db | 5 | **2,00** | 0,7% |
| S3 requests 500 k | storage | 500 k-req | **0,20** | 0,1% |
| VPC Gateway endpoint S3 | network | 1 mes | **0,00** | 0% |
| **TOTAL on-demand** | | | **275,78** | **92% del budget** |

Coincide con Solution §7 (**275,79**; diferencia de redondeo 0,01 en Fargate).

### 1.2 Top 3 y lectura FinOps

1. **RDS Multi-AZ** — 105,12 (db / HA del DW)  
2. **Fargate Airflow** — 45,04 (compute)  
3. **NAT Gateway base** — 32,85 (network)

Más storage RDS (28,75) el “olvidado caro” no es solo compute: **db + NAT + disco**.  
Spot no aplica a este stack (RDS/NAT/ALB/Fargate estable). El único `sp_eligible` es Fargate.

### 1.3 Optimizado (Compute Savings Plan 1 año, ~30% solo Fargate)

| | On-demand | Optimizado | Ahorro |
|--|----------:|-----------:|-------:|
| Fargate | 45,04 | 31,53 | 13,51 |
| Resto | 230,74 | 230,74 | 0 |
| **Total** | **275,78** | **262,26** | **13,51** |

- Presupuesto 300 → OD **92%** · SP **87%** → **entra**.  
- Margen OD: **24,22** USD · margen SP: **37,74** USD.

### 1.4 Hobby vs AWS (qué “genera” esta corrida local)

| Recurso IaC / Compose | Hobby (hoy) | AWS real |
|----------------------|-------------|----------|
| IAM roles/users/groups | LocalStack :4566 | IAM |
| VPC / SG / NAT / VPCE S3 | LocalStack (modelo) | VPC de pago (NAT sí factura) |
| Buckets lake | MinIO :9000 | S3 |
| RDS `tp-dw-db` + seed | MiniStack Postgres (host ~15432/15434) | RDS Multi-AZ |
| Secrets `dw/*` | MiniStack :4567 | Secrets Manager |
| Lambda `tp-gold-api` | LocalStack | Lambda |
| Airflow | Compose `:8080` | ECS Fargate + EFS |
| ALB | stand-in `:8088` | ALB + LCU |
| Budget 300 / alertas 80–100 | JSON inventario local | AWS Budgets (`create_budget=true`) |

`create_budget=false` a propósito: LocalStack Hobby **no** implementa Budgets usable. Estimación = `pricing.py`; Budget se crea en AWS real.

---

## 2. Escenarios

### 2.1 Endpoints (NAT solo a orígenes)

[`labs/finops/services.endpoints.json`](../labs/finops/services.endpoints.json): NAT data 100→25 GB (S3 ya va por Gateway VPCE, 0 USD).

| | Baseline | Endpoints | Δ |
|--|--------:|----------:|--:|
| On-demand | 275,78 | **272,40** | −3,38 |
| Optimizado | 262,26 | **258,89** | −3,37 |

No se puede apagar el NAT: ERP / ecommerce / eventos / scraping siguen **por host** (Solution §5). Interface endpoints Secrets/ECR (~7,3 USD/AZ) no se sumaron: el ahorro de GB de NAT no los paga.

### 2.2 Techo agresivo USD 220

| Opción | Idea | OD est. | ¿Cumple RPO/RTO Multi-AZ? |
|--------|------|--------:|---------------------------|
| **A — recortar HA** | RDS Single-AZ + Airflow horario laboral + Function URL (sin ALB) | ~167 | **No** |
| **B — right-size** | db.t3.small Multi-AZ, 150 GB gp3, menos egress | ~204 | **Sí** |

**Decisión:** B. El sponsor puede bajar techo sin romper HA del DW.

### 2.3 Scale producción (más BI / más datos)

RDS 500 GB + backup 250 + S3 500 GB + 1500 k-req + egress 200 GB + Fargate ×1,5 + 2 LCU:

- On-demand **364,49** USD (~**1,32×** baseline)  
- Optimizado **344,22** USD  
- Budget mínimo sugerido: **400**/mes (alerta 80% ≈ 320)

---

## 3. Observaciones del smoke test (13 ago 2026)

Infra levantada: Compose + `tofu apply` (**67 add / 5 change**). **Sin ETL.**

### 3.1 Críticas para “la infra responde”

Ninguna bloquea IAM / VPC / S3 / RDS / Lambda **existir** ni UIs (Airflow, ALB health, pgAdmin).

| Hallazgo | ¿Crítico para levantar? | ¿Crítico para usar? | Acción |
|----------|-------------------------|---------------------|--------|
| pgAdmin `admin@tp.local` + `chown` no-root | **Sí** (pgAdmin exit 1) | Login UI | **Ajustado:** email `admin@example.com`, `user: root` en Compose |
| Contenedores huérfanos (`alb-standin`, Airflow viejo en `:8080`) | Sí en *esta* máquina | Puertos | Operativo: `docker rm` / parar compose viejo. No es bug del HCL |
| Zip Lambda **sin `pg8000`** | No | **Sí** para `GET /gold/query` (500) | **No ajustado ahora** — decisión 006. Health ALB OK. Se arma cuando se pule ETL/API |
| Puerto RDS host 15434 ≠ 15432 | No | pgAdmin / override Lambda→RDS | **No crítico** hasta que haya driver. MiniStack asigna puerto dinámico. Override: `TF_VAR_rds_port_override` + `docker ps --filter name=ministack-rds` |
| MinIO + `test`/`test` → `InvalidAccessKeyId` | No | `aws s3 ls` | Docs: usar `minioadmin`. No es fallo de buckets |
| `tofu plan` 4 updates en `description` de SG | No | Idempotencia cosmética | **Ajustado:** `ignore_changes` también en `description` |
| Warnings S3 `for_each` deprecado (provider AWS) | No | Ruido en plan | No toca runtime. Deuda provider |
| Allowlist gold ≠ `hecho_ventas` | No | 400 en query | Tablas reales: `dim_*`, `fact_venta_linea`, … (README actualizado) |

### 3.2 Qué quedó verificado (sin ETL)

- Roles `app-role`, `api-role`, `ecsTaskExecutionRole`, grupo `bi-ops`  
- Buckets `*-data-lake` en MinIO  
- RDS `tp-dw-db` **available** + secrets `dw/rds-*`, `dw/erp`, `dw/origen-demo`  
- Lambda `tp-gold-api` **Active**  
- ALB `:8088/health` → `{"ok":true,"target":"tp-gold-api"}`  
- Airflow `:8080` y pgAdmin `:5050` HTTP 200  

Comandos: README §5.

---

## 4. Red de seguridad (cuando pase a AWS real)

- [ ] `notify.json` / `finops_notify_email` con mail real  
- [ ] `tofu apply` con `create_budget=true` (cuenta AWS real)  
- [ ] Alertas 80% ACTUAL y 100% FORECASTED  
- [ ] Revisar NAT GB reales vs modelo 100 GB  

Hobby: no crear Budget contra LocalStack.

---

## 5. Cómo regenerar los números

```powershell
cd labs/finops
python pricing.py --budget 300
python pricing.py --services services.endpoints.json --budget 300
python pricing.py --services services.scale.json --budget 400
```
