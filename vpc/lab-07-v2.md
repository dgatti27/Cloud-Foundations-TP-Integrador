# Lab 07 v2 — Redes Multi-AZ: VPC para ALB, RDS, ECS Fargate, Lambda y EFS

Versión del lab orientada al **TP Integrador**, no al ejemplo EC2 del `lab-07.md` original.

Cierra el arco **IAM (04) → S3 (06) → red que los une (hoy)** con la topología real del proyecto:

```text
BI (Internet) → IGW → ALB HTTPS (públicas Multi-AZ) → Lambda API (compute)
ETL ECS Fargate (compute) → NAT → Internet (fuentes: ERP, Mongo, scraping)
ETL / API / RDS → VPC endpoint Gateway → S3 (data lake, sin Internet)
ETL / API → RDS (privadas Multi-AZ)
ETL → EFS (NFS en compute)
```

> **LocalStack Community vs AWS real**  
> La topología (VPC, subredes, route tables, IGW, NAT, SGs, endpoints) se crea y se inspecciona en Community. El tráfico real de paquetes (NAT, ALB balanceando, Fargate saliendo a Internet) se valida mejor en AWS real / Learner Lab.

### Tres caminos (mismo alcance)

| Camino | Infra VPC / SG / NAT / vpce | Inventario |
|---|---|---|
| CLI (`lab-07-v2.md` pasos) | A mano | Variables de shell |
| Bash | `bash vpc/provision_vpc_v2.sh` (**se preserva**) | Echo al final |
| **OpenTofu** | `cd vpc/iac && tofu apply` | Escribe `vpc/vpc_config.json` |

El script bash **no se elimina**: sigue siendo el espejo de los comandos del lab. OpenTofu declara el estado deseado e idempotencia; no mezcles ambos sin `destroy`/limpieza previa.

---

## Por qué este lab (v2)

- El lab 07 original modela **EC2 pública + privada + S3**.
- El TP necesita: **ALB** (entrada HTTPS para BI), **NAT** (salida de ETL a fuentes), **RDS Multi-AZ**, **ECS + Lambda + EFS** en privadas, y **endpoint a S3** (storage sin NAT).
- Hoy armamos el **esqueleto de red** del Proyecto Final.

---

## Prerequisitos

- Branch de trabajo desde `main`
- Lab 04 corrido (`app-role`, policies IAM)
- Lab 06 corrido — buckets lake en **MinIO** (`:9000`): `backup-data-lake`, `snapshot-data-lake`, `staging-data-lake`
- Servicios activos: `docker compose up -d` (LocalStack para EC2/VPC; MinIO para el lake)
- `awslocal --version` responde

```bash
# Verificar dependencias
awslocal iam get-role --role-name app-role --query "Role.Arn"

# Lake = MinIO (decisión 002). LocalStack S3 queda comentado en compose.
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls | findstr data-lake
# Linux/macOS: aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls | grep data-lake

# --- LocalStack S3 (NO usar en el TP) ---
# awslocal s3 ls | findstr data-lake
```

Variables usadas en todos los pasos:

```bash
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AZ_A="${REGION}a"
AZ_B="${REGION}b"
AWS="${AWS_CLI:-awslocal}"
```
```powershell
if (-not $env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION = "us-east-1" }
$REGION = $env:AWS_DEFAULT_REGION
$AZ_A = "${REGION}a"
$AZ_B = "${REGION}b"
$AWS = if ($env:AWS_CLI) { $env:AWS_CLI } else { "awslocal" }
```
---

## Mapa CIDR (referencia)

```text
VPC 10.0.0.0/16
├── AZ-a                              AZ-b
├── 10.0.1.0/24  public-alb-a         10.0.2.0/24  public-alb-b       → ALB (+ NAT en A)
├── 10.0.10.0/24 private-rds-a        10.0.11.0/24 private-rds-b      → RDS Multi-AZ
└── 10.0.20.0/24 private-compute-a    10.0.21.0/24 private-compute-b  → ECS + Lambda + EFS
```

---

## Paso 1 — Crear la VPC

Contenedor de red: espacio de direcciones + DNS. Todavía no hay subredes ni Internet.

