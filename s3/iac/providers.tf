# Provider único → MinIO (:9000). IAM/STS siguen en LocalStack (s3_demo.py).
# En AWS real: mismo código sin endpoints, con credenciales de cuenta.

provider "aws" {
  region = var.region

  access_key = var.minio_access_key
  secret_key = var.minio_secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = var.minio_endpoint
  }
}
