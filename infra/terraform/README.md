# Terraform/OpenTofu

Esta carpeta es una introduccion a Infrastructure as Code.

IaC del data lake local: crea buckets en **MinIO** (API S3) via el provider AWS.
LocalStack S3 queda comentado en `main.tf` (ver `docs/decisions.md` #002).

No provisiona recursos cloud reales. Sirve para practicar:

- estructura de archivos;
- variables;
- outputs;
- `fmt`;
- `validate`;
- conversacion tecnica sobre `plan`, `apply` y `state`.

## Comandos

```bash
terraform init
terraform fmt
terraform validate
```

O con OpenTofu:

```bash
tofu init
tofu plan
tofu apply
tofu output
```

