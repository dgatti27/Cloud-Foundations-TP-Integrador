"""
Lab 04 — IAM demo: grupos, usuarios, roles y credenciales temporales vía STS.

Automatiza los pasos 2-7 de iam/lab-04.md:
  2. Buckets de referencia: backup-data-raw y snapshot-data-raw
  3. Grupos bi-ops / bi-admin con policies administradas (S3RWTP / S3AdminTP)
  4. Usuarios usuario2-ops -> bi-ops y usuario1-admin -> bi-admin
  5. Access key de larga duración (para observar el riesgo)
  6. Roles app-role (trust ECS) y db-role (trust RDS export) con inline policy
  7. AssumeRole vía STS -> credenciales temporales -> listar buckets

Corre contra LocalStack Community (mecánica de IAM, sin enforcement real).
Para enforcement real de Deny, usá LocalStack Pro o una cuenta AWS.

Uso:
    python iam/iam_demo.py
"""

import boto3
from botocore.exceptions import ClientError
from pathlib import Path

ENDPOINT = "http://localhost:4566"
REGION = "us-east-1"
BUCKETS = ["backup-data-raw", "snapshot-data-raw"]
IAM_DIR = Path(__file__).parent

# grupo -> (policy administrada, archivo de policy)
GROUPS = {
    "bi-ops": ("S3RWTP", "s3_readwrite_policy.json"),
    "bi-admin": ("S3AdminTP", "s3_admin_policy.json"),
}

# usuario -> grupo
USERS = {
    "usuario2-ops": "bi-ops",
    "usuario1-admin": "bi-admin",
}

# rol -> (trust policy, session name)
ROLES = {
    "app-role": ("trust_policy_ecs.json", "TP-App-session"),
    "db-role": ("trust_policy_rds_export.json", "TP-DB-session"),
}

