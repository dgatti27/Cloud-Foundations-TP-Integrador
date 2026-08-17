# =============================================================================
# CloudWatch Logs del TP
# =============================================================================
# Crea log groups estables (nombres fijos) para:
#   - modelo ECS/Airflow  → /ecs/tp-airflow
#   - Lambda gold-api     → /aws/lambda/tp-gold-api
#   - ETL genérico        → /tp-integrador/etl
#
# En Hobby, Airflow también escribe en apps/airflow/logs/ (stand-in EFS).
# Export a MinIO / queries ad-hoc = demos Python, no este módulo.
# =============================================================================

variable "tags" { type = map(string) }

# ---------------------------------------------------------------------------
# Log group Airflow (≈ tasks Fargate)
# Retención corta: entorno de lab.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_airflow" {
  name              = "/ecs/tp-airflow"
  retention_in_days = 7
  tags              = merge(var.tags, { Name = "tp-airflow-logs" })
}

# ---------------------------------------------------------------------------
# Log group Lambda tp-gold-api
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/tp-gold-api"
  retention_in_days = 14
  tags              = merge(var.tags, { Name = "tp-gold-api-logs" })
}

# ---------------------------------------------------------------------------
# Log group ETL genérico (métricas / demos)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "etl" {
  name              = "/tp-integrador/etl"
  retention_in_days = 14
  tags              = merge(var.tags, { Name = "tp-etl-logs" })
}
