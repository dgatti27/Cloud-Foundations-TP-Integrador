# Imagen toolbox del TP Integrador: código + OpenTofu + CLI + Python
# para aplicar el IaC sin perder seeds, policies, handlers ni HCL.
#
# Build (desde la raíz del repo):
#   docker build -f docker/Dockerfile -t tp-integrador-iac:latest .
# Run: ver docker/DOCKER.md

FROM python:3.12-bookworm

ARG TOFU_VERSION=1.9.1
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    AWS_DEFAULT_REGION=us-east-1 \
    LOCALSTACK_ENDPOINT=http://localstack-integrador:4566 \
    MINISTACK_ENDPOINT=http://ministack-integrador:4566 \
    MINIO_ENDPOINT=http://s3-soporte:9000 \
    TF_IN_AUTOMATION=1
# Credenciales de lab se inyectan en runtime (compose / -e), no en la imagen.

# OS deps + Docker CLI (post_rds.py hace docker exec al container RDS de MiniStack)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
      jq \
      git \
      docker.io \
    && rm -rf /var/lib/apt/lists/* \
    && docker --version

# OpenTofu (mismo HCL que Terraform; binario `tofu`)
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip" \
      -o /tmp/tofu.zip \
    && unzip -o /tmp/tofu.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/tofu \
    && rm /tmp/tofu.zip \
    && tofu version

# AWS CLI v2 (útil para verificaciones; demos usan boto3)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    && aws --version

WORKDIR /workspace

# Deps Python (mismo archivo que el host)
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/entrypoint-iac.sh

# Copia selectiva: evita symlinks rotos de Airflow (logs/scheduler/latest) en Windows
# y omite state/.terraform (se montan o regeneran en runtime).
COPY compose.yaml .env.example ./
COPY infra/ ./infra/
COPY apps/ ./apps/
COPY data/ ./data/
# apps/airflow/logs se excluye en .dockerignore (symlinks Airflow en Windows).
# En runtime, compose monta ./apps.

RUN mkdir -p /workspace/apps/airflow/dags \
             /workspace/apps/airflow/logs \
             /workspace/infra/generated \
    && sed -i 's/\r$//' /usr/local/bin/entrypoint-iac.sh \
    && sed -i 's/\r$//' /workspace/infra/scripts/post_rds.py \
    && chmod +x /usr/local/bin/entrypoint-iac.sh \
                /workspace/infra/scripts/post_rds.py \
    && find /workspace/infra -type d -name .terraform -exec rm -rf {} + 2>/dev/null || true \
    && find /workspace/infra -name '*.tfstate*' -delete 2>/dev/null || true

# Volume tip: montar ./infra para persistir terraform.tfstate entre runs
VOLUME ["/workspace/infra"]

ENTRYPOINT ["/usr/local/bin/entrypoint-iac.sh"]
CMD ["apply"]
