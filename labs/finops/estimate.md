# Estimación de costos — Cloud Foundations TP Integrador

**Presupuesto mensual objetivo:** USD **300** (Solution Architecture — alerta Budgets al 80%)  
**Región:** us-east-1  
**Fecha:** 13 ago 2026  
**Stack:** VPC 07-v2 · RDS 08-tp · Fargate+EFS 09b · Lambda+ALB lab-api · S3/MinIO lake  

Documento narrativo + observaciones de smoke test: [`docs/finops.md`](../../docs/finops.md).  
Decisiones: [`docs/decisions.md`](../../docs/decisions.md).

Este workbook es la sección FinOps del entregable. Números = `python pricing.py`.

---

## Arranque — stack TP (`services.json`)

```powershell
cd labs/finops
python pricing.py --budget 300
# o: python finops_demo.py
```

**Q1.** ¿Cuál es el costo mensual total **on-demand** del stack TP?
> **USD 275,78** (Solution §7: 275,79; Δ 0,01 redondeo Fargate)

**Q2.** Top 3 servicios por costo (nombre + USD + % del total):
1. `rds-postgres-maz` — **105,12** (38,1%) — db / HA
2. `ecs-fargate-airflow` — **45,04** (16,3%) — compute
3. `nat-gateway` — **32,85** (11,9%) — network  
   (si se suma NAT data 4,50 → NAT total 37,35, sigue 3º detrás de Fargate)

**Q3.** De esos top 3, ¿cuántos son **compute**, **db/storage**, **network**? ¿Coincide con “los olvidados caros = NAT + Multi-AZ”?
> 1 db (RDS Multi-AZ) + 1 compute (Fargate) + 1 network (NAT). **Sí:** los caros no son solo cómputo; HA del DW + NAT de salida a orígenes dominan. Storage gp3 (28,75) es el 4º.

**Q4.** Con Savings Plan solo en `ecs-fargate-airflow` (sp_eligible), ¿cuánto ahorrás vs on-demand total?
> **USD 13,51**/mes (30% de 45,04). Total optimizado **262,26**.

**Q5.** ¿El total optimizado entra en **USD 300**? ¿Con qué margen?
> **Sí.** OD 275,78 → margen **24,22** (92% del techo). SP 262,26 → margen **37,74** (87%).

---

## Desafío 1 — NAT vs VPC endpoints (lab 07-v2)

**Contexto TP:** el diseño ya tiene **Gateway endpoint S3** ($0). El NAT sigue siendo necesario para orígenes ERP/Internet, pero Secrets/S3 no deberían ir por NAT.

**Q6.** Corré el escenario endpoints:

```powershell
python pricing.py --services services.endpoints.json --budget 300
```

- Total optimizado baseline (`services.json`): **262,26**
- Total optimizado endpoints: **258,89**
- Ahorro: **3,37** (OD: 275,78 → 272,40 = **3,38**)

**Q7.** ¿Qué tráfico **impediría** apagar el NAT por completo en este TP? (pista: extract ERP / orígenes por host)
> Extract **por host** a ERP (FoxPro), ecommerce Mongo, eventos Mongo y scraping (Internet/VPN). Sin NAT (o Direct Connect/VPN managed) ese tráfico no sale de las subnets privadas. S3 ya puede ir por Gateway VPCE; los orígenes no.

---

## Desafío 2 — Presión de budget (tradeoffs reales del TP)

**Contexto:** el sponsor pide explorar un techo más agresivo de **USD 220/mes** sin romper el to-be (API gold + Bronce/Gold + Airflow).

**Q8.** Dos opciones (editá copias de `services.json` o describí los cambios):

**Opción A — recortar HA / cómputo:**
- RDS Single-AZ (~mitad de 105,12), Airflow solo horario laboral (~176 h vs 730), sacar ALB y exponer Lambda Function URL.
- Qué se pierde vs Solution §5: **RPO/RTO Multi-AZ**, ETL 24/7, TLS/HA perimetral del ALB.
- Costo estimado: **~167 USD** OD (entra holgado en 220).

**Opción B — right-size sin romper HA:**
- db.t3.small Multi-AZ (~52,6 vs 105,1), storage 150 GB gp3, backup 80 GB, egress 40 GB.
- Costo estimado: **~204 USD** OD (entra en 220).

**Q9.** Una sola decisión + justificación (¿cumple RPO/RTO Multi-AZ del TP?).
> **Opción B.** El techo 220 es viable right-sizeando instancia/disco **sin** bajar Multi-AZ. A rompe el SMART de HA (RPO ≤ 5 min / RTO ≤ 30 min). Documentado en `docs/decisions.md` + `docs/finops.md` §2.2.

```powershell
python pricing.py --budget 220
```

(baseline 275,78 **no** entra en 220 sin cambiar `services.json`; B sí.)

---

## Desafío 3 — Escalar producción (más BI / más datos)

