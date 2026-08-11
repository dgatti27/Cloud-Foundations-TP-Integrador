# Empaquetar y levantar el TP con Docker + OpenTofu

Esta guía cubre dos cosas:

1. **Empaquetar** el proyecto en la imagen `tp-integrador-iac` (código + OpenTofu + CLIs) sin perder lo que el IaC necesita (HCL, seeds SQL, handlers Lambda, policies IAM, DAGs/stand-in).
2. **Ejecutar** emuladores + `tofu apply` hasta dejar la infraestructura del TP en línea (idempotente).

Guía HCL detallada: [`lab-09-tp.md`](lab-09-tp.md).

---

## Qué queda dentro de la imagen

| Incluido en el build | Para qué |
|----------------------|----------|
| `iac/tp/**/*.tf` + `.terraform.lock.hcl` | Declaración OpenTofu + versiones de providers |
| `iac/iac_demo.py`, `iac/tp/scripts/post_rds.py` | Apply / reconcile / seed RDS |
| `rds/seed_tp.sql` | Schemas bronce/gold + roles |
| `lambda/handler.py`, `query_gold.py` | Zip de `tp-gold-api` |
| `iam/`, `ecs/*.json`, `s3/*policy*` | Referencia / demos |
| `ecs/efs-standin/dags/` (en runtime via bind mount) | Stand-in EFS (Hobby) |
| OpenTofu (`tofu`), AWS CLI, Docker CLI, Python+boto3 | Runtime del toolbox |

> **Nota Windows:** el árbol `ecs/` **no** se copia al build context (symlinks de logs de Airflow rompen Docker Desktop). En ejecución, `docker-compose.iac.yaml` monta `./ecs` completo.

| **No** va en la imagen (a propósito) | Motivo |
|--------------------------------------|--------|
| `*.tfstate*` | State mutable → se monta desde el host (`./iac/tp`) |
| `.terraform/` | Se regenera con `tofu init` |
| `.env` / secretos | Solo en el host |
| `assets/`, PNGs, carpeta Migración… | No hace falta para apply |

El `.dockerignore` de la raíz define exactamente ese corte.

---

## Prerequisitos (host)

- Docker Desktop (o Engine) + Compose v2
- Archivo `.env` en la raíz (partí de `.env.example`) con `LOCALSTACK_AUTH_TOKEN` Hobby
- Puertos libres: `4566`, `4567`, `9000`, `9001`, `5432–5434`, `15432` (RDS MiniStack)

```bash
cp .env.example .env
# editá LOCALSTACK_AUTH_TOKEN
```

---

## Paso a paso — empaquetar (build)

Desde la **raíz del repo**:

```bash
# Opción A — build vía Compose (recomendado)
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac build tp-iac

# Opción B — build directo
docker build -t tp-integrador-iac:latest .
```

Verificación rápida:

```bash
docker run --rm tp-integrador-iac:latest help
docker run --rm --entrypoint tofu tp-integrador-iac:latest version
```

Rebuild cuando cambies `Dockerfile`, `requirements-docker.txt` o archivos que **no** montás como volumen. Los `.tf` montados desde `./iac/tp` se ven al instante sin rebuild.

---

## Paso a paso — dejar todo en línea

### 1) Levantar emuladores (LocalStack + MiniStack + MinIO + Postgres)

```bash
docker compose up -d
docker compose ps
```

Esperá a que `localstack-integrador`, `ministack-integrador` y `s3-soporte` estén **healthy**.

### 2) Aplicar el IaC desde la imagen

**Primera vez** en un entorno donde ya corriste demos imperativos (roles/buckets/RDS a mano):

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac apply-reconcile
```

**Entorno limpio** o re-ejecuciones (idempotente):

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac apply
```

Qué hace el container:

1. Espera health de LocalStack / MiniStack / MinIO (DNS internos de Compose)
2. Corre `python iac/iac_demo.py` → `tofu init` + `tofu apply`
3. Crea IAM → VPC → S3(MinIO) → CloudWatch → RDS → Secrets → seed SQL → Lambda → marcadores ECS/EFS
4. Persiste el **state** en el volumen bind `./iac/tp/terraform.tfstate` (host)

### 3) Verificar

```bash
# Desde el toolbox
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac tofu output

# O desde el host (endpoints localhost)
aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db
aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api
```

Segundo apply (debe converger):

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac plan
# → No changes / sin drifts relevantes
```

### 4) Runtime Hobby (opcional, no es API LocalStack)

```bash
# Airflow ≈ Fargate + DAGs en efs-standin
python ecs/ecs_demo.py

# API / ALB stand-in
python lambda/lambda_demo.py
```

También podés entrar al toolbox:

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac shell
```

---

## Comandos útiles del entrypoint

| Comando | Efecto |
|---------|--------|
| `apply` (default) | `iac_demo.py` → init + apply |
| `apply-reconcile` | limpia choques + apply |
| `plan` | solo plan |
| `destroy` | `tofu destroy -auto-approve` |
| `init` | solo `tofu init` |
| `tofu <args>` | tofu en `iac/tp` |
| `wait` | solo healthchecks |
| `shell` | bash en `/workspace` |

Ejemplo:

```bash
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac tofu state list
```

---

## Por qué montamos volúmenes

```text
./iac/tp          → state + HCL vivos (no se pierden al borrar el container)
./rds, ./lambda…  → seeds/handlers actualizados sin rebuild
docker.sock       → post_rds.py hace docker exec al Postgres de MiniStack
```

Si **no** montás `./iac/tp`, el state vive solo en la capa writable del container y se pierde al `run --rm`.

---

## Diagrama del flujo

```text
Host                         Docker network (compose)
─────                        ────────────────────────
.git repo                    localstack-integrador :4566
  ├─ compose.yaml            ministack-integrador  :4566 (host :4567)
  ├─ Dockerfile      build→  s3-soporte (MinIO)    :9000
  ├─ iac/tp (state)  bind──→ tp-iac (toolbox)
  └─ docker.sock     bind──→    └─ tofu apply
                                 └─ docker exec → ministack-rds-*
```

---

## Cleanup

```bash
# Solo infra declarada en OpenTofu
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac \
  run --rm tp-iac destroy

# Emuladores (CUIDADO: -v borra volúmenes y datos)
docker compose down
# docker compose down -v   # solo si querés reset total
```

---

## Troubleshooting

| Síntoma | Qué mirar |
|---------|-----------|
| `LOCALSTACK_AUTH_TOKEN` missing | Creá `.env` desde `.env.example` |
| timeout LocalStack/MiniStack | `docker compose ps` / logs; esperá healthy |
| `BucketAlreadyExists` / roles ya existen | `apply-reconcile` o `iac_demo.py --import-existing` |
| `post_rds` no encuentra container RDS | `docker.sock` montado; MiniStack levantó `tp-dw-db` |
| endpoints malos desde el container | Usá el compose `docker-compose.iac.yaml` (DNS internos); no mezcles `:4567` dentro de la red |
| plan con drifts eternos | Ya mitigado en HCL (lifecycle LocalStack); corré `plan` de nuevo tras un apply limpio |

---

## Relación con el lab sin Docker toolbox

En el host, con OpenTofu instalado:

```bash
docker compose up -d
python iac/iac_demo.py
```

La imagen solo **empaqueta** ese mismo flujo para que cualquier máquina con Docker pueda repetirlo sin instalar `tofu`/deps a mano.
