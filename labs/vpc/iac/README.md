# Lab 07-v2 — IaC OpenTofu (VPC Multi-AZ en LocalStack)

Declara la red del TP Integrador contra **LocalStack** (`:4566`):

| Recurso | Lab 07-v2 |
|---|---|
| `aws_vpc` + DNS | Paso 1 |
| 6× `aws_subnet` Multi-AZ | Paso 2 |
| `aws_internet_gateway` | Paso 3 |
| RT pública + ruta IGW | Paso 4 |
| RT privadas RDS / compute | Paso 5 |
| EIP + NAT + ruta compute | Paso 6.1 |
| SGs + reglas SG→SG | Paso 6.2 |
| VPC endpoint Gateway S3 | Paso 7 |
| `local_file` → `vpc_config.json` | Inventario para labs 08+ |

## Qué va en IaC vs Bash

| Capa | Herramienta | Responsabilidad |
|---|---|---|
| **Infra (deseado)** | OpenTofu acá | VPC completa + `vpc_config.json` |
| **CLI / aprendizaje** | `lab-07-v2.md` pasos | Entender cada API `ec2` |
| **Script bash** | `provision_vpc_v2.sh` | **Se preserva** — misma infra vía awslocal, sin state |

No hay `vpc_demo.py` en este lab (el curso genérico usa `scripts/vpc_demo.py`).  
El módulo `infra/modules/vpc` es el mismo diseño a escala TP (lab 09); este stack es **autocontenido para lab-07-v2**.

## Prereqs

```powershell
docker compose up -d localstack-integrador   # o el servicio LocalStack del compose
# Labs 04 (IAM) y 06 (lake MinIO) recomendados; no bloquean el apply de red
```

## Uso

```powershell
cd vpc/iac
Copy-Item terraform.tfvars.example terraform.tfvars

tofu init
tofu plan
tofu apply
```

Si el NAT falla o molesta en LocalStack:

```hcl
# terraform.tfvars
enable_nat = false
```

Ver inventario:

```powershell
Get-Content ..\vpc_config.json
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=tp-integrador-vpc" --query "Vpcs[0].VpcId"
```

## Destroy

```powershell
tofu destroy
```

En AWS real el NAT cobra aunque no haya tráfico: destruir al terminar el lab.

## Relación con `provision_vpc_v2.sh`

| | OpenTofu | Bash |
|---|---|---|
| Idempotencia | State + plan | Crear de nuevo / IDs viejos |
| Inventario | Escribe `vpc_config.json` | Echo al final (pegar a mano) |
| Pedagógico | Declarativo | Cada comando del lab visible |

Podés usar **uno u otro**, no ambos a la vez sobre la misma VPC sin limpiar (duplicás recursos).