**Q10.** Creá `services.scale.json` (o anotá) con:
- RDS storage 500 GB; backup 250 GB
- S3 lake 500 GB; requests 1500 k-req
- egress 200 GB
- Fargate 1.5× unit_price (más workers Airflow)
- ALB 2 LCU (×2 `alb-lcu` usage)

→ archivo: [`services.scale.json`](./services.scale.json)

**Q11.** Budget mínimo sugerido para ese scale: **USD 400**/mes (OD ≈ 364; SP ≈ 344; alerta 80% ≈ 320).

**Q12.** ¿Cuántas veces más caro vs el baseline TP?
> **~1,32×** on-demand (364 / 275,78).

```powershell
python pricing.py --services services.scale.json --budget 400
```

---

## Cierre — entregable TP

**Q13.** Pegá el output de:

```powershell
python pricing.py --budget 300
```

```
On-Demand (precio de lista)
  rds-postgres-maz     db              730 hs       $  0.1440  $ 105.12
  rds-storage-gp3      storage         250 GB-mes   $  0.1150  $  28.75
  rds-backup           storage         120 GB-mes   $  0.0950  $  11.40
  ecs-fargate-airflow  compute         730 hs       $  0.0617  $  45.04
  efs-airflow          storage          10 GB-mes   $  0.3000  $   3.00
  nat-gateway          network         730 hs       $  0.0450  $  32.85
  nat-data-processed   network         100 GB       $  0.0450  $   4.50
  alb-api              network         730 hs       $  0.0225  $  16.43
  alb-lcu              network         730 LCU-hs   $  0.0080  $   5.84
  lambda-gold-api      compute           1 mes      $  4.0000  $   4.00
  s3-data-lake         storage         150 GB-mes   $  0.0230  $   3.45
  s3-requests          storage         500 k-req    $  0.0004  $   0.20
  data-egress          network          80 GB       $  0.0900  $   7.20
  cloudwatch           storage           1 mes      $  6.0000  $   6.00
  secrets-manager      db                5 secret-mes $  0.4000  $   2.00
  vpce-s3-gateway      network           1 mes      $  0.0000  $   0.00
  TOTAL                                                       $ 275.78

Optimizado
  ecs-fargate-airflow  SavingsPlan  $  45.04  →  $  31.53  (ahorro $ 13.51)
  TOTAL                            $ 275.78  $  262.26  $  13.51

Presupuesto vs realidad
  Presupuesto:      $ 300.00
  On-Demand:        $ 275.78  (  92% del budget)
  Optimizado:       $ 262.26  (  87% del budget)
  Ahorro mensual:   $  13.51
  Estado:           ✓ entra en budget con optimización
```

**Q14.** ¿Cumple ≤ USD 300? Si el margen es fino, ¿qué decisión de arquitectura documentarías en `docs/decisions.md`?
> **Sí, cumple** (margen OD 24 USD / SP 38 USD). No es “fino” al punto de recortar HA. Decisiones a dejar: **005** (estimar local, Budget en AWS real), **007** (NAT + VPCE S3, no apagar NAT), **003** (Hobby no factura; el 275,78 es to-be). Si el sponsor baja a 220 → right-size RDS (B), no Single-AZ.

---

## Red de seguridad (Budget)

- [ ] Mail real en `notify.json` (no `you@example.com`)
- [ ] `budget.json` Amount = **300** (o el techo que eligieron en Q9)
- [ ] `create-budget.sh` / Budget contra **AWS real**
- [ ] Alertas 80% ACTUAL y 100% FORECASTED

Hobby LocalStack: Budgets = **Pro-only** — modelar JSON; crear budget en AWS real.

---

## Mapa lab → línea de costo

| Lab | Servicio(s) en `services.json` | Módulo IaC |
|---|---|---|
| 07-v2 | `nat-gateway`, `nat-data-processed`, `vpce-s3-gateway` | `infra/modules/vpc` |
| 08-tp | `rds-postgres-maz`, `rds-storage-gp3`, `rds-backup`, `secrets-manager` | `infra/modules/rds` + `secrets` |
| 09b | `ecs-fargate-airflow`, `efs-airflow` | `infra/modules/ecs` (Hobby: Compose Airflow) |
| lab-api | `alb-api`, `alb-lcu`, `lambda-gold-api`, `data-egress` | `infra/modules/lambda` + alb-standin |
| lake | `s3-data-lake`, `s3-requests` | `infra/modules/s3` (MinIO) |
| ops | `cloudwatch` | `infra/modules/cloudwatch` |

---

## Fuentes

- [`docs/Solution_Architecture.md`](../../docs/Solution_Architecture.md) §7
- [`docs/finops.md`](../../docs/finops.md)
- [AWS Pricing Calculator](https://calculator.aws/)
- VPC / NAT / endpoints, RDS, Fargate, ALB, Lambda, S3, EFS pricing pages
