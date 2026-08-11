# Lab 10 TP — Cloud Economics & FinOps (TP Integrador)

<!--
  Este lab aplica FinOps al stack REAL del TP (no al ejemplo genérico EC2+t3.micro).
  Plantilla de clase genérica: lab-10.md (referencia).
  Entregable workbook: estimate.md → copiar a docs/costos-proyecto.md
  Script: python finops/finops_demo.py
-->

Estimar y acotar el costo del to-be:

**IAM → VPC → RDS → Fargate/EFS → Lambda/ALB → S3 lake**, con techo **≤ USD 300/mes**
([`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §7).

> **Punto de fondo**  
> El costo es una **decisión de arquitectura** (Multi-AZ, NAT, Fargate vs EC2, ALB).  
> Este lab no es “correr un script y copiar el número”: es justificar tradeoffs
> frente al budget del TP.

---

## Script de ejecución (recomendado)

```powershell
$env:PYTHONIOENCODING = "utf-8"
cd finops

python finops_demo.py
# python finops_demo.py --endpoints      # escenario VPC endpoints
# python finops_demo.py --budget 220
# python pricing.py --services services.json --budget 300
```

`finops_demo.py` corre el estimador, muestra top drivers y valida `budget.json` / `notify.json`.

---

## Prerequisitos

- Python 3 (stdlib + los JSON del repo; `pricing.py` no necesita pip)
- Haber leído Solution §5–7 (por qué Fargate, Multi-AZ, ALB, NAT)
- Labs 07–09b / lab-api ya entendidos (aunque FinOps no levanta Docker)

---

## Parte 1 — Workbook TP

1. Copiá el workbook:

```powershell
Copy-Item finops\estimate.md docs\costos-proyecto.md
```

2. Respondé **Q1–Q14** en `docs/costos-proyecto.md` (plantilla: [`estimate.md`](./estimate.md)).

| Bloque | Qué pedimos en este TP |
|---|---|
| Arranque Q1–Q5 | Baseline `services.json` (stack TP) vs budget **300** |
| Desafío 1 Q6–Q7 | `services.endpoints.json` — NAT parcial + endpoints (lab 07-v2) |
| Desafío 2 Q8–Q9 | Techo agresivo **220**: tradeoffs Multi-AZ / Fargate / ALB |
| Desafío 3 Q10–Q12 | Scale BI/datos (`services.scale.json` si lo arman) |
| Cierre Q13–Q14 | Output final + decisión en `docs/decisions.md` |

---

## Parte 2 — Herramientas

### `services.json` (baseline TP)

Líneas alineadas a labs reales:

| name | Lab / rol |
|---|---|
| `rds-postgres-maz` + storage/backup | 08-tp |
| `ecs-fargate-airflow` + `efs-airflow` | 09b |
| `nat-gateway` + data | 07-v2 |
| `alb-*` + `lambda-gold-api` + egress | lab-api |
| `s3-*` | lake (MinIO local / S3 AWS) |
| `secrets-manager` / `cloudwatch` | soporte |
| `vpce-s3-gateway` | 07-v2 ($0) |

### `pricing.py`

```powershell
python pricing.py --budget 300
python pricing.py --services services.endpoints.json --budget 300
```

On-demand vs optimizado (SP ~30% solo si `sp_eligible`, Spot ~70% si `spot_eligible`).  
En el TP casi todo el ahorro SP cae en **Fargate**; RDS/NAT/ALB no tienen Spot.

### Escenarios

| Archivo | Uso |
|---|---|
| `services.json` | Baseline to-be (~USD 276 en Solution §7) |
| `services.endpoints.json` | Desafío 1 — menos GB por NAT + interface Secrets |
| `services.scale.json` | Opcional — desafío 3 (lo crea el grupo) |

---

## Parte 3 — Budget (red de seguridad)

**Qué:** AWS Budget mensual **USD 300**, alertas 80% ACTUAL y 100% FORECASTED.  
**Para qué:** no descubrir el NAT olvidado a fin de mes.  
**Hobby:** Budgets = Pro-only en LocalStack → validar JSON acá; crear en **AWS real / Learner Lab**.

```powershell
# 1) Editá notify.json → mail del grupo (si queda you@example.com, el script falla a propósito)
# 2) budget.json Amount ya es "300"
# 3) AWS real:
bash create-budget.sh
# o desde Git Bash / WSL. En LocalStack:
#   $env:LOCALSTACK="1"; bash create-budget.sh   → esperable "API not implemented" en Hobby
```

Verificar:

```powershell
aws budgets describe-budget `
  --account-id (aws sts get-caller-identity --query Account --output text) `
  --budget-name tp-integrador-monthly-budget
```

---

## Paso — Decisión en `docs/decisions.md`

```
### 013 — FinOps TP: estimar stack to-be y Budget USD 300

Decision: estimar el costo mensual del TP con finops/services.json + pricing.py
(alineado a Solution §7) y configurar AWS Budget tp-integrador-monthly-budget
con alertas 80% ACTUAL / 100% FORECASTED.

Justificación: techo ≤ USD 300 del enunciado; NAT y RDS Multi-AZ son drivers
conscientes (HA + salida a orígenes), no sorpresas.

Tradeoff: Hobby no emite factura ni Budgets reales; la alerta se valida en AWS.
Resultado: ver docs/costos-proyecto.md (Q1–Q14).
```

---

## Checkpoint

- [ ] `python finops_demo.py` (o `pricing.py --budget 300`) corrido
- [ ] Q1–Q14 en `docs/costos-proyecto.md`
- [ ] Desafío endpoints comparado
- [ ] Tradeoff budget 220 documentado
- [ ] `notify.json` con mail real
- [ ] Budget creado en AWS real (si hay cuenta)
- [ ] Decisión 013 en `decisions.md`

---

## Hobby vs AWS real

| Acción | Hobby / local | AWS real |
|---|---|---|
| `pricing.py` / `finops_demo.py` | ✅ | ✅ |
| Validar JSON budget/notify | ✅ | ✅ |
| `budgets create-budget` | ❌ Pro-only | ✅ |
| Alertas mail / Cost Explorer | ❌ | ✅ |
| Costo Docker local (Airflow, MinIO…) | $0 infra cloud | Factura servicios AWS |

---

## Relación con el resto del TP

| Lab | Qué aporta a FinOps |
|---|---|
| 07-v2 | NAT caro + endpoint S3 $0 |
| 08-tp | RDS Multi-AZ = mayor línea de costo |
| 09b | Fargate+EFS (compute estable, candidato SP) |
| lab-api | ALB + Lambda (perímetro BI) |
| **10-tp** | Estimar + Budget antes/después de provisionar en AWS |

---

## Archivos

| Archivo | Rol |
|---|---|
| `lab-10-tp.md` | Esta guía |
| `lab-10.md` | Lab genérico de clase (referencia) |
| `finops_demo.py` | Script de ejecución |
| `pricing.py` | Estimador |
| `services.json` | Baseline TP |
| `services.endpoints.json` | Escenario endpoints |
| `estimate.md` | Workbook entregable |
| `budget.json` / `notify.json` | AWS Budgets |
| `create-budget.sh` | Alta del budget |
