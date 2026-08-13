# =============================================================================
# providers.tf — AWS real (Budgets) u opcional LocalStack Pro
# -----------------------------------------------------------------------------
# Budgets es un servicio de cuenta (API en us-east-1). En el lab:
#   - Estimación de costos NO usa este provider (pricing.py es local).
#   - create_budget=false → credenciales stub + skip_* (plan/apply sin cuenta).
#   - create_budget=true + use_localstack=false → credenciales del entorno
#     (AWS_PROFILE / AWS_ACCESS_KEY_ID). No hardcodear secrets en tfvars.
#   - use_localstack=true → :4566 (Hobby: create falla; Pro modela).
# =============================================================================

locals {
  # Sin Budget real: no hace falta cuenta AWS (Hobby / solo inventario).
  stub_aws = var.use_localstack || !var.create_budget
}

provider "aws" {
  region = var.region

  # Stub solo en modo local/dry-run. En AWS real: dejar que el SDK use el env.
  access_key = local.stub_aws ? var.aws_access_key : null
  secret_key = local.stub_aws ? var.aws_secret_key : null

  skip_credentials_validation = local.stub_aws
  skip_metadata_api_check     = local.stub_aws
  skip_requesting_account_id  = local.stub_aws

  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      budgets = var.localstack_endpoint
      sts     = var.localstack_endpoint
    }
  }
}
