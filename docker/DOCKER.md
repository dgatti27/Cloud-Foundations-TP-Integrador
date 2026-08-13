# Empaquetar y levantar el TP con Docker + OpenTofu

Esta guía cubre dos cosas:

1. **Empaquetar** el proyecto en la imagen `tp-integrador-iac` (código + OpenTofu + CLIs) sin perder lo que el IaC necesita (HCL, seeds SQL, handlers Lambda, policies IAM, DAGs/stand-in).
2. **Ejecutar** emuladores + `tofu apply` hasta dejar la infraestructura del TP en línea (idempotente).

Stack OpenTofu: [`../infra`](../infra).  
Deps Python (host y toolbox): [`../requirements.txt`](../requirements.txt).

Archivos Docker en este directorio:

| Archivo | Rol |
|---------|-----|
| [`Dockerfile`](Dockerfile) | Imagen toolbox (`tp-integrador-iac`) |
| [`entrypoint.sh`](entrypoint.sh) | Arranque: wait backends + apply/plan/destroy/shell |
| [`DOCKER.md`](DOCKER.md) | Esta guía |

Quedan en la **raíz** a propósito:

- [`../compose.yaml`](../compose.yaml) — `docker compose up -d` y volúmenes `./apps`, `./ops`, …
- [`../.dockerignore`](../.dockerignore) — se lee junto al **build context** (`.` = raíz)

---

## Qué queda dentro de la imagen

| Incluido en el build | Para qué |
|----------------------|----------|
| `infra/**/*.tf` + lockfile | Declaración OpenTofu + versiones de providers |
| `infra/scripts/post_rds.py` | Seed RDS post-apply |
| `data/rds/seed_tp.sql` | Schemas bronce/gold + roles |
| `apps/api/handler.py`, `query_gold.py` | Zip de `tp-gold-api` |
| `apps/airflow/dags/` (bind mount en runtime) | Stand-in EFS (Hobby) |
| OpenTofu (`tofu`), AWS CLI, Docker CLI, Python | Runtime del toolbox |

> **Nota Windows:** `apps/airflow/logs/` **no** se copia al build (symlinks de Airflow). En ejecución, `compose.yaml` monta `./apps`.

| **No** va en la imagen (a propósito) | Motivo |
|--------------------------------------|--------|
| `*.tfstate*` | State mutable → se monta desde el host (`./infra`) |
| `.terraform/` | Se regenera con `tofu init` |
| `.env` / secretos | Solo en el host |
| `assets/`, PNGs | No hace falta para apply |

El `.dockerignore` de la raíz define exactamente ese corte.

---

## Prerequisitos (host)

- Docker Desktop (o Engine) + Compose v2
- Archivo `.env` en la raíz (partí de `.env.example`) con `LOCALSTACK_AUTH_TOKEN` Hobby
- Puertos libres: `4566`, `4567`, `9000`, `9001`, `5050`, `5432–5434`, `8080`, `8088`, `15432`

```bash
cp .env.example .env
# editá LOCALSTACK_AUTH_TOKEN

# Deps Python en el host (opcional si usás solo el toolbox)
pip install -r requirements.txt
```

---

## Paso a paso — empaquetar (build)

Desde la **raíz del repo** (el context es `.`, el Dockerfile está en `docker/`):

```bash
# Opción A — build vía Compose (recomendado)
docker compose --profile iac build tp-iac

# Opción B — build directo
docker build -f docker/Dockerfile -t tp-integrador-iac:latest .
```

Verificación rápida:

```bash
docker run --rm tp-integrador-iac:latest help
docker run --rm --entrypoint tofu tp-integrador-iac:latest version
```

Rebuild cuando cambies `docker/Dockerfile`, `docker/entrypoint.sh`, `requirements.txt` o archivos que **no** montás como volumen. Los `.tf` montados desde `./infra` se ven al instante sin rebuild.

---

## Paso a paso — dejar todo en línea

### 1) Levantar emuladores + runtime Hobby

```bash
docker compose up -d
docker compose ps
```

