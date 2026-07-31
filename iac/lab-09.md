# Lab 09 — Runtime & IaC Foundations: contenedores + OpenTofu

Hasta acá construimos el stack a mano (IAM → EC2 → S3 → VPC → RDS) usando `aws` CLI o boto3. Hoy aprendemos a **declarar** la infra (IaC con OpenTofu) y **empaquetar** la app (Docker), para que todo sea repetible.

> **Las dos capas**
> - **IaC** declara *dónde corre* (infra: buckets, VPCs, roles)
> - **Containers** declaran *qué corre* (app: código + runtime + deps congelados)
>
> Las dos van versionadas en git. Las dos se construyen a partir de archivos, no de clicks.

---

## Prerequisitos

- Branch `lab-09-tuNombre` desde main
- Servicios activos: `docker compose up -d`
- LocalStack respondiendo: `curl -s http://localhost:4566/_localstack/health`
- **OpenTofu instalado**: `tofu --version`
- **Docker funcionando**: `docker --version`

### Instalar OpenTofu (una vez)

En Codespaces / Linux:
```bash
curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
bash install-opentofu.sh --install-method deb
rm install-opentofu.sh
tofu --version
```

Para macOS: `brew install opentofu`. Para otros sistemas, ver https://opentofu.org/docs/intro/install/.

> Si tenés solo `terraform` instalado y no querés bajar `tofu`, todos los comandos funcionan idénticos cambiando `tofu` por `terraform`.

---

## Paso 1 — Mirar la app que vamos a empaquetar

```bash
ls app/
cat app/app.py
cat app/Dockerfile
```

La app es 30 líneas: lee/escribe un objeto en S3, lee de env vars `AWS_ENDPOINT_URL` y `BUCKET`. Es deliberadamente mínima para que el foco sea el ciclo Docker + IaC.

---

## Paso 2 — Build de la imagen Docker

```bash
docker build -t lab-09-app app/
docker images | grep lab-09-app
```

Lo que pasó:
1. Docker leyó el `Dockerfile` línea por línea
2. `FROM python:3.12-slim` → base con Python 3.12
3. `COPY requirements.txt + RUN pip install` → capa cacheada con las deps
4. `COPY app.py` → capa con el código
5. `ENTRYPOINT ["python", "app.py"]` → comando por defecto al `docker run`

**Imagen ≠ contenedor**: la imagen es la "receta congelada" (read-only), el contenedor es una instancia en ejecución de la receta.

---

## Paso 3 — Correr la app contra LocalStack (sin IaC todavía)

```bash
# Crear el bucket a mano (luego lo reemplazaremos con IaC)
awslocal s3 mb s3://lab-09-app-bucket

# Correr la app
docker run --rm --network host \
  -e BUCKET=lab-09-app-bucket \
  -e AWS_ENDPOINT_URL=http://localhost:4566 \
  lab-09-app
```

Output esperado:
```
endpoint = http://localhost:4566
bucket   = lab-09-app-bucket
  ✓ PUT s3://lab-09-app-bucket/hello.txt  (54 bytes)
  ✓ GET s3://lab-09-app-bucket/hello.txt
    contenido: 'hello from app — 2026-06-30T...'
```

**`--network host`** hace que el container comparta la red del host, así puede llegar a `localhost:4566` directo. En producción se usa una red dedicada o el endpoint público del servicio.

Borrá el bucket — lo vamos a recrear con IaC:
```bash
awslocal s3 rb s3://lab-09-app-bucket --force
```

---

## Paso 4 — Mirar la declaración de infra

```bash
ls iac/
ls iac/aws/
cat iac/aws/main.tf
```

> `iac/` tiene 3 carpetas (una por cloud): `aws/`, `gcp/`, `azure/`. El lab obligatorio usa `aws/`. Si te interesa el paralelo multi-cloud, ver `iac/README.md` y `docs/lab-opcional-multi-cloud.md` después.

Lo que declaramos en HCL:
- **`terraform`** — versión requerida y providers
- **`provider "aws"`** — apuntado a LocalStack (flags + endpoints)
- **`resource "aws_s3_bucket"`** — el bucket que en lab 06 creamos con `awslocal s3 mb`
- **`resource "aws_s3_bucket_versioning"`** — versioning ON (decisión heredada)
- **`resource "aws_s3_object"`** — un objeto seed

La diferencia clave: **no decís *cómo* crearlo, decís *qué* querés que exista**. OpenTofu calcula el diff vs el estado actual y aplica los cambios necesarios.

---

## Paso 5 — `tofu init`

```bash
cd iac/aws/
tofu init
```

Lo que pasa:
- Descarga el provider AWS (`hashicorp/aws ~> 5.0`)
- Crea `.terraform/` (gitignored)
- Inicializa el backend (por defecto local — el state vive en `terraform.tfstate`)

---

## Paso 6 — `tofu plan` (leé el diff)

```bash
tofu plan
```

Output muestra:
```
Terraform will perform the following actions:

  # aws_s3_bucket.app will be created
  + resource "aws_s3_bucket" "app" { ... }

  # aws_s3_bucket_versioning.app will be created
  + resource "aws_s3_bucket_versioning" "app" { ... }

  # aws_s3_object.hello will be created
  + resource "aws_s3_object" "hello" { ... }

Plan: 3 to add, 0 to change, 0 to destroy.
```

**Esto es lo distinto vs `aws s3 mb`**: ves el diff ANTES de aplicar. En un equipo, este diff va en el PR para que alguien lo revise.

---

## Paso 7 — `tofu apply`