```bash
VPC_ID=$($AWS ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --query "Vpc.VpcId" --output text)

# Es una ruta JMESPath sobre la respuesta JSON de create-vpc.
# La API devuelve algo así:
#{
#  "Vpc": {
#    "VpcId": "vpc-0a1b2c3d4e5f67890",
#    "CidrBlock": "10.0.0.0/16",
#    ...
#  }
#}
#--query "Vpc.VpcId" significa: entrá al objeto Vpc y sacá el campo VpcId.
#Con --output text solo imprime el string (vpc-...), sin JSON, para poder guardarlo en $VPC_ID

$AWS ec2 create-tags --resources "$VPC_ID" --tags \
  Key=Name,Value=tp-integrador-vpc \
  Key=Project,Value=TP-Integrador \
  Key=Lab,Value=07-v2

#Activar 2 atributos DNS de la vpc
$AWS ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
$AWS ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support

echo "VPC: $VPC_ID"
```

### Qué hace cada parte

| Pieza | Detalle |
|---|---|
| `10.0.0.0/16` | 65.536 IPs privadas (RFC1918). Rango típico de lab/TP; AWS permite `/16`–`/28`. |
| Tags | Identificación FinOps/ops (`Name`, `Project`, `Lab`). |
| `enable-dns-support` | Resolver DNS de Amazon dentro de la VPC (necesario para RDS, endpoints, etc.). |
| `enable-dns-hostnames` | Hostnames DNS privados para recursos (útil para conexiones por host). |

Sin VPC no hay aislamiento: todo lo demás (subredes, SG, NAT, endpoints) vive **dentro** de este CIDR.

---

## Paso 2 — Subredes Multi-AZ (HA por diseño)

**Cada subred vive en UNA AZ.** ALB, RDS Multi-AZ y EFS/Fargate piden ≥2 AZs.

```bash
# Públicas — ALB HTTPS (BI → API)
SUBNET_PUBLIC_A=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "$AZ_A" \
  --query "Subnet.SubnetId" --output text)
SUBNET_PUBLIC_B=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "$AZ_B" \
  --query "Subnet.SubnetId" --output text)

# Privadas RDS — DB subnet group Multi-AZ
SUBNET_RDS_A=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.10.0/24 --availability-zone "$AZ_A" \
  --query "Subnet.SubnetId" --output text)
SUBNET_RDS_B=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.11.0/24 --availability-zone "$AZ_B" \
  --query "Subnet.SubnetId" --output text)

# Privadas compute — ECS Fargate (ETL) + Lambda API + EFS
SUBNET_COMPUTE_A=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.20.0/24 --availability-zone "$AZ_A" \
  --query "Subnet.SubnetId" --output text)
SUBNET_COMPUTE_B=$($AWS ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.21.0/24 --availability-zone "$AZ_B" \
  --query "Subnet.SubnetId" --output text)

$AWS ec2 create-tags --resources "$SUBNET_PUBLIC_A" --tags \
  Key=Name,Value=public-alb-a Key=Tier,Value=public Key=Role,Value=alb
$AWS ec2 create-tags --resources "$SUBNET_PUBLIC_B" --tags \
  Key=Name,Value=public-alb-b Key=Tier,Value=public Key=Role,Value=alb
$AWS ec2 create-tags --resources "$SUBNET_RDS_A" --tags \
  Key=Name,Value=private-rds-a Key=Tier,Value=private Key=Role,Value=rds
$AWS ec2 create-tags --resources "$SUBNET_RDS_B" --tags \
  Key=Name,Value=private-rds-b Key=Tier,Value=private Key=Role,Value=rds
$AWS ec2 create-tags --resources "$SUBNET_COMPUTE_A" --tags \
  Key=Name,Value=private-compute-a Key=Tier,Value=private Key=Role,Value=ecs-lambda-efs
$AWS ec2 create-tags --resources "$SUBNET_COMPUTE_B" --tags \
  Key=Name,Value=private-compute-b Key=Tier,Value=private Key=Role,Value=ecs-lambda-efs

$AWS ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_A" --map-public-ip-on-launch
$AWS ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_B" --map-public-ip-on-launch

# Hace que, en esa subnet pública, cada instancia/ENI nueva reciba una IP pública automáticamente al lanzarse.
# Sin ese flag, solo tendría IP privada y no saldría a Internet aunque haya Internet Gateway (salvo que le asignes una IP pública a mano).
#Solo tiene sentido en subnets públicas (las del ALB: SUBNET_PUBLIC_A / B). En las privadas (RDS, compute) no se usa.

echo "Públicas ALB:  $SUBNET_PUBLIC_A ($AZ_A) | $SUBNET_PUBLIC_B ($AZ_B)"
echo "Privadas RDS:  $SUBNET_RDS_A ($AZ_A) | $SUBNET_RDS_B ($AZ_B)"
echo "Privadas cmp:  $SUBNET_COMPUTE_A ($AZ_A) | $SUBNET_COMPUTE_B ($AZ_B)"
```

