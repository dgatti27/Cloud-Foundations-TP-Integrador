output "budget_name" {
  value = local.budget_name
}

output "create_budget" {
  value = var.create_budget
}

output "inventory_path" {
  value = local_file.finops_inventory.filename
}