```bash
tofu apply
# Tipear `yes` para confirmar
```

OpenTofu crea los 3 recursos. Al final imprime los outputs:

```
bucket_name     = "lab-09-app-bucket"
bucket_arn      = "arn:aws:s3:::lab-09-app-bucket"
endpoint        = "http://localhost:4566"
seed_object_url = "s3://lab-09-app-bucket/hello.txt"
```

Verificá:
```bash
awslocal s3 ls s3://lab-09-app-bucket
awslocal s3 cp s3://lab-09-app-bucket/hello.txt -
awslocal s3api get-bucket-versioning --bucket lab-09-app-bucket
```

---

## Paso 8 — Correr la app contra la infra IaC

```bash
cd ..  # volver al root del repo
docker run --rm --network host \
  -e BUCKET=lab-09-app-bucket \
  -e AWS_ENDPOINT_URL=http://localhost:4566 \
  lab-09-app
```

Misma app, mismo bucket — solo cambió quién lo creó.

---

## Paso 9 — `tofu destroy` y `tofu apply` (la prueba de reproducibilidad)

```bash
cd iac/aws/
tofu destroy   # borra todo lo del state
# Tipear `yes`

awslocal s3 ls   # confirmar que el bucket no está

tofu apply     # crea todo de nuevo
# Tipear `yes`

awslocal s3 ls   # bucket de vuelta, idéntico
```

**Esto es reproducibilidad**: el entorno se baja y se levanta con un comando. En equipos con varios entornos (dev/staging/prod), esto significa que `prod` es exactamente igual a `dev`.

---

## Paso 10 — El estado (`terraform.tfstate`)

```bash
cat terraform.tfstate | python3 -m json.tool | head -30
```

El state es donde OpenTofu "recuerda" qué creó. Sin state, no sabría qué destruir.

**En equipo**: el state va en un backend remoto (S3 + DynamoDB lock para AWS), no en el repo. El de este lab queda local porque es ejemplo.

> El `.gitignore` del repo ya excluye `*.tfstate*` — no subirlo NUNCA. Puede contener secretos (passwords, tokens) leídos durante el apply.

---

## Paso 11 — Documentar en `decisions.md`

```
### 011 — IaC declarativa con OpenTofu en lugar de scripts de AWS CLI

Decision: usar OpenTofu (HCL declarativo) para la infra en lugar de scripts
imperativos con aws CLI o boto3.

Contexto: scripts imperativos requieren manejar idempotencia a mano,
ordenar las llamadas, y no muestran el diff antes de aplicar. IaC declarativa
hace eso por nosotros.

Alternativas: Terraform (mismo HCL, licencia BSL desde 2023),
CloudFormation (AWS-only, YAML), AWS CDK (programación), Pulumi.

Tradeoff: hay que aprender HCL y el modelo de state. A favor: diff
antes de aplicar (revisable en PR), destroy/apply idempotente, portabilidad
entre clouds (provider para AWS/GCP/Azure).

Resultado: iac/ en HCL, ejecutable con tofu o terraform indistinto.
Backend local en este lab; remoto (S3 + lock) en el proyecto final.
```

---

## Paso 12 — Cleanup

```bash
cd iac/aws/
tofu destroy   # borra los recursos
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*  # limpia el state local
docker rmi lab-09-app  # opcional: borrar la imagen Docker
```

---

## Checkpoint

- [ ] `app/Dockerfile` lee, `docker build` deja una imagen `lab-09-app`
- [ ] `docker run` de la imagen escribe y lee en LocalStack
- [ ] `iac/main.tf` declara bucket + versioning + objeto seed
- [ ] `tofu init` baja el provider
- [ ] `tofu plan` muestra el diff
- [ ] `tofu apply` crea los 3 recursos
- [ ] `tofu destroy` los borra
- [ ] `tofu apply` los recrea idénticos (reproducibilidad)
- [ ] Decisión 011 en `decisions.md`

---

## Para llevar: Imperativo vs Declarativo

| Aspecto | Scripts (AWS CLI / boto3) | IaC (OpenTofu) |
|---|---|---|
| Estilo | imperativo: "primero esto, después esto" | declarativo: "que exista esto" |
| Idempotencia | tenés que codearla (chequear antes de crear) | la herramienta la garantiza |
| Diff antes de aplicar | no | sí (`tofu plan`) |
| Reproducibilidad | depende del cuidado del script | garantizada |
| Estado | el script no recuerda qué creó | `tfstate` lo recuerda |
| Versionable | sí (Python/bash) | sí (HCL) |
| Portabilidad multi-cloud | reescribís el script | cambiás el provider |

Las dos coexisten en proyectos reales: IaC para infra, scripts para operaciones puntuales (migración de data, debug, ETL ad-hoc). Pero para "levantar el entorno", el camino es IaC.

---

## Para llevar: LocalStack vs AWS real

| Acción | LocalStack | AWS real |
|---|---|---|
| `tofu init/plan/apply/destroy` con provider AWS | ✅ | ✅ |
| `docker build` y `docker run` de la imagen | ✅ | ✅ |
| `aws_s3_bucket`, IAM, EC2, VPC (recursos) | ✅ | ✅ |
| Push a registry real (ECR) | ⚠️ modela | ✅ |
| Orquestación real (ECS/Fargate bajo carga) | ⚠️ parcial | ✅ |
| Backend remoto del state (S3 + DynamoDB lock) | ✅ | ✅ |

El flujo de IaC sobre el stack del lab es indistinguible. Para containers en producción (ECS, EKS), Learner Lab del Mod 11 del AWS Academy.
