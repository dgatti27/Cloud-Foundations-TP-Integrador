# =============================================================================
# main.tf — Lab 10-TP FinOps (Budget AWS + inventario local)
# -----------------------------------------------------------------------------
# Qué ES infraestructura en este lab:
#   aws_budgets_budget — techo mensual + notificaciones (red de seguridad).
#
# Qué NO es IaC (queda en Python / markdown):
#   services.json + pricing.py + finops_demo.py — estimación on-demand/SP
#   estimate.md workbook Q1–Q14
#   create-budget.sh — alternativa bash al resource de abajo
#
# Flujo Hobby (default):
#   tofu apply  → check JSON + finops_inventory.json  (create_budget=false)
#   python finops/finops_demo.py → números del stack
#
# Flujo AWS real:
#   Editá notify_email / notify.json → create_budget=true → tofu apply
# =============================================================================

locals {
  finops_dir = "${path.module}/.."

  # Lee budget.json del lab (misma fuente que create-budget.sh / finops_demo)
  budget_file = jsondecode(file("${local.finops_dir}/budget.json"))

  # Preferir variables (tfvars) pero cruzar con el archivo del repo
  budget_name_effective   = coalesce(var.budget_name, local.budget_file["BudgetName"])
  budget_amount_effective = coalesce(var.budget_amount, local.budget_file["BudgetLimit"]["Amount"])
}

# ---------------------------------------------------------------------------
# Guardrails — fallan en plan si la config del lab está mal
# ---------------------------------------------------------------------------
check "budget_amount_matches_file" {
  assert {
    condition     = local.budget_amount_effective == local.budget_file["BudgetLimit"]["Amount"]
    error_message = "budget_amount (${local.budget_amount_effective}) ≠ budget.json Amount (${local.budget_file["BudgetLimit"]["Amount"]}). Alineá tfvars y el JSON."
  }
}

check "notify_email_not_placeholder" {
  assert {
    condition     = !var.create_budget || var.notify_email != "you@example.com"
    error_message = "create_budget=true requiere notify_email real (no you@example.com). Editá terraform.tfvars y finops/notify.json."
  }
}

# ---------------------------------------------------------------------------
# Inventario local (siempre) — entregable / DX sin tocar la nube
# ---------------------------------------------------------------------------
resource "local_file" "finops_inventory" {
  filename = "${local.finops_dir}/finops_inventory.json"
  content = jsonencode({
    lab              = "10-tp"
    create_budget    = var.create_budget
    use_localstack   = var.use_localstack
    budget_name      = local.budget_name_effective
    budget_limit_usd = local.budget_amount_effective
    notify_email     = var.notify_email
    alerts = [
      {
        type      = "ACTUAL"
        threshold = var.actual_threshold_pct
      },
      {
        type      = "FORECASTED"
        threshold = var.forecasted_threshold_pct
      },
    ]
    estimation = {
      tool             = "python finops/finops_demo.py"
      services_baseline = "finops/services.json"
      services_endpoints = "finops/services.endpoints.json"
      workbook         = "finops/estimate.md → docs/costos-proyecto.md"
    }
    bash_alternative = "finops/create-budget.sh"
    notes            = "Inventario generado por finops/iac. Estimación de costos = pricing.py (no Budgets API)."
    tags             = var.tags
  })
}

# ---------------------------------------------------------------------------
# AWS Budget (solo si create_budget=true)
# Equivale a: aws budgets create-budget --budget file://budget.json
#             --notifications-with-subscribers file://notify.json
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "tp" {
  count = var.create_budget ? 1 : 0

  name         = local.budget_name_effective
  budget_type  = "COST"
  limit_amount = local.budget_amount_effective
  limit_unit   = var.budget_unit
  time_unit    = "MONTHLY"

  # CostTypes alineados a budget.json del lab
  cost_types {
    include_credit             = false
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = false
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }

  # 80% gasto ACTUAL
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.actual_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notify_email]
  }

  # 100% FORECASTED
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.forecasted_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notify_email]
  }
}
