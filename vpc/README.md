# VPC — Arquitectura de red (Lab 07 v2)

Red Multi-AZ del **TP Integrador**: une IAM, S3, cómputo (ECS Fargate + Lambda + EFS) y datos (RDS) según el diseño de `lab-07-v2.md`.

Documento de lab: [`lab-07-v2.md`](./lab-07-v2.md)  
Lab del curso (EC2 genérico): [`lab-07.md`](./lab-07.md)

---

## Objetivo

Definir una VPC donde:

1. **BI en Internet** consume la **API (Lambda)** vía **ALB HTTPS**.
2. Los **ETL (ECS Fargate)** salen a **fuentes externas** (ERP, Mongo, scraping) vía **NAT**.
3. El **data lake S3** se alcanza por **VPC endpoint Gateway** (sin Internet / sin NAT).
4. **RDS** queda en subredes privadas **sin** salida a Internet.

---

## Diagrama lógico

```text
                         Internet
                    ┌───────┴───────┐
                    │               │
              (BI → HTTPS)    (fuentes ETL)
                    │               │
                   IGW             IGW
                    │               │
         ┌──────────┴───────────────┴──────────┐
         │         Subredes PÚBLICAS           │
         │  10.0.1.0/24 (AZ-a)  10.0.2.0/24   │
         │         ALB  +  NAT (EIP en AZ-a)   │
         └──────────┬───────────────▲──────────┘
                    │               │
              :443  │               │ 0.0.0.0/0
                    ▼               │ (solo RT_COMPUTE)
         ┌──────────────────────────┴──────────┐
         │      Subredes PRIVADAS COMPUTE      │
         │  10.0.20.0/24 (AZ-a)  10.0.21.0/24  │
         │  Lambda API │ ECS ETL │ EFS         │
         └───────┬──────────┬──────────────────┘
                 │          │
            :5432│          │ pl-* → vpce (S3)
                 ▼          ▼
         ┌────────────┐  S3 data lake
         │ PRIVADAS   │  (lab 06: backup / snapshot / staging)
         │ RDS        │
         │ 10.0.10/11 │
         └────────────┘
```

---

## CIDR y subredes

| CIDR | Nombre | AZ | Tier | Uso |
|---|---|---|---|---|
| `10.0.0.0/16` | `tp-integrador-vpc` | — | VPC | Espacio total |
| `10.0.1.0/24` | `public-alb-a` | a | Pública | ALB (+ NAT Gateway) |
| `10.0.2.0/24` | `public-alb-b` | b | Pública | ALB (2ª AZ) |
| `10.0.10.0/24` | `private-rds-a` | a | Privada | RDS Multi-AZ |
| `10.0.11.0/24` | `private-rds-b` | b | Privada | RDS Multi-AZ |
| `10.0.20.0/24` | `private-compute-a` | a | Privada | ECS + Lambda + EFS |
| `10.0.21.0/24` | `private-compute-b` | b | Privada | ECS + Lambda + EFS |

**Por qué Multi-AZ:** ALB exige ≥2 AZs; RDS Multi-AZ necesita DB subnet group en ≥2 AZs; Fargate/EFS se reparte por AZ.

---

## Route tables

| Tabla | Subredes asociadas | Rutas relevantes |
|---|---|---|
| `rt-public-alb` | públicas a/b | `10.0.0.0/16 → local` · `0.0.0.0/0 → IGW` |
| `rt-private-rds` | RDS a/b | `local` · `pl-* (S3) → vpce` · **sin** Internet |
| `rt-private-compute` | compute a/b | `local` · `pl-* → vpce` · `0.0.0.0/0 → NAT` |

Una subred es **pública** solo si tiene ruta a un **IGW**. No hay flag “make public”.

---

## Flujos de tráfico

| Flujo | Camino | Componentes |
|---|---|---|
| **Entrada BI → API** | Internet → IGW → ALB :443 → Lambda | Públicas + `sg-alb` / `sg-api` |
| **Salida ETL → fuentes** | ECS → NAT → IGW → Internet | `RT_COMPUTE` + NAT + EIP |
| **ETL/API → S3** | Gateway endpoint (red AWS) | `vpce` en `RT_COMPUTE` / `RT_RDS` |
| **ETL/API → RDS** | Solo VPC | `local` + `sg-rds` :5432 |
| **ETL → EFS** | Solo VPC | `sg-efs` :2049 |

