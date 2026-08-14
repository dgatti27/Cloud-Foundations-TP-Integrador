# Cómputo ETL (stand-in Fargate + EFS)

Hobby no tiene APIs `ecs`/`efs`. Este directorio tiene el **script de runtime** que:

1. (Opcional) modela IAM execution/task en LocalStack  
2. Levanta Airflow vía Compose raíz  
3. Triggerea DAGs en `apps/airflow/dags/` (≈ EFS)

IaC del modelo: [`../../infra/modules/ecs`](../../infra/modules/ecs).  
Flujo de datos: [README raíz](../../README.md#datos-esquemas-y-procesamiento).

## Quick start

```powershell
# Tras: docker compose up -d  +  cd infra; tofu apply
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

python apps/etl/etl_demo.py                              # origen ERP + dw/erp
python labs/ecs/ecs.py --skip-infra --erp                # DAGs ERP→bronce→gold
# UI http://localhost:8080  admin/admin
```

| Flag | Efecto |
|------|--------|
| (sin flags) | IAM modelo + Compose + camino A (`etl_rds_comprobation`) |
| `--skip-infra` | Solo runtime (recomendado si ya corriste `tofu apply`) |
| `--erp` | Además `etl_erp_to_bronce` + `etl_bronce_to_gold` |
| `--skip-runtime` | Solo IAM / checks |
| `--cleanup` | Stop Airflow |

## Archivos

| Archivo | Rol |
|---|---|
| [`ecs.py`](./ecs.py) | Orquestación demo / trigger DAGs |
| [`efs_config.json`](./efs_config.json) | Inventario stand-in (paths → `apps/airflow`) |
| [`IAM-NOTES.md`](./IAM-NOTES.md) | Notas de policies |
| Policies `*.json` | Modelo IAM (también en `infra/modules/iam`) |
