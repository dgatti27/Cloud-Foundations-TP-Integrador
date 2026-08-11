# Lab 09-tp — IaC OpenTofu: stack completo del TP Integrador

El lab 09 genérico (`lab-09.md` + `iac/aws/`) enseña el ciclo `init/plan/apply` con un bucket. Este lab declara **toda la infraestructura to-be del TP** en HCL, en el orden correcto, y la deja **idempotente**: cada `tofu apply` converge al mismo estado deseado.

> Continuación del lab pedagógico: después de `lab-09.md`, este es el cierre IaC del TP Integrador.

> **Declarativo vs imperativo**
> Los demos (`vpc/provision_*.sh`, `rds_tp_demo.py`, …) *ejecutan pasos*.
> OpenTofu *describe el resultado*. El state recuerda qué existe; el plan muestra el diff.

---

## Qué levanta

| Capa | Dónde (Hobby) | Recursos |
|------|----------------|----------|
| IAM | LocalStack `:4566` | `app-role`, `api-role`, `ecsTaskExecutionRole`, `db-role`, grupos `bi-api` / `bi-ops` + policies |
| VPC | LocalStack | VPC Multi-AZ, 6 subnets, IGW, NAT, RTs, SGs (`sg-alb/api/ecs-etl/rds/efs`), VPCE S3 |
| S3 (lake) | MinIO `:9000` | `backup-data-lake`, `snapshot-data-lake`, `staging-data-lake` + versioning |
| CloudWatch | LocalStack | log groups `/ecs/tp-airflow`, `/aws/lambda/tp-gold-api`, `/tp-integrador/etl` |
| RDS | MiniStack `:4567` | subnet group `tp-rds-subnets`, instancia `tp-dw-db` (Postgres Multi-AZ) |
| Secrets | MiniStack | `dw/rds-master`, `dw/rds-etl`, `dw/rds-api`, `dw/origen-demo`, `dw/erp` |
| Seed SQL | Docker exec → RDS | `rds/seed_tp.sql` + passwords de `etl_writer` / `api_reader` |
| Lambda | LocalStack | `tp-gold-api` (handler gold) |
| ECS / EFS | Hobby stand-in | marcadores + `ecs/efs-standin/`; con `-var enable_ecs_api=true` → cluster + EFS API |

Orden efectivo (dependencias TF):

```text
IAM ∥ VPC ∥ S3 ∥ CloudWatch
         ↓
        RDS  →  Secrets (host)  →  seed SQL
         ↓
      Lambda + ECS/stand-in
         ↓
   generated/vpc_config.json  (+ copia a vpc/vpc_config.json)
```

---

## Prerequisitos

- `docker compose up -d` (LocalStack + MiniStack + MinIO + Postgres orígenes)
- OpenTofu: `tofu --version` (≥ 1.6) — o `terraform`
- Python 3 + `boto3` (solo para `iac_demo.py --reconcile`)

```bash
# Instalar OpenTofu (si falta) — ver lab-09.md
tofu --version
```

---

## Camino rápido (recomendado)

Desde la raíz del repo:

```bash
# Primera vez en un entorno donde ya corriste demos imperativos:
python iac/iac_demo.py --reconcile

# Si hay buckets/grupos que no querés borrar, adoptá al state:
# python iac/iac_demo.py --import-existing

# Siguientes veces (idempotente):
python iac/iac_demo.py
```

**Sin instalar OpenTofu en el host** (imagen Docker): ver [`DOCKER.md`](DOCKER.md).

Equivalente manual:

```bash
cd iac/tp
tofu init
tofu plan
tofu apply
# tofu apply de nuevo → "No changes" si nada cambió
```

---

## Variables útiles

Ver `iac/tp/terraform.tfvars.example`. Las más importantes:

| Variable | Default | Significado |
|----------|---------|-------------|
| `enable_ecs_api` | `false` | Hobby: stand-in Compose/EFS dirs. `true` en AWS real / Pro |
| `enable_nat` | `true` | NAT + ruta compute (lab 07-v2) |
| `apply_rds_seed` | `true` | Corre `scripts/post_rds.py` tras RDS |
| `localstack_endpoint` / `ministack_endpoint` / `minio_endpoint` | localhost 4566/4567/9000 | backends locales |

```bash
tofu apply -var="enable_ecs_api=true"   # solo si el endpoint soporta ECS/EFS
```

---

## Idempotencia

1. **Con state** (`iac/tp/terraform.tfstate`, gitignored): `apply` N veces = sin cambios si la realidad coincide.
2. **Tras `destroy` + `apply`**: recrea el grafo completo.
3. **Choque con labs imperativos** (mismo nombre de rol/secret/RDS fuera del state): usar `python iac/iac_demo.py --reconcile` una vez, o importar a mano (`tofu import`).

El state **no** se sube a git (puede contener passwords de `random_password`).

---

## Verificación

```bash
cd iac/tp
tofu output

# IAM
aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role

# VPC
aws --endpoint-url http://localhost:4566 ec2 describe-vpcs \
  --filters Name=tag:ManagedBy,Values=OpenTofu

# Lake
aws --endpoint-url http://localhost:9000 s3 ls

# RDS + secrets
aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db
aws --endpoint-url http://localhost:4567 secretsmanager list-secrets

# Lambda
aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api
```

Runtime que **no** es API Hobby (sigue siendo Compose):

```bash
python ecs/ecs_demo.py          # Airflow ≈ Fargate + DAGs en efs-standin
python lambda/lambda_demo.py    # opcional: ALB stand-in / smoke invoke
```

---

## Layout

```text
iac/
  lab-09.md           # lab pedagógico (bucket + Docker app)
  lab-09-tp.md        # este lab
  iac_demo.py         # init/plan/apply/destroy + reconcile
  aws/                # ejemplo mínimo del lab-09
  tp/                 # stack completo del TP
    main.tf           # orquesta módulos
    providers.tf      # aliases localstack / ministack / minio
    modules/{iam,vpc,s3,cloudwatch,secrets,rds,lambda,ecs}/
    scripts/post_rds.py
    generated/        # zip lambda, inventarios (gitignore)
```

---

## AWS real

1. Un solo `provider "aws"` (sin `endpoints`, credenciales reales).
2. MinIO → S3 real; MiniStack → RDS + Secrets reales.
3. `-var="enable_ecs_api=true"` y completar task definitions / ALB según Solution Architecture.
4. Backend remoto del state (S3 + lock) — fuera del alcance de este lab local.

---

## Cleanup

```bash
python iac/iac_demo.py --destroy
# o: cd iac/tp && tofu destroy
```

---

## Checkpoint

- [ ] `tofu init` en `iac/tp`
- [ ] `tofu apply` crea IAM → VPC → S3 → CW → RDS → Secrets → Lambda
- [ ] Segundo `tofu apply` sin drifts relevantes
- [ ] `vpc/vpc_config.json` regenerado con tags ManagedBy=OpenTofu
- [ ] Secrets `dw/*` listables en MiniStack
- [ ] `tp-gold-api` existe en LocalStack
- [ ] Con `enable_ecs_api=false`, existe marcador en `ecs/efs-standin/.iac-managed`
