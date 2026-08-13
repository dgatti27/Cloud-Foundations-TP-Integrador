# =============================================================================
# outputs.tf — Valores de `tofu apply` / `tofu output`
# =============================================================================

output "create_budget" {
  description = "Si este apply creó el Budget en la cuenta"
  value       = var.create_budget
}

output "budget_name" {
  description = "Nombre del budget (JSON / variable)"
  value       = local.budget_name_effective
}

output "budget_limit_usd" {
  description = "Techo mensual USD"
  value       = local.budget_amount_effective
}

output "budget_arn" {
  description = "ARN del budget si create_budget=true; null en dry-run"
  value       = try(aws_budgets_budget.tp[0].arn, null)
}

output "notify_email" {
  description = "Mail configurado para alertas (sensible en logs de apply)"
  value       = var.notify_email
  sensitive   = true
}

output "inventory_path" {
  description = "JSON inventario en finops/"
  value       = local_file.finops_inventory.filename
}

output "next_steps" {
  description = "Ayuda post-apply"
  value       = <<-EOT
    FinOps IaC OK (create_budget=${var.create_budget}).
    Estimación del stack (local, no Budgets API):
      python finops/finops_demo.py
      python finops/finops_demo.py --endpoints
      python finops/pricing.py --budget 300
    Workbook:
      Copy-Item finops\estimate.md docs\costos-proyecto.md
    Budget en AWS real (si aún no):
      # terraform.tfvars → create_budget = true, notify_email = "grupo@..."
      tofu apply
    Alternativa bash: bash finops/create-budget.sh
  EOT
}
