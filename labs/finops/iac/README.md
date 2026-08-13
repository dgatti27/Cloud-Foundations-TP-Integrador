# Lab 10-TP — IaC OpenTofu (AWS Budget FinOps)

Declara la **única infra cloud** del lab 10: el **AWS Budget** mensual del TP.

| Recurso | Lab 10-TP |
|---|---|
| `check` + `local_file` inventario | Valida `budget.json` / mail; escribe `finops_inventory.json` |
| `aws_budgets_budget` (opcional) | Techo USD 300 + alertas 80% ACTUAL / 100% FORECASTED |

## Qué va en IaC vs Python

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Estimación de costos** | `finops_demo.py` / `pricing.py` | **Se preserva** — local, sin API cloud |
| **Workbook** | `estimate.md` → `docs/costos-proyecto.md` | Q1–Q14 |
| **Budget (deseado)** | OpenTofu acá (`create_budget=true`) | `tp-integrador-monthly-budget` |
| **Budget bash** | `create-budget.sh` | **Se preserva** — misma API vía CLI |

> LocalStack Hobby: Budgets = **Pro-only**. Default `create_budget=false` para que `tofu apply` funcione sin cuenta.

No hay módulos FinOps en `infra/`; este stack es autocontenido para lab-10-tp.

## Prereqs

```powershell
# Estimación: solo Python + JSON del repo
# Budget real: cuenta AWS / Learner Lab + mail en notify.json
```

## Uso — Hobby (inventario)

```powershell
cd finops/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Luego estimación:

```powershell
cd ../..
python finops/finops_demo.py
```

## Uso — AWS real (crear Budget)

1. Editá `finops/notify.json` (mail del grupo).
2. En `terraform.tfvars`:

```hcl
create_budget  = true
use_localstack = false
notify_email   = "tu-grupo@universidad.edu"
```

3. Credenciales AWS en el entorno (`AWS_PROFILE` / keys).
4. `tofu apply`

## Destroy

```powershell
tofu destroy   # solo borra el Budget si create_budget=true
```

## Relación con `finops_demo.py`

| | OpenTofu | Python |
|---|---|---|
| `services.json` → USD/mes | No | Sí |
| Validar budget/notify JSON | Checks + inventario | `validate_budget_files()` |
| `create-budget` API | `aws_budgets_budget` | No (bash `create-budget.sh`) |
