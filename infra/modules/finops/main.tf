# =============================================================================
# FinOps — Budget AWS opcional + inventario local
# =============================================================================
# Hobby (create_budget=false, default):
#   LocalStack no implementa Budgets de forma usable.
#   Solo escribe infra/generated/finops_inventory.json.
#   Estimación de costo → labs/finops/pricing.py + docs/finops.md.
#
# AWS real (create_budget=true + email real):
#   Crea aws_budgets_budget con alertas ACTUAL y FORECASTED.
# =============================================================================

variable "tags" { type = map(string) }
variable "create_budget" {
  type        = bool
  description = "false en Hobby. true solo en AWS real con notify_email válido."
  default     = false
}
variable "notify_email" {
  type    = string
  default = "you@example.com"
}
variable "actual_threshold_pct" {
  type    = number
  default = 80
}
variable "forecasted_threshold_pct" {
  type    = number
  default = 100
}

# ---------------------------------------------------------------------------
# Locals — leen budget.json (nombre + límite USD del techo SMART del TP)
# ---------------------------------------------------------------------------
locals {
  budget_file   = jsondecode(file("${path.module}/budget.json"))
  budget_name   = local.budget_file["BudgetName"]
  budget_amount = local.budget_file["BudgetLimit"]["Amount"]
}

# ---------------------------------------------------------------------------
# Guardrail: no crear Budget con email placeholder
# ---------------------------------------------------------------------------
check "notify_email_not_placeholder" {
  assert {
    condition     = !var.create_budget || var.notify_email != "you@example.com"
    error_message = "create_budget=true requiere notify_email real (no you@example.com)."
  }
}

# ---------------------------------------------------------------------------
# Inventario local (siempre) — evidencia FinOps en Hobby
# ---------------------------------------------------------------------------
resource "local_file" "finops_inventory" {
  filename = "${path.module}/../../generated/finops_inventory.json"
  content = jsonencode({
    create_budget    = var.create_budget
    budget_name      = local.budget_name
    budget_limit_usd = local.budget_amount
    notify_email     = var.notify_email
    alerts = [
      { type = "ACTUAL", threshold = var.actual_threshold_pct },
      { type = "FORECASTED", threshold = var.forecasted_threshold_pct },
    ]
    estimation = {
      tool               = "python labs/finops/pricing.py"
      services_baseline  = "labs/finops/services.json"
      workbook           = "labs/finops/estimate.md"
      narrative          = "docs/finops.md"
      decisions          = "docs/decisions.md"
    }
    notes = "Hobby: inventario local. Budget AWS solo si create_budget=true."
    tags  = var.tags
  })
}

# ---------------------------------------------------------------------------
# Budget AWS real (solo create_budget=true)
# Alertas: 80% gasto actual · 100% forecast → email.
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "tp" {
  count = var.create_budget ? 1 : 0

  name         = local.budget_name
  budget_type  = "COST"
  limit_amount = local.budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

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

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.actual_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notify_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.forecasted_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notify_email]
  }
}