### Por qué 6 subredes

| Par | Rol |
|---|---|
| 2 públicas | ALB exige subredes en **≥2 AZs** |
| 2 privadas RDS | DB subnet group Multi-AZ (primary + standby en otra AZ) |
| 2 privadas compute | Tasks Fargate, ENIs de Lambda y mount targets EFS repartidos |

`/24` = 256 IPs; AWS reserva 5 → ~251 utilizables por subred.

---

## Paso 3 — Internet Gateway (puerta a Internet)

```bash
IGW_ID=$($AWS ec2 create-internet-gateway \
  --query "InternetGateway.InternetGatewayId" --output text)
$AWS ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
#Conecta IGW a la VPC
$AWS ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value=tp-igw
echo "IGW: $IGW_ID"
```

### Detalle

- El IGW **attached** a la VPC aún no mueve tráfico solo: hace falta la **ruta** en la route table pública (paso 4).
- Sirve para:
  - **Entrada**: BI → ALB HTTPS.
  - **Base del NAT**: el NAT (paso 6) vive en pública y usa el IGW por debajo para salir.

---

## Paso 4 — Route table pública (esto hace públicas a las subredes del ALB)

**No existe un flag "make subnet public".** Una subred es pública **si y solo si** su route table tiene `0.0.0.0/0 → IGW`.

```bash
RT_PUBLIC=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" \
  --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_PUBLIC" --tags Key=Name,Value=rt-public-alb

$AWS ec2 create-route \
  --route-table-id "$RT_PUBLIC" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"

#Cre la ruta por defecto asociado a la tabla de ruteo
#Todo lo que no sea tráfico local de la VPC (0.0.0.0/0 = “cualquier destino”) → salir por el Internet Gateway ($IGW_ID).

$AWS ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_A"
$AWS ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_B"
#Asocia la subnet publica a la tabla de ruteo

$AWS ec2 describe-route-tables --route-table-ids "$RT_PUBLIC" \
  --query "RouteTables[0].Routes"
```

Flujo de entrada:

```text
BI (Internet) → IGW → ALB (subredes públicas, Multi-AZ) → Lambda (compute, paso 7 SGs)
```

---

## Paso 5 — Route tables privadas - Lo mismo que el paso 4 pero para las subnet privadas

Dos tablas: **RDS** (sin Internet) y **compute** (después le agregamos NAT solo a esta).

```bash
# RDS: solo tráfico local VPC
RT_RDS=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" \
  --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_RDS" --tags Key=Name,Value=rt-private-rds
$AWS ec2 associate-route-table --route-table-id "$RT_RDS" --subnet-id "$SUBNET_RDS_A"
$AWS ec2 associate-route-table --route-table-id "$RT_RDS" --subnet-id "$SUBNET_RDS_B"

# Compute: aún sin 0.0.0.0/0 (NAT en el paso 6)
RT_COMPUTE=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" \
  --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_COMPUTE" --tags Key=Name,Value=rt-private-compute
$AWS ec2 associate-route-table --route-table-id "$RT_COMPUTE" --subnet-id "$SUBNET_COMPUTE_A"
$AWS ec2 associate-route-table --route-table-id "$RT_COMPUTE" --subnet-id "$SUBNET_COMPUTE_B"
```

### Detalle

- Lo que aísla es la **ausencia** de ruta a IGW/NAT (hasta que explícitamente la agregues).
- Separar `RT_RDS` y `RT_COMPUTE` permite: ETL sale a Internet; **RDS no**.

---

## Paso 6 — NAT Gateway + Security Groups

En el script del TP este paso tiene dos mitades:

1. **NAT** — salida de los ETL a fuentes en Internet.  
2. **Security Groups** — firewall entre ALB, API, ETL, RDS y EFS.

### 6.1 NAT Gateway (solo salida ETL → Internet)

