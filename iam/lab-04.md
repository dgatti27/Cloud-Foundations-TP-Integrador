# Lab 04 — IAM: identidad, privilegio mínimo y credenciales temporales

Continuamos sobre el stack de la clase 2. No hay nuevos servicios: usamos
LocalStack, que ya estaba en `compose.yaml`, y lo exploramos desde el ángulo
de identidad.

> **LocalStack Community vs enforcement real**
> En Community podés crear y adjuntar policies, usuarios, grupos y roles, y
> hacer `sts:AssumeRole`. Lo que **no** funciona es el enforcement: un `Deny`
> no bloquea la llamada. Para demostrar eso necesitás LocalStack Pro o una
> cuenta AWS real. El lab documenta los puntos donde el comportamiento difiere.

---

## Prerequisitos

- Rama de trabajo: `lab-04-tuNombre` creada desde `main`
- Dependencias instaladas: `pip install -r requirements.txt` (incluye `awscli-local`)
- Servicios activos: `docker compose up -d`
- Verificar LocalStack: `curl -s http://localhost:4566/_localstack/health | python3 -m json.tool`
- Verificar `awslocal`: `awslocal --version` debe responder

> En Codespaces los dos primeros pasos ocurren solos por el `postCreateCommand` del devcontainer. Localmente hay que correrlos a mano la primera vez.

---

## Paso 1 — Explorar lo que ya existe en LocalStack

```bash
awslocal iam list-users
awslocal iam list-roles
# S3 del TP = MinIO (:9000). LocalStack S3 queda fuera (decisión 002):
# awslocal s3 ls
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls
```

Al arrancar, LocalStack no tiene usuarios ni roles: partimos de cero, igual
que una cuenta AWS nueva.

---

## Paso 2 — Crear el bucket S3 de referencia (MinIO)

Los buckets del data lake viven en **MinIO** (`s3-soporte`, puerto 9000), no en LocalStack.
IAM (usuarios/roles/policies) sigue en LocalStack (`:4566`).

```bash
# Credenciales para acceder a minio = MINIO_ROOT_* del compose (default minioadmin/minioadmin)
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-east-1
MINIO="aws --endpoint-url http://localhost:9000 --region us-east-1"

#Crea los buckets
$MINIO s3 mb s3://backup-data-raw
$MINIO s3 mb s3://snapshot-data-raw
$MINIO s3 mb s3://staging-data-raw

$MINIO s3 ls
```

Versió PowerShell:

```powershell
$env:AWS_ACCESS_KEY_ID = "minioadmin"
$env:AWS_SECRET_ACCESS_KEY = "minioadmin"
$env:AWS_DEFAULT_REGION = "us-east-1"
$MINIO = "aws --endpoint-url http://localhost:9000 --region us-east-1"

Invoke-Expression "$MINIO s3 mb s3://backup-data-raw"
Invoke-Expression "$MINIO s3 mb s3://snapshot-data-raw"
Invoke-Expression "$MINIO s3 mb s3://staging-data-raw"
Invoke-Expression "$MINIO s3 ls"
```

Estos buckets son el "recurso protegido" sobre el que referencian las policies IAM (ARNs `arn:aws:s3:::...`). El enforcement real de esas policies contra MinIO no aplica igual que en AWS; el lab enseña el modelo IAM y el storage queda en MinIO (decisión 002).

```bash
# --- Alternativa LocalStack S3 (NO usar en el TP; conservada por referencia) ---
# awslocal s3 mb s3://backup-data-raw
# awslocal s3 mb s3://snapshot-data-raw
# awslocal s3 mb s3://staging-data-raw
# awslocal s3 ls
```

---

## Paso 3 — Crear grupo con política administrada

