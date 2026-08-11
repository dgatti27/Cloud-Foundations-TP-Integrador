# Lambda API → GOLD (lab-api)

Lab: [`lab-api-tp.md`](./lab-api-tp.md)  
Script: [`lambda_demo.py`](./lambda_demo.py)

```powershell
python lambda/lambda_demo.py
# Postman GET http://localhost:8088/gold/query?table=dim_cliente&columns=nombre,email&condition=segmento=retail
# Logs: CW /aws/lambda/tp-gold-api → MinIO s3://backup-data-lake/logs/lambda/tp-gold-api/
```

## Hobby vs AWS

| Pieza | Hobby | AWS real |
|---|---|---|
| Lambda en compute privada | ✅ LocalStack + VpcConfig | ✅ |
| ALB HTTPS público | Stand-in `:8088` | ALB `:443` |
| Secret / SQL | `dw/rds-api` / `api_reader` | igual |
| Logs | CW Logs (LS) + export JSONL a MinIO | Firehose / Export Task → S3 |

## Archivos

| Archivo | Rol |
|---|---|
| `handler.py` | Entry Lambda |
| `query_gold.py` | SELECT seguro gold |
| `*_policy.json` / `trust_lambda.json` | IAM |
| `docker-compose.alb.yaml` | ALB stand-in |
