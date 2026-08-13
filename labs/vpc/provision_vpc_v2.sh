#!/usr/bin/env bash
# VPC Multi-AZ — TP Integrador (lab-07-v2)
#
# Camino CLI/bash (pedagógico). Alternativa declarativa:
#   cd infra && tofu apply   → también genera vpc_config.json
# No corras este script y OpenTofu a la vez sin limpiar (duplicás VPC).
#
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
$AWS ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID" 2>/dev/null || echo "WARN: wait no disponible / continuar"
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

echo "== 7. VPC endpoint S3 (modelo AWS; lake local = MinIO) =="
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
