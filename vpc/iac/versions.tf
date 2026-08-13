# =============================================================================
# versions.tf — Versión de OpenTofu y providers
# -----------------------------------------------------------------------------
# No crea recursos: fija requisitos para `tofu init`.
# Infra lab-07-v2 → LocalStack EC2/VPC.
# Bash pedagógico (se preserva): vpc/provision_vpc_v2.sh
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # API EC2/VPC (también SGs, EIP, NAT, VPC endpoints)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Escribe vpc/vpc_config.json para labs 08+ (RDS, Lambda, ECS)
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}
