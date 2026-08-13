# =============================================================================
# variables.tf — Entradas del stack FinOps lab-10-tp
# -----------------------------------------------------------------------------
# Tornillos sin editar main.tf. Defaults = techo TP USD 300 + Hobby seguro.
# =============================================================================

variable "region" {
  type        = string
  description = "Región de la API Budgets (global vía us-east-1)."
  default     = "us-east-1"
}

variable "use_localstack" {
  type        = bool
  description = <<-EOT
    true = endpoints LocalStack (:4566). Budgets es Pro-only → Hobby falla al create.
    false (default) = AWS real / Learner Lab (credenciales del entorno).
  EOT
  default     = false
}

variable "localstack_endpoint" {
  type        = string
  description = "URL LocalStack si use_localstack=true."
  default     = "http://localhost:4566"
}

variable "aws_access_key" {
  type        = string
  description = "Solo para use_localstack (test/test)."
  default     = "test"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "Solo para use_localstack (test/test)."
  default     = "test"
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Budget (alineado a budget.json / Solution §7)
# ---------------------------------------------------------------------------

variable "create_budget" {
  type        = bool
  description = <<-EOT
    false (default) = no llama a la API Budgets; valida JSON + escribe inventario.
                      Usá esto en Hobby / sin cuenta AWS.
    true = crea aws_budgets_budget (requiere notify_email real + AWS o LocalStack Pro).
  EOT
  default     = false
}

variable "budget_name" {
  type        = string
  description = "BudgetName (tp-integrador-monthly-budget)."
  default     = "tp-integrador-monthly-budget"
}

variable "budget_amount" {
  type        = string
  description = "Límite mensual en USD (string, API Budgets). Techo TP = 300."
  default     = "300"
}

variable "budget_unit" {
  type        = string
  description = "Unidad del límite (USD)."
  default     = "USD"
}

variable "notify_email" {
  type        = string
  description = <<-EOT
    Mail del grupo para alertas 80% ACTUAL / 100% FORECASTED.
    Debe coincidir con notify.json editado. create_budget=true rechaza you@example.com.
  EOT
  default     = "you@example.com"
}

variable "actual_threshold_pct" {
  type        = number
  description = "Umbral ACTUAL (% del budget). Lab: 80."
  default     = 80
}

variable "forecasted_threshold_pct" {
  type        = number
  description = "Umbral FORECASTED (% del budget). Lab: 100."
  default     = 100
}

variable "tags" {
  type        = map(string)
  description = "Tags de documentación (Budgets no siempre los propaga igual que EC2)."
  default = {
    Project = "TP-Integrador"
    Lab     = "10-tp"
  }
}
