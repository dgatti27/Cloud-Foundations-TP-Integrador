# Captura evidencia de Compose + OpenTofu + smoke HTTP/AWS CLI → test/<fecha>-smoke/
# Uso (raíz del repo, stack ya up + apply hecho):
#   .\test\capture-smoke.ps1
#   .\test\capture-smoke.ps1 -Name 2026-08-13-smoke
# No escribe SecretString ni tfstate.

[CmdletBinding()]
param(
  [string]$Name = ("{0}-smoke" -f (Get-Date -Format "yyyy-MM-dd"))
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root "compose.yaml"))) {
  $Root = (Get-Location).Path
}
Set-Location $Root
$Out = Join-Path $Root "test\$Name"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Utf8 = New-Object System.Text.UTF8Encoding $false

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

function Save-Utf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, ($Text.TrimEnd() + "`n"), $Utf8)
}

function Capture([string]$Title, [string]$File, [scriptblock]$Cmd) {
  $path = Join-Path $Out $File
  try {
    $body = & $Cmd 2>&1 | Out-String
  } catch {
    $body = "ERROR: $_"
  }
  Save-Utf8 $path @"
=== $Title ===
utc=$(Get-Date -Format o)

$body
"@
  Write-Host "  $File"
}

Write-Host "Capturando → $Out"

Save-Utf8 (Join-Path $Out "00-meta.txt") @"
TP Integrador — evidencia smoke test + IaC
fecha_local=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
host=$env:COMPUTERNAME
os=$([System.Environment]::OSVersion.VersionString)
cwd=$Root
etl_ejecutado=false
nota=Sin secretos (no SecretString). Regenerado con test/capture-smoke.ps1
"@

Capture "versiones" "00-versions.txt" {
  docker --version
  docker compose version
  tofu version
  aws --version
}
Capture "docker compose ps" "01-compose-ps.txt" {
  docker compose ps
  Write-Output ""
  docker ps --filter name=ministack-rds --format "{{.Names}}  {{.Ports}}  {{.Status}}"
}
Capture "tofu output" "02-tofu-output.txt" {
  Push-Location (Join-Path $Root "infra"); try { tofu output } finally { Pop-Location }
}
Capture "IAM LocalStack :4566" "03-iam.txt" {
  aws --endpoint-url http://localhost:4566 iam get-role --role-name app-role --query Role.RoleName --output text
  aws --endpoint-url http://localhost:4566 iam get-role --role-name api-role --query Role.RoleName --output text
  aws --endpoint-url http://localhost:4566 iam get-role --role-name ecsTaskExecutionRole --query Role.RoleName --output text
  aws --endpoint-url http://localhost:4566 iam get-role --role-name db-role --query Role.RoleName --output text
  aws --endpoint-url http://localhost:4566 iam get-group --group-name bi-ops --query Group.GroupName --output text
  aws --endpoint-url http://localhost:4566 iam get-group --group-name bi-admin --query Group.GroupName --output text
  aws --endpoint-url http://localhost:4566 iam get-group --group-name bi-api --query Group.GroupName --output text
  aws --endpoint-url http://localhost:4566 iam list-users --query "Users[].UserName" --output text
}
Capture "MinIO S3 :9000 (minioadmin)" "04-minio-s3.txt" {
  $env:AWS_ACCESS_KEY_ID = "minioadmin"
  $env:AWS_SECRET_ACCESS_KEY = "minioadmin"
  aws --endpoint-url http://localhost:9000 s3 ls --region us-east-1
  $env:AWS_ACCESS_KEY_ID = "test"
  $env:AWS_SECRET_ACCESS_KEY = "test"
}
Capture "RDS MiniStack :4567" "05-rds.txt" {
  aws --endpoint-url http://localhost:4567 rds describe-db-instances --db-instance-identifier tp-dw-db --output json
}
Capture "Secrets names only (no SecretString)" "06-secrets-names.txt" {
  aws --endpoint-url http://localhost:4567 secretsmanager list-secrets --query "SecretList[].Name" --output text
}
Capture "Lambda tp-gold-api" "07-lambda.txt" {
  aws --endpoint-url http://localhost:4566 lambda get-function --function-name tp-gold-api --query "{Name:Configuration.FunctionName,Runtime:Configuration.Runtime,State:Configuration.State,Handler:Configuration.Handler,LastModified:Configuration.LastModified,Role:Configuration.Role}" --output json
}
Capture "HTTP health UIs" "08-http-health.txt" {
  Write-Output "--- ALB /health ---"
  try { (Invoke-RestMethod http://localhost:8088/health) | ConvertTo-Json -Compress } catch { "FAIL $_" }
  Write-Output "--- Airflow /health ---"
  try { $r = Invoke-WebRequest http://localhost:8080/health -UseBasicParsing; "status=$($r.StatusCode)" } catch { "FAIL $_" }
  Write-Output "--- pgAdmin /misc/ping ---"
  try { $r = Invoke-WebRequest http://localhost:5050/misc/ping -UseBasicParsing; "status=$($r.StatusCode) body=$($r.Content)" } catch { "FAIL $_" }
}
Capture "API gold/query (sin ETL)" "09-gold-query.txt" {
  Write-Output "--- table=hecho_ventas ---"
  try { Invoke-RestMethod "http://localhost:8088/gold/query?table=hecho_ventas&limit=1" | ConvertTo-Json -Compress } catch { if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { "$_" } }
  Write-Output "--- table=dim_cliente ---"
  try { Invoke-RestMethod "http://localhost:8088/gold/query?table=dim_cliente&limit=2" | ConvertTo-Json -Compress } catch { if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { "$_" } }
}

Push-Location (Join-Path $Root "infra")
$planOut = & tofu plan -no-color -detailed-exitcode 2>&1 | Out-String
$planExit = $LASTEXITCODE
Pop-Location
Save-Utf8 (Join-Path $Out "10-tofu-plan.txt") @"
=== tofu plan (idempotencia) ===
utc=$(Get-Date -Format o)

$planOut

exit_code=$planExit
# 0=no changes  1=error  2=changes present
"@
Write-Host "  10-tofu-plan.txt (exit=$planExit)"

if (Test-Path (Join-Path $Root "labs\finops\pricing.py")) {
  Push-Location (Join-Path $Root "labs\finops")
  $p1 = & python pricing.py --budget 300 2>&1 | Out-String
  Pop-Location
  Save-Utf8 (Join-Path $Out "11-finops-pricing.txt") @"
=== python pricing.py --budget 300 ===
utc=$(Get-Date -Format o)

$p1
"@
  Write-Host "  11-finops-pricing.txt"
}

Push-Location (Join-Path $Root "infra")
$resources = @(tofu state list 2>$null)
Pop-Location
Save-Utf8 (Join-Path $Out "13-tofu-state-summary.txt") @"
=== tofu state list (resumen IaC) ===
utc=$(Get-Date -Format o)
resource_count=$($resources.Count)

$($resources -join "`n")
"@
Write-Host "  13-tofu-state-summary.txt ($($resources.Count) resources)"
Write-Host "Listo: $Out"
