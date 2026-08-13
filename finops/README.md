# `finops/` — Lab 10 TP: Cloud Economics & FinOps

Guía TP: [`lab-10-tp.md`](./lab-10-tp.md)  
Script: [`finops_demo.py`](./finops_demo.py)  
Plantilla clase (genérica): [`lab-10.md`](./lab-10.md)

Estima el **stack real del Integrador** (RDS Multi-AZ, Fargate, NAT, ALB, Lambda, EFS, S3…)
contra el techo **≤ USD 300/mes** (`docs/Solution_Architecture.md` §7).

## Uso rápido

```powershell
python finops/finops_demo.py
python finops/pricing.py --budget 300
python finops/pricing.py --services services.endpoints.json --budget 300

# Inventario IaC (Hobby) / Budget en AWS con create_budget=true
cd finops/iac; Copy-Item terraform.tfvars.example terraform.tfvars; tofu apply; cd ../..

# Workbook entregable
Copy-Item finops\estimate.md docs\costos-proyecto.md
```

## Archivos

| Archivo | Rol |
|---|---|
| `lab-10-tp.md` | Guía TP (qué / por qué) |
| `finops_demo.py` | Ejecución automatizada (estimación) |
| `pricing.py` | Estimador local (stdlib) |
| `services.json` | Baseline costos to-be |
| `services.endpoints.json` | Escenario NAT + VPC endpoints |
| `estimate.md` | Workbook Q1–Q14 |
| `budget.json` | Budget **USD 300** (`tp-integrador-monthly-budget`) |
| `notify.json` | Alertas 80% / 100% (editá el mail) |
| `create-budget.sh` | Alta Budget en AWS real (bash) |
| [`iac/`](./iac/README.md) | OpenTofu: inventario + Budget opcional |

## LocalStack

**AWS Budgets = Pro-only.** En Hobby validás JSON con el demo; el budget real se crea en AWS / Learner Lab.