```bash
# Elastic IP pública fija para el NAT
EIP_ALLOC=$($AWS ec2 allocate-address --domain vpc \
  --query "AllocationId" --output text)

# El NAT vive en subred PÚBLICA (usa el IGW por debajo)
NAT_ID=$($AWS ec2 create-nat-gateway \
  --subnet-id "$SUBNET_PUBLIC_A" \
  --allocation-id "$EIP_ALLOC" \
  --query "NatGateway.NatGatewayId" --output text)

$AWS ec2 create-tags --resources "$NAT_ID" --tags Key=Name,Value=tp-nat-etl
$AWS ec2 create-tags --resources "$EIP_ALLOC" --tags Key=Name,Value=tp-nat-eip

# En AWS real esperar available; en LocalStack el waiter puede no existir
$AWS ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID" 2>/dev/null || \
  echo "WARN: wait nat-gateway-available no disponible; continuar"

# La ruta crítica: solo COMPUTE sale (ECS); RDS no
#La salida de la subnet compute hacia las fuentes de datos
$AWS ec2 create-route \
  --route-table-id "$RT_COMPUTE" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_ID"
```

#### Qué hace cada comando

| Comando | Rol |
|---|---|
| `allocate-address --domain vpc` | Reserva una **EIP** (IP pública estable). Las fuentes verán esa IP (útil para allowlists). |
| `create-nat-gateway` en `SUBNET_PUBLIC_A` | Crea el NAT **en la pública**; traduce IPs privadas de compute → EIP. |
| `wait nat-gateway-available` | Evita crear la ruta mientras el NAT está `pending` (~1–2 min en AWS real). |
| `create-route … --nat-gateway-id` en `RT_COMPUTE` | Todo lo no-local (`0.0.0.0/0`) de ECS/Lambda sale por el NAT. **No** se agrega a `RT_RDS`. |

```text
ECS ETL (10.0.20.x) → RT_COMPUTE 0.0.0.0/0 → NAT (EIP) → IGW → Internet (fuentes)
RDS (10.0.10.x)    → RT_RDS sin 0.0.0.0/0 → no sale a Internet
```

> **FinOps:** el NAT se cobra por hora + datos. Un solo NAT en AZ-a alcanza para el lab; en prod HA conviene un NAT por AZ.

### 6.2 Security Groups (referencia SG→SG, no por IP)

```text
BI --:443--> ALB (sg-alb) --:443--> Lambda API (sg-api) --:5432--> RDS (sg-rds)
ETL ECS (sg-ecs-etl) --:5432--> RDS | --:2049--> EFS | --NAT--> Internet (fuentes)
```

```bash
# ALB: HTTPS desde BI/Internet
SG_ALB=$($AWS ec2 create-security-group \
  --vpc-id "$VPC_ID" \
  --group-name sg-alb \
  --description "ALB HTTPS — entrada desde BI/Internet" \
  --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ALB" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
# En prod: restringir CIDR a IPs del BI si se conocen

# Lambda API: solo desde el ALB
SG_API=$($AWS ec2 create-security-group \
  --vpc-id "$VPC_ID" \
  --group-name sg-api \
  --description "Lambda API — solo desde ALB" \
  --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_API" \
  --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,UserIdGroupPairs=[{GroupId=$SG_ALB,Description='Solo desde ALB'}]"

# ECS ETL: sin ingress desde Internet; egress default permite salir por NAT
SG_ECS_ETL=$($AWS ec2 create-security-group \
  --vpc-id "$VPC_ID" \
  --group-name sg-ecs-etl \
  --description "ECS Fargate ETL — egress a fuentes vía NAT y a RDS/EFS/S3" \
  --query "GroupId" --output text)

# RDS: Postgres solo desde API y ETL
SG_RDS=$($AWS ec2 create-security-group \
  --vpc-id "$VPC_ID" \
  --group-name sg-rds \
  --description "RDS PostgreSQL — solo desde Lambda API y ECS ETL" \
  --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_RDS" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$SG_API,Description='Lambda API'},{GroupId=$SG_ECS_ETL,Description='ECS ETL'}]"

# EFS: NFS solo desde ETL
SG_EFS=$($AWS ec2 create-security-group \
  --vpc-id "$VPC_ID" \
  --group-name sg-efs \
  --description "EFS — NFS 2049 solo desde ECS ETL" \
  --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_EFS" \
  --ip-permissions "IpProtocol=tcp,FromPort=2049,ToPort=2049,UserIdGroupPairs=[{GroupId=$SG_ECS_ETL,Description='ECS ETL'}]"

$AWS ec2 create-tags --resources "$SG_ALB" --tags Key=Name,Value=sg-alb
$AWS ec2 create-tags --resources "$SG_API" --tags Key=Name,Value=sg-api
$AWS ec2 create-tags --resources "$SG_ECS_ETL" --tags Key=Name,Value=sg-ecs-etl
$AWS ec2 create-tags --resources "$SG_RDS" --tags Key=Name,Value=sg-rds
$AWS ec2 create-tags --resources "$SG_EFS" --tags Key=Name,Value=sg-efs

echo "SG_ALB=$SG_ALB | SG_API=$SG_API | SG_ECS_ETL=$SG_ECS_ETL | SG_RDS=$SG_RDS | SG_EFS=$SG_EFS"

$AWS ec2 describe-security-groups --group-ids "$SG_RDS" \
  --query "SecurityGroups[0].IpPermissions"
```