BOTO_KWARGS = dict(
    endpoint_url=ENDPOINT,
    region_name=REGION,
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


# ── helpers ───────────────────────────────────────────────────────────────────

def _already_exists(e: ClientError) -> bool:
    # AWS real devuelve Code='EntityAlreadyExists'.
    # LocalStack 3.x community devuelve el mensaje como Code (ej: 'Group X already exists').
    code = e.response["Error"].get("Code", "")
    return code == "EntityAlreadyExists" or "already exists" in code.lower()


def make_client(service: str):
    return boto3.client(service, **BOTO_KWARGS)


# ── pasos del lab ─────────────────────────────────────────────────────────────

def ensure_buckets(s3):
    """Paso 2 — buckets de referencia (recurso protegido)."""
    for bucket in BUCKETS:
        try:
            s3.head_bucket(Bucket=bucket)
            print(f"  bucket '{bucket}' ya existe")
        except ClientError:
            s3.create_bucket(Bucket=bucket)
            s3.put_object(
                Bucket=bucket, Key="sample/hello.txt", Body=b"hello from lab-04"
            )
            print(f"  bucket '{bucket}' creado con objeto de ejemplo")


def create_groups_with_policies(iam):
    """Paso 3 — grupos bi-ops / bi-admin con sus policies administradas."""
    policy_arns = {}
    for group, (policy_name, policy_file) in GROUPS.items():
        try:
            iam.create_group(GroupName=group)
            print(f"  grupo '{group}' creado")
        except ClientError as e:
            if _already_exists(e):
                print(f"  grupo '{group}' ya existe")
            else:
                raise

        policy_doc = (IAM_DIR / policy_file).read_text()
        try:
            resp = iam.create_policy(
                PolicyName=policy_name,
                PolicyDocument=policy_doc,
                Description=f"Policy {policy_name} sobre buckets del lab 04",
            )
            policy_arn = resp["Policy"]["Arn"]
            print(f"  policy '{policy_name}' creada: {policy_arn}")
        except ClientError as e:
            if _already_exists(e):
                policy_arn = f"arn:aws:iam::000000000000:policy/{policy_name}"
                print(f"  policy '{policy_name}' ya existe: {policy_arn}")
            else:
                raise

        iam.attach_group_policy(GroupName=group, PolicyArn=policy_arn)
        print(f"  policy '{policy_name}' adjuntada al grupo '{group}'")
        policy_arns[group] = policy_arn
    return policy_arns


def create_users(iam):
    """Paso 4 — usuarios asignados a sus grupos."""
    for username, group in USERS.items():
        try:
            iam.create_user(UserName=username)
            print(f"  usuario '{username}' creado")
        except ClientError as e:
            if _already_exists(e):
                print(f"  usuario '{username}' ya existe")
            else:
                raise

        iam.add_user_to_group(GroupName=group, UserName=username)
        print(f"  usuario '{username}' agregado al grupo '{group}'")


def create_access_key(iam, username: str):
    """Paso 5 — access key de larga duración (lo que queremos evitar en prod)."""
    try:
        key = iam.create_access_key(UserName=username)["AccessKey"]
        print(
            f"  access key creada para '{username}': {key['AccessKeyId']} "
            "(larga duración — evitar en prod)"
        )
    except ClientError as e:
        if "LimitExceeded" in str(e):
            print(f"  access key ya existe para '{username}'")
        else:
            raise


def create_roles(iam):
    """Paso 6 — roles con trust policy (ECS y RDS export) + inline policy."""
    inline_policy = (IAM_DIR / "s3_readwrite_policy.json").read_text()
    role_arns = {}
    for role_name, (trust_file, _session) in ROLES.items():
        trust_policy = (IAM_DIR / trust_file).read_text()
        try:
            iam.create_role(
                RoleName=role_name,
                AssumeRolePolicyDocument=trust_policy,
                Description=f"Rol {role_name} con acceso mínimo a S3 — lab 04",
            )
            print(f"  rol '{role_name}' creado (trust: {trust_file})")
        except ClientError as e:
            if _already_exists(e):
                print(f"  rol '{role_name}' ya existe")
            else:
                raise

        iam.put_role_policy(
            RoleName=role_name,
            PolicyName="InlineS3Read",
            PolicyDocument=inline_policy,
        )
        print(f"  inline policy 'InlineS3Read' adjuntada al rol '{role_name}'")
        role_arns[role_name] = iam.get_role(RoleName=role_name)["Role"]["Arn"]
    return role_arns


def assume_role_and_use_s3(sts, role_arn: str, session_name: str):
    """Paso 7 — AssumeRole vía STS y uso de credenciales temporales en S3."""
    print(f"\n  asumiendo rol: {role_arn} (session: {session_name})")
    resp = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name,
        DurationSeconds=900,
    )
    creds = resp["Credentials"]
    print(f"  AccessKeyId:  {creds['AccessKeyId']}")
    print(f"  Expiration:   {creds['Expiration']}  <- credencial temporal")

    s3_temp = boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        region_name=REGION,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )

    for bucket in BUCKETS:
        objects = s3_temp.list_objects_v2(Bucket=bucket).get("Contents", [])
        print(f"  objetos en '{bucket}' con credenciales temporales:")
        for obj in objects:
            print(f"    - {obj['Key']} ({obj['Size']} bytes)")

    return creds


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    print("=== Lab 04 — IAM demo ===\n")
    print("AVISO: LocalStack Community no enforcea policies (Deny no bloquea).")
    print("       Practicamos la mecánica: crear, adjuntar, asumir.\n")

    iam = make_client("iam")
    s3 = make_client("s3")
    sts = make_client("sts")

    print("1. Buckets S3 de referencia")
    ensure_buckets(s3)

    print("\n2. Grupos + policies administradas")
    policy_arns = create_groups_with_policies(iam)

    print("\n3. Usuarios -> grupos")
    create_users(iam)

    print("\n4. Access key de larga duración (observar el riesgo)")
    create_access_key(iam, "usuario2-ops")

    print("\n5. Roles con trust policy (ECS / RDS export) + inline policy mínima")
    role_arns = create_roles(iam)

    print("\n6. AssumeRole vía STS -> credenciales temporales")
    for role_name, (_trust, session_name) in ROLES.items():
        assume_role_and_use_s3(sts, role_arns[role_name], session_name)

    print("\n=== Resumen de recursos creados ===")
    print(f"  Buckets:  {', '.join(BUCKETS)}")
    for group, arn in policy_arns.items():
        print(f"  Grupo:    {group} -> {arn}")
    for username, group in USERS.items():
        print(f"  Usuario:  {username} (grupo {group})")
    for role_name, arn in role_arns.items():
        print(f"  Rol:      {role_name} -> {arn}")
    print("\nListo. Revisá los JSON en iam/ para entender cada documento.")


if __name__ == "__main__":
    main()