```bash
# grupo
awslocal iam create-group --group-name bi-ops
awslocal iam create-group --group-name bi-admin

# política administrada (equivalente a AmazonS3ReadOnlyAccess, acotada al bucket)
awslocal iam create-policy --policy-name S3AdminTP --policy-document file://iam/s3_admin_policy.json

awslocal iam create-policy --policy-name S3RWTP --policy-document file://iam/s3_readwrite_policy.json

# adjuntar al grupo - ASociar las políticas con el grupo
awslocal iam attach-group-policy --group-name bi-ops --policy-arn arn:aws:iam::000000000000:policy/S3RWTP

awslocal iam attach-group-policy --group-name bi-admin --policy-arn arn:aws:iam::000000000000:policy/S3AdminTP
```

## Paso 4 — Crear usuario y asignarlo al grupo

```bash
awslocal iam create-user --user-name usuario1-admin
awslocal iam create-user --user-name usuario2-ops
awslocal iam add-user-to-group --group-name bi-ops --user-name usuario2-ops
awslocal iam add-user-to-group --group-name bi-admin --user-name usuario1-admin

# verificar membresía
awslocal iam get-group --group-name bi-admin
```

En este punto el usuario tiene acceso a S3 por pertenecer al grupo.
No tiene credenciales propias todavía.

---

## Paso 5 — Crear access key (llave de larga duración — observar el riesgo)

```bash
awslocal iam create-access-key --user-name lab-user
```

Guardá el `AccessKeyId` y `SecretAccessKey` que devuelve. Son credenciales de
larga duración: no expiran, no dejan rastro de quién las usó, y si se filtran
dan acceso indefinido.

> **Por qué esto es riesgoso en producción**: una access key en un repo, en
> logs o en una variable de entorno mal protegida es un incidente de seguridad.
> La solución es usar roles con STS (paso 7).

---

## Paso 6 — Crear rol con trust policy para ECS y RDS. (identidad para servicios) en lugar de usuarios con access keys fijas.

```bash
awslocal iam create-role --role-name app-role --assume-role-policy-document file://iam/trust_policy_ecs.json

awslocal iam put-role-policy --role-name app-role --policy-name InlineS3Read --policy-document file://iam/s3_readwrite_policy.json

awslocal iam create-role --role-name db-role --assume-role-policy-document file://iam/trust_policy_rds_export.json

awslocal iam put-role-policy --role-name db-role --policy-name InlineS3Read --policy-document file://iam/s3_readwrite_policy.json

awslocal iam get-role --role-name app-role

awslocal iam get-role --role-name db-role
```
Hace tres cosas por cada rol:
  Crear el rol con una trust policy — quién puede asumirlo:
      app-role → solo ecs-tasks.amazonaws.com (tareas ECS)
      db-role → solo export.rds.amazonaws.com (export de RDS)
  Adjuntar permisos (put-role-policy) — qué puede hacer una vez asumido: leer/escribir en los buckets S3 definidos en s3_readwrite_policy.json.
Verificar con get-role que quedaron creados.

La idea: un servicio (ECS, RDS) no usa claves permanentes de un usuario; pide a STS “actuar como este rol” y recibe credenciales temporales (eso es el Paso 7).

Revisá `iam/trust_policy_ecs.json`: el `Principal` es `ecs.amazonaws.com`.
Eso significa que solo una instancia ECS (o en LocalStack, cualquier caller)
puede asumir este rol — no cualquier usuario.

---

## Paso 7 — AssumeRole vía STS → credenciales temporales

ECS (o un servicio) cuando asume el rol y obtiene credenciales temporales con STS.
sts assume-role pide a IAM: “quiero actuar como app-role durante 15 min (900 s)”.
STS responde con un trío temporal: AccessKeyId, SecretAccessKey y SessionToken (+ Expiration).
Exportás esas variables y con ellas listás S3: ya no usás el usuario permanente, sino la identidad del rol.
Es el patrón de privilegio mínimo: el rol tiene los permisos S3; quien lo asume recibe claves que caducan, en lugar de access keys fijas de un usuario.

```bash
awslocal sts assume-role --role-arn arn:aws:iam::000000000000:role/app-role --role-session-name TP-App-session --duration-seconds 900

awslocal sts assume-role --role-arn arn:aws:iam::000000000000:role/db-role --role-session-name TP-DB-session --duration-seconds 900

# Listar buckets en MinIO (no awslocal):
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://backup-data-raw --recursive
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://snapshot-data-raw --recursive
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://staging-data-raw --recursive
```