| SG | Ingress | Egress típico |
|---|---|---|
| `sg-alb` | 443 desde Internet | Hacia targets (`sg-api`) |
| `sg-api` | 443 (o puerto del TG) solo desde `sg-alb` | 5432 a RDS; S3 vía endpoint |
| `sg-ecs-etl` | Ninguno desde Internet | `0.0.0.0/0` (NAT→fuentes); RDS; EFS; S3 |
| `sg-rds` | 5432 solo desde `sg-api` y `sg-ecs-etl` | Mínimo |
| `sg-efs` | 2049 solo desde `sg-ecs-etl` | — |

**SG→SG > CIDR:** el ALB y las tasks cambian de IP; la regla “solo quien tenga `sg-alb`” sigue valiendo.  
SGs son **stateful** y **solo allow**.

---

## Paso 7 — VPC endpoint Gateway a S3 (modelo AWS / to-be)

El endpoint es al **servicio S3 de la región AWS** (`com.amazonaws.<region>.s3`), no a un bucket por nombre ni a MinIO.

**En el TP (local):**
- El **data lake** vive en **MinIO** (`:9000`) — lab 06 / decisión 002.
- Este Gateway endpoint **no enruta** a MinIO; modela el camino de red que en AWS real usarán ETL/API/RDS hacia S3 **sin NAT**.
- Quién autoriza en AWS: **IAM + bucket policy**. En local, MinIO usa sus propias keys/policies.

```bash
ENDPOINT_S3=$($AWS ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${REGION}.s3" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$RT_COMPUTE" "$RT_RDS" \
  --query "VpcEndpoint.VpcEndpointId" --output text)
#Crea un VPC Endpoint Gateway hacia S3 de AWS.
#En concreto:
#create-vpc-endpoint — abre un camino privado VPC → servicio S3 (com.amazonaws.<region>.s3), tipo Gateway (sin ENI; agrega rutas en las route tables).
#Lo asocia a $RT_COMPUTE y $RT_RDS — ETL y RDS pueden ir a S3 sin pasar por el NAT/Internet.

$AWS ec2 create-tags --resources "$ENDPOINT_S3" --tags Key=Name,Value=vpce-s3-datalake
echo "ENDPOINT_S3=$ENDPOINT_S3"

$AWS ec2 describe-route-tables --route-table-ids "$RT_COMPUTE" \
  --query "RouteTables[0].Routes"
$AWS ec2 describe-route-tables --route-table-ids "$RT_RDS" \
  --query "RouteTables[0].Routes"
```

```bash
# Verificar lake local (MinIO), no LocalStack S3:
aws --endpoint-url http://localhost:9000 --region us-east-1 s3 ls
# awslocal s3 ls   # NO usar en el TP
```

### Rutas que quedan

**`RT_COMPUTE`:**

1. `10.0.0.0/16 → local` — API/ETL ↔ RDS, EFS  
2. `pl-* (S3) → vpce-*` — data lake **sin Internet**  
3. `0.0.0.0/0 → nat-*` — solo **fuentes externas**

**`RT_RDS`:**

1. `10.0.0.0/16 → local`  
2. `pl-* → vpce-*` — export/snapshots a S3 sin Internet  
3. **Sin** `0.0.0.0/0`

```text
ETL ──NAT──► Internet (fuentes)
ETL / API / RDS ──vpce──► S3 AWS (to-be; modelado en LocalStack EC2)
En local el lake operativo ──► MinIO :9000 (lab 06)
BI ──IGW──► ALB ──► Lambda API
```

Cierra el arco: IAM (04) + MinIO lake (06) + topología de red to-be (endpoint S3 + NAT solo para orígenes).

---

## Script completo (pasos 1–7)

Podés correr el lab de un tirón (bash / Git Bash / WSL). En PowerShell nativo conviene paso a paso o WSL.