Incluye LocalStack, MiniStack, MinIO, Postgres, Airflow (`:8080`), ALB stand-in (`:8088`) y pgAdmin (`:5050`).  
Esperá a que `localstack-integrador`, `ministack-integrador` y `s3-soporte` estén **healthy**.

### 2) Aplicar el IaC desde la imagen

**Primera vez** si ya corriste demos imperativos (roles/buckets/RDS a mano):

```bash
docker compose --profile iac run --rm tp-iac apply-reconcile
```

**Entorno limpio** o re-ejecuciones (idempotente):

```bash
docker compose --profile iac run --rm tp-iac apply
```

Qué hace el container:

1. Espera health de LocalStack / MiniStack / MinIO (DNS internos de Compose)
2. Corre `tofu init` + `tofu apply` en `/workspace/infra`
3. Crea IAM → VPC → S3(MinIO) → CloudWatch → RDS → Secrets → seed SQL → Lambda → marcadores ECS/EFS
4. Persiste el **state** en `./infra/terraform.tfstate` (host)

### 3) Verificar

```bash
docker compose --profile iac run --rm tp-iac tofu output

aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db
aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api
```

Segundo apply (debe converger):

```bash
docker compose --profile iac run --rm tp-iac plan
# → No changes / sin drifts relevantes
```

### 4) Toolbox interactivo

```bash
docker compose --profile iac run --rm tp-iac shell
```

---

## Comandos útiles del entrypoint

| Comando | Efecto |
|---------|--------|
| `apply` (default) | `tofu init` + `apply -auto-approve` en `infra/` |
| `apply-reconcile` | igual que apply |
| `plan` | `tofu init` + plan |
| `destroy` | `tofu destroy -auto-approve` |
| `init` | solo `tofu init` |
| `tofu <args>` | tofu en `infra/` (workdir imagen: `/workspace/infra`) |
| `wait` | solo healthchecks |
| `shell` | bash en `/workspace` |

```bash
docker compose --profile iac run --rm tp-iac tofu state list
```

---

## Por qué montamos volúmenes

```text
./infra           → state + HCL vivos (no se pierden al borrar el container)
./apps, ./data    → handlers/seeds/DAGs actualizados sin rebuild
docker.sock       → post_rds.py hace docker exec al Postgres de MiniStack
```

Si **no** montás `./infra`, el state vive solo en el container y se pierde al `run --rm`.

---

## Diagrama del flujo

```text
Host                         Docker network (compose)
─────                        ────────────────────────
.git repo                    localstack-integrador :4566
  ├─ compose.yaml            ministack-integrador  :4566 (host :4567)
  ├─ docker/Dockerfile build→ s3-soporte (MinIO)   :9000
  ├─ docker/entrypoint.sh    → tp-iac ENTRYPOINT
  ├─ infra/          bind──→ tp-iac (toolbox)
  └─ docker.sock     bind──→    └─ tofu apply
                                 └─ docker exec → ministack-rds-*
```

---

## Cleanup

```bash
docker compose --profile iac run --rm tp-iac destroy

docker compose down
# docker compose down -v   # solo si querés reset total (borra datos)
```

---

## Troubleshooting

| Síntoma | Qué mirar |
|---------|-----------|
| `LOCALSTACK_AUTH_TOKEN` missing | Creá `.env` desde `.env.example` |
| timeout LocalStack/MiniStack | `docker compose ps` / logs; esperá healthy |
| `BucketAlreadyExists` / roles ya existen | `tofu import` / destroy+apply, o `apply-reconcile` |
| `post_rds` no encuentra container RDS | `docker.sock` montado; MiniStack levantó `tp-dw-db` |
| endpoints malos desde el container | Usá `docker compose --profile iac run` (DNS internos); no mezcles `:4567` dentro de la red |
| plan con drifts eternos | Ya mitigado en HCL (lifecycle LocalStack); corré `plan` de nuevo tras un apply limpio |

---

## Relación con el lab sin Docker toolbox

En el host, con OpenTofu instalado:

```bash
docker compose up -d
pip install -r requirements.txt
cd infra && tofu init && tofu apply
```

La imagen solo **empaqueta** ese mismo flujo para que cualquier máquina con Docker pueda repetirlo sin instalar `tofu`/deps a mano.
