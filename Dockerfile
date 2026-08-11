# Imagen toolbox del TP Integrador: código + OpenTofu + CLI + Python
# para aplicar el IaC sin perder seeds, policies, handlers ni HCL.
#
# Build:  docker build -t tp-integrador-iac:latest .
# Run:    ver iac/DOCKER.md

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

# Deps Python mínimas para iac_demo + demos del TP
COPY iac/requirements-docker.txt /tmp/requirements-docker.txt
RUN pip install --no-cache-dir -r /tmp/requirements-docker.txt \
    && rm /tmp/requirements-docker.txt

# Copia selectiva: evita symlinks rotos de Airflow (logs/scheduler/latest) en Windows
# y omite state/.terraform (se montan o regeneran en runtime).
COPY compose.yaml docker-compose.iac.yaml .env.example ./
COPY iac/ ./iac/
COPY rds/ ./rds/
COPY lambda/ ./lambda/
COPY vpc/ ./vpc/
COPY iam/ ./iam/
COPY s3/ ./s3/
COPY etl/ ./etl/
COPY finops/ ./finops/
COPY scripts/ ./scripts/
# ecs/ se monta en runtime (docker-compose.iac.yaml). No copiar efs-standin/logs
# (symlinks de Airflow rompen el build context en Docker Desktop Windows).

RUN mkdir -p /workspace/ecs/efs-standin/dags \
             /workspace/ecs/efs-standin/logs \
             /workspace/iac/tp/generated \
    && sed -i 's/\r$//' /workspace/iac/docker/entrypoint.sh \
    && sed -i 's/\r$//' /workspace/iac/tp/scripts/post_rds.py \
    && chmod +x /workspace/iac/docker/entrypoint.sh \
                /workspace/iac/tp/scripts/post_rds.py \
                /workspace/iac/iac_demo.py \
    && cp /workspace/iac/docker/entrypoint.sh /usr/local/bin/entrypoint-iac.sh \
    && chmod +x /usr/local/bin/entrypoint-iac.sh \
    && find /workspace/iac/tp -type d -name .terraform -exec rm -rf {} + 2>/dev/null || true \
    && find /workspace/iac/tp -name '*.tfstate*' -delete 2>/dev/null || true

# Volume tip: montar iac/tp para persistir terraform.tfstate entre runs
VOLUME ["/workspace/iac/tp"]

ENTRYPOINT ["/usr/local/bin/entrypoint-iac.sh"]
CMD ["apply"]