### Separación de responsabilidades

- **IGW + ALB** = que BI **entre** a la API por HTTPS.  
- **NAT** = que los ETL **salgan** a orígenes externos.  
- **VPC endpoint S3** = storage del data lake **sin** usar NAT ni Internet.  
- **RDS** = sin egress a Internet.

El endpoint **no** se ata a un bucket por nombre: es el servicio S3 de la región. Los buckets del lab 06 se usan con las policies IAM / bucket policy ya definidas.

---

## Security Groups

Patrón: **referencia SG→SG** (no CIDR de capa), para tolerar IPs cambiantes de ALB/Fargate.

| SG | Ingress | Quién lo usa |
|---|---|---|
| `sg-alb` | TCP 443 desde `0.0.0.0/0` (o IPs del BI) | ALB |
| `sg-api` | TCP 443 (o puerto del TG) solo desde `sg-alb` | Lambda API |
| `sg-ecs-etl` | Sin ingress público | ECS Fargate ETL |
| `sg-rds` | TCP 5432 desde `sg-api` y `sg-ecs-etl` | RDS PostgreSQL |
| `sg-efs` | TCP 2049 desde `sg-ecs-etl` | EFS |

SGs: solo **allow**, **stateful** (la respuesta de una conexión permitida sale sola).

---

## NAT Gateway

| Pieza | Rol |
|---|---|
| Elastic IP (`eipalloc-…`) | Cara pública fija del NAT (allowlists en orígenes) |
| NAT en `public-alb-a` | Traduce origen privado → EIP; **no** abre entrada a ECS |
| Ruta en `RT_COMPUTE` | `0.0.0.0/0 → nat-…` |

Un solo NAT (AZ-a) alcanza para el lab. En producción HA: un NAT por AZ. **Costo:** $/hora + datos transferidos.

---

## VPC endpoint S3 (Gateway)

| Atributo | Valor |
|---|---|
| Tipo | `Gateway` |
| Servicio | `com.amazonaws.<region>.s3` |
| Route tables | `rt-private-compute`, `rt-private-rds` |
| Buckets del TP | `backup-data-lake`, `snapshot-data-lake`, `staging-data-lake` (+ raw del lab 04 vía IAM) |

Autorización = **IAM** (`app-role`, `S3RWTP`, etc.) + **bucket policies**. El endpoint solo cambia el camino de red.

---

## Inventario de recursos (tags)

| Recurso | Tag `Name` típico |
|---|---|
| VPC | `tp-integrador-vpc` |
| IGW | `tp-igw` |
| NAT | `tp-nat-etl` |
| EIP | `tp-nat-eip` |
| Endpoint | `vpce-s3-datalake` |
| Lab | `Lab=07-v2` |

---

## Cómo provisionar

Seguir los pasos de [`lab-07-v2.md`](./lab-07-v2.md) o el script completo al final de ese documento.

```bash
# Ejemplo (Git Bash / WSL), con LocalStack:
export AWS_CLI=awslocal
export AWS_DEFAULT_REGION=us-east-1
# bash vpc/provision_vpc_v2.sh   # si exportaste el script del lab
```

Prerrequisitos: LocalStack arriba, lab 04 (IAM) y lab 06 (buckets lake) corridos.

---

## Limpieza

El NAT **sigue cobrando** en AWS real aunque no haya tráfico. Borrar en orden inverso (endpoint → SGs → NAT → EIP → route tables → IGW → subnets → VPC). Detalle en el paso 9 de `lab-07-v2.md`.

---

## Relación con el resto del TP

| Lab | Aporte |
|---|---|
| 04 IAM | Roles/policies que hablan con S3 y asumen identidad |
| 06 S3 | Buckets lake + BPA + bucket policies |
| **07 v2 VPC** | Dónde viven ALB, Fargate, Lambda, EFS, RDS y cómo llegan a S3/Internet |
| Siguiente | Provisionar ALB, RDS, ECS, Lambda y EFS **dentro** de estas subredes/SGs |
