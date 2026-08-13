# Estimación de costos — Cloud Foundations TP Integrador

**Presupuesto mensual objetivo:** USD **300** (Solution Architecture — alerta Budgets al 80%)  
**Región:** us-east-1  
**Fecha:** _completar_  
**Stack:** VPC 07-v2 · RDS 08-tp · Fargate+EFS 09b · Lambda+ALB lab-api · S3/MinIO lake  

Este workbook es la sección FinOps del entregable. Respondé mirando `python pricing.py` / `python finops_demo.py`.

---

## Arranque — stack TP (`services.json`)

```powershell
cd finops
python pricing.py --budget 300
# o: python finops_demo.py
```

**Q1.** ¿Cuál es el costo mensual total **on-demand** del stack TP?
> _número_

**Q2.** Top 3 servicios por costo (nombre + USD + % del total):
1. _
2. _
3. _

**Q3.** De esos top 3, ¿cuántos son **compute**, **db/storage**, **network**? ¿Coincide con “los olvidados caros = NAT + Multi-AZ”?
> _

**Q4.** Con Savings Plan solo en `ecs-fargate-airflow` (sp_eligible), ¿cuánto ahorrás vs on-demand total?
> _

**Q5.** ¿El total optimizado entra en **USD 300**? ¿Con qué margen?
> _

---

## Desafío 1 — NAT vs VPC endpoints (lab 07-v2)

**Contexto TP:** el diseño ya tiene **Gateway endpoint S3** ($0). El NAT sigue siendo necesario para orígenes ERP/Internet, pero Secrets/S3 no deberían ir por NAT.

**Q6.** Corré el escenario endpoints:

```powershell
python pricing.py --services services.endpoints.json --budget 300
```

- Total optimizado baseline (`services.json`): $___
- Total optimizado endpoints: $___
- Ahorro: $___

**Q7.** ¿Qué tráfico **impediría** apagar el NAT por completo en este TP? (pista: extract ERP / orígenes por host)
> _

---

## Desafío 2 — Presión de budget (tradeoffs reales del TP)

**Contexto:** el sponsor pide explorar un techo más agresivo de **USD 220/mes** sin romper el to-be (API gold + Bronce/Gold + Airflow).

**Q8.** Dos opciones (editá copias de `services.json` o describí los cambios):

**Opción A — recortar HA / cómputo:**
- ¿Single-AZ RDS? ¿Airflow solo en horario laboral (menos hs Fargate)? ¿sacar ALB y exponer Lambda Function URL?
- Qué se pierde vs Solution §5:
- Costo estimado:

**Opción B — right-size sin romper HA:**
- db.t3.small Multi-AZ, menos storage, lifecycle S3 IA, menos egress
- Costo estimado:

**Q9.** Una sola decisión + justificación (¿cumple RPO/RTO Multi-AZ del TP?).
> _

```powershell
python pricing.py --budget 220
```

---

## Desafío 3 — Escalar producción (más BI / más datos)

**Q10.** Creá `services.scale.json` (o anotá) con:
- RDS storage 500 GB; backup 250 GB
- S3 lake 500 GB; requests 1500 k-req
- egress 200 GB
- Fargate 1.5× unit_price (más workers Airflow)
- ALB 2 LCU (×2 `alb-lcu` usage)

**Q11.** Budget mínimo sugerido para ese scale: $___  
**Q12.** ¿Cuántas veces más caro vs el baseline TP?
> _

```powershell
python pricing.py --services services.scale.json --budget 500
```

---

## Cierre — entregable TP

**Q13.** Pegá el output de:

```powershell
python pricing.py --budget 300
```

```
_pegar output_
```

**Q14.** ¿Cumple ≤ USD 300? Si el margen es fino, ¿qué decisión de arquitectura documentarías en `docs/decisions.md`?
> _

---

## Red de seguridad (Budget)

- [ ] Mail real en `notify.json` (no `you@example.com`)
- [ ] `budget.json` Amount = **300** (o el techo que eligieron en Q9)
- [ ] `create-budget.sh` / `finops_demo.py --create-budget` contra **AWS real** (Learner Lab)
- [ ] Alertas 80% ACTUAL y 100% FORECASTED

Hobby LocalStack: Budgets = **Pro-only** — modelar JSON; crear budget en AWS real.

---

## Mapa lab → línea de costo

| Lab | Servicio(s) en `services.json` |
|---|---|
| 07-v2 | `nat-gateway`, `nat-data-processed`, `vpce-s3-gateway` |
| 08-tp | `rds-postgres-maz`, `rds-storage-gp3`, `rds-backup`, `secrets-manager` |
| 09b | `ecs-fargate-airflow`, `efs-airflow` |
| lab-api | `alb-api`, `alb-lcu`, `lambda-gold-api`, `data-egress` |
| lake | `s3-data-lake`, `s3-requests` |
| ops | `cloudwatch` |

---

## Fuentes

- [`docs/Solution_Architecture.md`](../docs/Solution_Architecture.md) §7
- [AWS Pricing Calculator](https://calculator.aws/)
- VPC / NAT / endpoints, RDS, Fargate, ALB, Lambda, S3, EFS pricing pages