```bash
#!/usr/bin/env bash
# VPC Multi-AZ — TP Integrador (lab-07-v2)
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AZ_A="${REGION}a"
AZ_B="${REGION}b"
AWS="${AWS_CLI:-awslocal}"

echo "== 1. VPC =="
VPC_ID=$($AWS ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --query "Vpc.VpcId" --output text)
$AWS ec2 create-tags --resources "$VPC_ID" --tags \
  Key=Name,Value=tp-integrador-vpc Key=Project,Value=TP-Integrador Key=Lab,Value=07-v2
$AWS ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
$AWS ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
echo "VPC: $VPC_ID"

echo "== 2. Subredes Multi-AZ =="
SUBNET_PUBLIC_A=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "$AZ_A" --query "Subnet.SubnetId" --output text)
SUBNET_PUBLIC_B=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "$AZ_B" --query "Subnet.SubnetId" --output text)
SUBNET_RDS_A=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.10.0/24 --availability-zone "$AZ_A" --query "Subnet.SubnetId" --output text)
SUBNET_RDS_B=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.11.0/24 --availability-zone "$AZ_B" --query "Subnet.SubnetId" --output text)
SUBNET_COMPUTE_A=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.20.0/24 --availability-zone "$AZ_A" --query "Subnet.SubnetId" --output text)
SUBNET_COMPUTE_B=$($AWS ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.21.0/24 --availability-zone "$AZ_B" --query "Subnet.SubnetId" --output text)

$AWS ec2 create-tags --resources "$SUBNET_PUBLIC_A" --tags Key=Name,Value=public-alb-a Key=Tier,Value=public Key=Role,Value=alb
$AWS ec2 create-tags --resources "$SUBNET_PUBLIC_B" --tags Key=Name,Value=public-alb-b Key=Tier,Value=public Key=Role,Value=alb
$AWS ec2 create-tags --resources "$SUBNET_RDS_A" --tags Key=Name,Value=private-rds-a Key=Tier,Value=private Key=Role,Value=rds
$AWS ec2 create-tags --resources "$SUBNET_RDS_B" --tags Key=Name,Value=private-rds-b Key=Tier,Value=private Key=Role,Value=rds
$AWS ec2 create-tags --resources "$SUBNET_COMPUTE_A" --tags Key=Name,Value=private-compute-a Key=Tier,Value=private Key=Role,Value=ecs-lambda-efs
$AWS ec2 create-tags --resources "$SUBNET_COMPUTE_B" --tags Key=Name,Value=private-compute-b Key=Tier,Value=private Key=Role,Value=ecs-lambda-efs
$AWS ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_A" --map-public-ip-on-launch
$AWS ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_B" --map-public-ip-on-launch

echo "== 3. IGW =="
IGW_ID=$($AWS ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
$AWS ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
$AWS ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value=tp-igw

echo "== 4. RT pública =="
RT_PUBLIC=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_PUBLIC" --tags Key=Name,Value=rt-public-alb
$AWS ec2 create-route --route-table-id "$RT_PUBLIC" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"
$AWS ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_A"
$AWS ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_B"

echo "== 5. RT privadas =="
RT_RDS=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_RDS" --tags Key=Name,Value=rt-private-rds
$AWS ec2 associate-route-table --route-table-id "$RT_RDS" --subnet-id "$SUBNET_RDS_A"
$AWS ec2 associate-route-table --route-table-id "$RT_RDS" --subnet-id "$SUBNET_RDS_B"
RT_COMPUTE=$($AWS ec2 create-route-table --vpc-id "$VPC_ID" --query "RouteTable.RouteTableId" --output text)
$AWS ec2 create-tags --resources "$RT_COMPUTE" --tags Key=Name,Value=rt-private-compute
$AWS ec2 associate-route-table --route-table-id "$RT_COMPUTE" --subnet-id "$SUBNET_COMPUTE_A"
$AWS ec2 associate-route-table --route-table-id "$RT_COMPUTE" --subnet-id "$SUBNET_COMPUTE_B"

echo "== 6.1 NAT =="
EIP_ALLOC=$($AWS ec2 allocate-address --domain vpc --query "AllocationId" --output text)
NAT_ID=$($AWS ec2 create-nat-gateway --subnet-id "$SUBNET_PUBLIC_A" --allocation-id "$EIP_ALLOC" --query "NatGateway.NatGatewayId" --output text)
$AWS ec2 create-tags --resources "$NAT_ID" --tags Key=Name,Value=tp-nat-etl
$AWS ec2 create-tags --resources "$EIP_ALLOC" --tags Key=Name,Value=tp-nat-eip
$AWS ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID" 2>/dev/null || echo "WARN: wait no disponible"
$AWS ec2 create-route --route-table-id "$RT_COMPUTE" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID"

echo "== 6.2 Security Groups =="
SG_ALB=$($AWS ec2 create-security-group --vpc-id "$VPC_ID" --group-name sg-alb --description "ALB HTTPS" --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress --group-id "$SG_ALB" --protocol tcp --port 443 --cidr 0.0.0.0/0
SG_API=$($AWS ec2 create-security-group --vpc-id "$VPC_ID" --group-name sg-api --description "Lambda API" --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress --group-id "$SG_API" --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443,UserIdGroupPairs=[{GroupId=$SG_ALB,Description='ALB'}]"
SG_ECS_ETL=$($AWS ec2 create-security-group --vpc-id "$VPC_ID" --group-name sg-ecs-etl --description "ECS ETL" --query "GroupId" --output text)
SG_RDS=$($AWS ec2 create-security-group --vpc-id "$VPC_ID" --group-name sg-rds --description "RDS" --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress --group-id "$SG_RDS" --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$SG_API,Description='API'},{GroupId=$SG_ECS_ETL,Description='ETL'}]"
SG_EFS=$($AWS ec2 create-security-group --vpc-id "$VPC_ID" --group-name sg-efs --description "EFS" --query "GroupId" --output text)
$AWS ec2 authorize-security-group-ingress --group-id "$SG_EFS" --ip-permissions "IpProtocol=tcp,FromPort=2049,ToPort=2049,UserIdGroupPairs=[{GroupId=$SG_ECS_ETL,Description='ETL'}]"
$AWS ec2 create-tags --resources "$SG_ALB" --tags Key=Name,Value=sg-alb
$AWS ec2 create-tags --resources "$SG_API" --tags Key=Name,Value=sg-api
$AWS ec2 create-tags --resources "$SG_ECS_ETL" --tags Key=Name,Value=sg-ecs-etl
$AWS ec2 create-tags --resources "$SG_RDS" --tags Key=Name,Value=sg-rds
$AWS ec2 create-tags --resources "$SG_EFS" --tags Key=Name,Value=sg-efs

echo "== 7. VPC endpoint S3 =="
ENDPOINT_S3=$($AWS ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${REGION}.s3" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$RT_COMPUTE" "$RT_RDS" \
  --query "VpcEndpoint.VpcEndpointId" --output text)
$AWS ec2 create-tags --resources "$ENDPOINT_S3" --tags Key=Name,Value=vpce-s3-datalake

echo
echo "=== Resumen lab-07-v2 ==="
cat <<EOF
VPC=$VPC_ID
SUBNET_PUBLIC_A=$SUBNET_PUBLIC_A
SUBNET_PUBLIC_B=$SUBNET_PUBLIC_B
SUBNET_RDS_A=$SUBNET_RDS_A
SUBNET_RDS_B=$SUBNET_RDS_B
SUBNET_COMPUTE_A=$SUBNET_COMPUTE_A
SUBNET_COMPUTE_B=$SUBNET_COMPUTE_B
IGW=$IGW_ID
RT_PUBLIC=$RT_PUBLIC
RT_RDS=$RT_RDS
RT_COMPUTE=$RT_COMPUTE
NAT=$NAT_ID
EIP_ALLOC=$EIP_ALLOC
SG_ALB=$SG_ALB
SG_API=$SG_API
SG_ECS_ETL=$SG_ECS_ETL
SG_RDS=$SG_RDS
SG_EFS=$SG_EFS
ENDPOINT_S3=$ENDPOINT_S3
EOF
```

