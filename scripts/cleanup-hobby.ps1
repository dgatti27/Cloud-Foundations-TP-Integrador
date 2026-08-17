#Requires -Version 5.1
<#
.SYNOPSIS
  Baja la infra Hobby y limpia volumenes de emuladores para evitar ghosts
  (secrets soft-deleted, IAM/S3 huerfanos, RDS MiniStack con schema viejo).

.DESCRIPTION
  Orden:
    1) tofu destroy (toolbox o host) — salvo -SkipDestroy
    2) docker compose down
    3) elimina contenedores ministack-rds-*
    4) borra volumenes LocalStack / MiniStack / MinIO (+ RDS data)
    5) opcional -Full: tambien postgres/redis/pgadmin

  Ejecutar desde la raiz del repo:
    .\scripts\cleanup-hobby.ps1
    .\scripts\cleanup-hobby.ps1 -Yes
    .\scripts\cleanup-hobby.ps1 -SkipDestroy -Yes
    .\scripts\cleanup-hobby.ps1 -Full -Yes

.NOTES
  No borra .env ni terraform.tfstate a proposito (destroy ya vacia el state).
#>
[CmdletBinding()]
param(
    [switch]$SkipDestroy,
    [switch]$Full,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg) { Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

if (-not $Yes) {
    Write-Host ""
    Write-Host "Cleanup Hobby - esto va a:"
    if (-not $SkipDestroy) {
        Write-Host "  - tofu destroy (recursos IaC)"
    } else {
        Write-Host "  - (sin tofu destroy)"
    }
    Write-Host "  - docker compose down"
    Write-Host "  - borrar sidecars ministack-rds-*"
    Write-Host "  - borrar volumenes: localstack-data, ministack-data, minio-data, ministack-rds-*-data"
    if ($Full) {
        Write-Host "  - Full: tambien postgres-*, redis-data, pgadmin-data"
    }
    Write-Host ""
    $ans = Read-Host "Continuar? [y/N]"
    if ($ans -notmatch '^(y|yes|s|si)$') {
        Write-Host "Cancelado."
        exit 0
    }
}

# Evitar que un LOCALSTACK_AUTH_TOKEN corto del proceso pise .env
Remove-Item Env:LOCALSTACK_AUTH_TOKEN -ErrorAction SilentlyContinue
if (-not $env:AWS_ACCESS_KEY_ID) { $env:AWS_ACCESS_KEY_ID = "test" }
if (-not $env:AWS_SECRET_ACCESS_KEY) { $env:AWS_SECRET_ACCESS_KEY = "test" }
if (-not $env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION = "us-east-1" }

# --- 1) OpenTofu destroy ---
if (-not $SkipDestroy) {
    Write-Step "tofu destroy"
    $destroyed = $false
    $toolbox = docker images -q tp-integrador-iac 2>$null

    if ($toolbox) {
        Write-Host "  via imagen toolbox (tp-iac)..."
        docker compose --profile iac run --rm tp-iac destroy
        if ($LASTEXITCODE -eq 0) {
            $destroyed = $true
            Write-Ok "destroy (toolbox)"
        } else {
            Write-Warn "destroy toolbox fallo (exit $LASTEXITCODE); se sigue con limpieza Docker"
        }
    } elseif (Get-Command tofu -ErrorAction SilentlyContinue) {
        Write-Host "  via tofu en el host..."
        Push-Location (Join-Path $Root "infra")
        try {
            tofu destroy -auto-approve
            if ($LASTEXITCODE -eq 0) {
                $destroyed = $true
                Write-Ok "destroy (host)"
            } else {
                Write-Warn "tofu destroy fallo (exit $LASTEXITCODE)"
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Warn "Sin toolbox ni tofu en PATH - se omite destroy (usa -SkipDestroy o instala tofu / build tp-iac)"
    }

    if (-not $destroyed) {
        Write-Warn "Si quedan recursos en emuladores, el wipe de volumenes los limpia igual."
    }
}

# --- 2) Compose down ---
Write-Step "docker compose down"
docker compose down --remove-orphans 2>&1 | Out-Host
Write-Ok "compose down"

# --- 3) Sidecars RDS MiniStack ---
Write-Step "contenedores ministack-rds-*"
$rdsIds = @(docker ps -aq --filter "name=ministack-rds" 2>$null | Where-Object { $_ })
if ($rdsIds.Count -gt 0) {
    docker rm -f @($rdsIds) 2>&1 | Out-Host
    Write-Ok ("eliminados: " + $rdsIds.Count)
} else {
    Write-Ok "ninguno"
}

# --- 4) Volumenes ---
Write-Step "volumenes emuladores"
$project = "cloud-foundations-tp-integrador"
$vols = [System.Collections.Generic.List[string]]::new()
[void]$vols.Add("${project}_localstack-data")
[void]$vols.Add("${project}_ministack-data")
[void]$vols.Add("${project}_minio-data")

if ($Full) {
    [void]$vols.Add("${project}_postgres-data-bronce")
    [void]$vols.Add("${project}_postgres-data-dw")
    [void]$vols.Add("${project}_postgres-data-erp")
    [void]$vols.Add("${project}_redis-data")
    [void]$vols.Add("${project}_pgadmin-data")
}

docker volume ls -q 2>$null | Where-Object { $_ -like "*ministack-rds*" } | ForEach-Object {
    if (-not $vols.Contains($_)) { [void]$vols.Add($_) }
}

foreach ($v in $vols) {
    docker volume inspect $v 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        docker volume rm $v 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "rm $v"
        } else {
            Write-Warn "no se pudo borrar $v (en uso?)"
        }
    } else {
        Write-Host "  - $v (no existe)"
    }
}

Write-Host ""
Write-Host "Cleanup listo." -ForegroundColor Green
Write-Host "Proximo arranque limpio:"
Write-Host "  docker compose up -d"
Write-Host "  docker compose --profile iac run --rm tp-iac apply"
Write-Host "  # o: cd infra; tofu apply"
Write-Host ""
