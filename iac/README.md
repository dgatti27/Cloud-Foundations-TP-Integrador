# IaC — OpenTofu

| Doc | Qué hace |
|-----|----------|
| [`lab-09.md`](lab-09.md) | Fundamentos: Docker app + bucket S3 en `aws/` |
| [`lab-09-tp.md`](lab-09-tp.md) | Stack completo del TP en `tp/` |
| [`DOCKER.md`](DOCKER.md) | **Empaquetar imagen + levantar todo en línea** |

## TP Integrador (en el host)

```bash
docker compose up -d
python iac/iac_demo.py --reconcile   # solo si chocan demos imperativos previos
python iac/iac_demo.py               # tofu init + apply (idempotente)
```

## TP Integrador (imagen toolbox)

```bash
cp .env.example .env   # + LOCALSTACK_AUTH_TOKEN
docker compose up -d
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac build tp-iac
docker compose -f compose.yaml -f docker-compose.iac.yaml --profile iac run --rm tp-iac apply
```

Paso a paso completo: [`DOCKER.md`](DOCKER.md).

Código HCL: [`tp/`](tp/). Entrypoint host: [`iac_demo.py`](iac_demo.py). Dockerfile raíz del repo.
