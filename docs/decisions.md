# Decision log — justificaciones de la arquitectura to-be

Formato: Decision / Contexto / Alternativas / Tradeoff / Resultado.

### 001 - Soluciones locales emulando AWS
Decision: usar Docker Compose, MinIO y LocalStack en lugar de cuentas AWS.
Contexto: evitar costos accidentales y reducir friccion de setup.
Tradeoff:
Resultado:

### 002 - MinIO como object storage local (no LocalStack S3)
Decision: usar **MinIO** (`s3-soporte` en Compose, puerto 9000) como emulacion del data lake / S3 para el flujo de datos y para el IaC de buckets (OpenTofu/Terraform). LocalStack queda reservado a otros servicios AWS (SQS, SNS, IAM, Lambda, etc.), no como storage del pipeline. La opción de S3 AWS en localstack queda comentada ya que es más conveniente para utilizar luego las propias políticas de seguridad de IAM

Contexto:
- Ambos hablan API compatible con S3, pero no son el mismo producto ni el mismo rol en el lab.

Alternativas:
1. **Solo MinIO** para S3 del data lake (elegida para el pipeline).
2. **Solo LocalStack S3** para todo (scripts + Terraform).
3. **Ambos activos para S3** a la vez (descartada: solapamiento y doble estado).

Tradeoff:
- MinIO es mas liviano, tiene consola (:9001) y se siente como object storage de producto; no emula IAM/SQS/Lambda ni el resto del ecosistema AWS.
- LocalStack imita mejor el modelo AWS end-to-end, pero es mas pesado y sobredimensionado si solo se necesita subir/listar objetos en el lab diario.
- Politicas, grupos y usuarios avanzados de MinIO conviene gestionarlos luego con el provider nativo `aminueza/minio` (stubs en `main.tf`); el provider AWS alcanza para buckets y bucket policies basicas.

Resultado:
- **Pipeline / lab diario (datos) + IaC de buckets:** MinIO (`infra/terraform` apunta a `:9000`).
- **LocalStack:** reservado a otros servicios AWS (SQS, SNS, IAM, Lambda…); su bloque S3 queda comentado en `main.tf`.
- No mezclar ambos como destino S3 del mismo flujo.