Opcional: guardar este bloque como `vpc/provision_vpc_v2.sh` y ejecutarlo con `bash vpc/provision_vpc_v2.sh`.

---

## Paso 8 — Inspección de la topología

```bash
$AWS ec2 describe-vpcs --filters Name=tag:Lab,Values=07-v2
$AWS ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[].{Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,Name:Tags[?Key=='Name']|[0].Value}"
$AWS ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID \
  --query "RouteTables[].{Id:RouteTableId,Name:Tags[?Key=='Name']|[0].Value,Routes:Routes}"
$AWS ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID \
  --query "NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}"
$AWS ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID \
  --query "SecurityGroups[].{Id:GroupId,Name:GroupName}"
$AWS ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID
```

---

## Paso 9 — Limpieza

Orden inverso a las dependencias. **En AWS real el NAT cobra por hora:** borrarlo si no lo vas a usar.

```bash
$AWS ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ENDPOINT_S3"

$AWS ec2 delete-security-group --group-id "$SG_EFS"
$AWS ec2 delete-security-group --group-id "$SG_RDS"
$AWS ec2 delete-security-group --group-id "$SG_ECS_ETL"
$AWS ec2 delete-security-group --group-id "$SG_API"
$AWS ec2 delete-security-group --group-id "$SG_ALB"

$AWS ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"
# Esperar a que el NAT quede deleted antes de liberar la EIP / borrar subredes
sleep 30
$AWS ec2 release-address --allocation-id "$EIP_ALLOC"

# Disociar / borrar rutas y tablas (simplificado: borrar tablas tras quitar asociaciones)
$AWS ec2 delete-route-table --route-table-id "$RT_COMPUTE"
$AWS ec2 delete-route-table --route-table-id "$RT_RDS"
$AWS ec2 delete-route-table --route-table-id "$RT_PUBLIC"

$AWS ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
$AWS ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"

for s in "$SUBNET_PUBLIC_A" "$SUBNET_PUBLIC_B" "$SUBNET_RDS_A" "$SUBNET_RDS_B" \
         "$SUBNET_COMPUTE_A" "$SUBNET_COMPUTE_B"; do
  $AWS ec2 delete-subnet --subnet-id "$s"
done

$AWS ec2 delete-vpc --vpc-id "$VPC_ID"
```