El response tiene tres campos clave:
- `AccessKeyId`: empieza con `ASIA` (en AWS real; en LocalStack es diferente)
- `SecretAccessKey`: rotatoria
- `SessionToken`: obligatorio para autenticar
- `Expiration`: **las credenciales expiran** — en 15 minutos en este ejemplo

Usá esas credenciales para listar en MinIO (mismo endpoint `:9000`):

```bash
export AWS_ACCESS_KEY_ID="minioadmin"
export AWS_SECRET_ACCESS_KEY="minioadmin"

aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://backup-data-raw --recursive
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://snapshot-data-raw --recursive
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://staging-data-raw --recursive
```

---

## Paso 8 — Script automatizado e IaC

El script `iam/iam_demo.py` hace los pasos 2–7 en secuencia:

```bash
python iam/iam_demo.py
```

Sirve como referencia y para reproducir el setup en un entorno limpio.

**Alternativa OpenTofu** (misma infra declarativa; demos en Python):

| Capa | Herramienta |
|---|---|
| Infra (pasos 2–4, 6) | `cd iam/iac && tofu apply` |
| Demos (pasos 5 y 7) | `python iam/iam_demo.py --skip-infra` |

Detalle en `iam/iac/README.md`. No corras infra Python y OpenTofu a la vez sin limpiar.

---

## Paso 9 — Dónde falla LocalStack Community (documentar en decisions.md)

En Community, un `Deny` explícito no bloquea la llamada:

```bash
# esto en AWS real bloquearía al usuario — en LocalStack Community pasa igual
awslocal iam put-user-policy \
  --user-name lab-user \
  --policy-name DenyEverything \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'

# Si los buckets estuvieran en LocalStack S3 (comentado — TP usa MinIO):
# awslocal s3 ls s3://backup-data-raw   # en Community: seguiría funcionando

# En el TP el storage es MinIO (IAM no lo enforcea de todos modos):
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls s3://backup-data-raw
```

> En AWS real (y LocalStack Pro), el Deny explícito siempre gana sobre cualquier
> Allow. Esta es la regla más importante del modelo de evaluación de políticas.

---

## Paso 10 — Documentar en decisions.md

Agregá una decisión con este formato:

```
### 005 - Identidad y credenciales en el lab

Decision: usar roles con STS en lugar de access keys de larga duración para acceso entre servicios.

Contexto: las access keys no expiran y si se filtran dan acceso indefinido.
Los roles con STS generan credenciales temporales (15 min a 12 hs) con trazabilidad.

Alternativas: access keys rotadas manualmente, vault/secret manager.

Tradeoff: asumir un rol requiere que el servicio tenga permiso de sts:AssumeRole
y que el rol tenga un trust policy correcto. Más configuración inicial, menos riesgo.

Resultado: app-role con inline policy de privilegio mínimo sobre course-data-raw.
```

---

## Checkpoint

Al finalizar deberías poder mostrar:

- [ ] Buckets `backup-data-raw` / `snapshot-data-raw` / `staging-data-raw` en **MinIO** (`:9000`)
- [ ] Grupos `bi-ops` / `bi-admin` con policies adjuntadas
- [ ] Usuarios `usuario2-ops` / `usuario1-admin` en sus grupos
- [ ] Rol `app-role` (y `db-role`) con trust policy + inline policy
- [ ] Output del `sts assume-role` con `Expiration` visible
- [ ] Decisión 005 en `docs/decisions.md`

---

## Para llevar: en AWS real vs LocalStack

| Acción                        | LocalStack Community | AWS real          |
|-------------------------------|----------------------|-------------------|
| Crear users/groups/roles      | ✅                   | ✅                |
| Adjuntar policies             | ✅                   | ✅                |
| `sts:AssumeRole`              | ✅                   | ✅                |
| Enforcement de Deny           | ❌                   | ✅                |
| MFA virtual                   | ❌                   | ✅                |
| CloudTrail (trazabilidad)     | ❌                   | ✅                |