> Si falla el borrado de una route table, primero listá y borrá las asociaciones (`describe-route-tables` → `disassociate-route-table`).

---

## Paso 10 — Documentar en `decisions.md`

```
### 008-v2 - VPC Multi-AZ del TP: ALB + NAT ETL + endpoint S3 (to-be)

Decision: VPC 10.0.0.0/16 Multi-AZ con (1) subredes públicas para ALB HTTPS
consumido por BI, (2) NAT solo en RT_COMPUTE para que los ETL en ECS salgan
a fuentes en Internet, (3) RDS en privadas sin egress, (4) VPC endpoint
Gateway a S3 (modelo AWS). En local el lake operativo es MinIO; LocalStack S3
queda comentado.

Contexto: separar entrada (BI→API) de salida (ETL→fuentes) y de storage.
El endpoint enseña el camino privado a S3 en AWS; no sustituye a MinIO en el lab.
Mezclar todo por NAT encarece y amplía superficie.

Tradeoff: NAT tiene costo horario; un solo NAT no es HA cross-AZ. Endpoint S3
no cubre ECR/Logs/Secrets (harían falta Interface endpoints o más uso de NAT).

Resultado: topología alineada al to-be del TP (ALB, Fargate, Lambda, EFS, RDS, S3).
```

---

## Checkpoint

- [ ] VPC `tp-integrador-vpc` `10.0.0.0/16` con DNS ON
- [ ] 2 públicas ALB + 2 privadas RDS + 2 privadas compute (2 AZs)
- [ ] IGW + `RT_PUBLIC` con `0.0.0.0/0 → IGW`
- [ ] `RT_RDS` sin Internet; `RT_COMPUTE` con `0.0.0.0/0 → NAT`
- [ ] SGs: `sg-alb`, `sg-api`, `sg-ecs-etl`, `sg-rds`, `sg-efs` (SG→SG)
- [ ] VPC endpoint Gateway S3 en `RT_COMPUTE` y `RT_RDS`
- [ ] Decisión 008-v2 en `docs/decisions.md`

---

## Para llevar: LocalStack vs AWS real

| Acción | LocalStack Community | AWS real |
|---|---|---|
| VPC, subnets, RTs, IGW, SGs | ✅ | ✅ |
| NAT Gateway + EIP | ⚠️ parcial | ✅ (cobro $/h) |
| VPC endpoint Gateway S3 | ⚠️ parcial (API sí; tráfico real limitado) | ✅ |
| ALB HTTPS + Lambda en VPC | ⚠️ / Pro | ✅ |
| ECS Fargate saliendo por NAT | ⚠️ | ✅ |

---

## Relación con `lab-07.md`

| | `lab-07.md` (curso) | `lab-07-v2.md` (TP) |
|---|---|---|
| Cómputo | EC2 pública/privada | ALB + Lambda + ECS Fargate + EFS |
| Datos | — | RDS Multi-AZ |
| Salida Internet | No (solo endpoint S3) | NAT para ETL → fuentes |
| S3 | Endpoint en RT privada | Endpoint en `RT_COMPUTE` + `RT_RDS` |
| HA | 1 pública + 1 privada | 2 AZs × 3 tiers |
