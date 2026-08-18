#Requires -Version 5.1
<#
.SYNOPSIS
  Detecta el puerto host de MiniStack RDS y lo escribe en .env y terraform.tfvars.

.DESCRIPTION
  MiniStack publica el sidecar ministack-rds-* en un puerto dinámico (15432, 15433, …).
  Este script lee docker ps, actualiza RDS_PORT_OVERRIDE y rds_port_override, y avisa
  si hace falta recrear Airflow o re-aplicar la Lambda.

  Uso (después de tofu apply):
    .\scripts\sync-rds-port.ps1
    .\scripts\sync-rds-port.ps1 -RecreateAirflow
#>
[CmdletBinding()]
param(
    [switch]$RecreateAirflow
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Get-RdsHostPort {
    $line = docker ps --filter "name=ministack-rds" --format "{{.Ports}}" 2>$null | Select-Object -First 1
    if (-not $line) {
        Write-Error "No hay contenedor ministack-rds-* en ejecución. Corré 'tofu apply' primero."
    }
    if ($line -match '0\.0\.0\.0:(\d+)->5432') {
        return [int]$Matches[1]
    }
    if ($line -match ':(\d+)->5432') {
        return [int]$Matches[1]
    }
    Write-Error "No se pudo parsear el puerto desde: $line"
}

function Set-EnvValue([string]$Path, [string]$Key, [string]$Value) {
    $content = Get-Content $Path -Raw
    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    $replacement = "${Key}=${Value}"
    if ($content -match $pattern) {
        $newContent = [regex]::Replace($content, $pattern, $replacement)
    } else {
        $newContent = $content.TrimEnd() + "`n$replacement`n"
    }
    if ($newContent -ne $content) {
        Set-Content -Path $Path -Value $newContent -NoNewline
        return $true
    }
    return $false
}

function Set-TfvarsPort([string]$Path, [int]$Port) {
    $line = "rds_port_override = $Port"
    if (Test-Path $Path) {
        $content = Get-Content $Path -Raw
        if ($content -match '(?m)^rds_port_override\s*=\s*\d+') {
            $newContent = [regex]::Replace($content, '(?m)^rds_port_override\s*=\s*\d+.*', $line)
        } else {
            $newContent = $content.TrimEnd() + "`n$line`n"
        }
    } else {
        $newContent = "$line`n"
    }
    if ($newContent -ne (Get-Content $Path -Raw -ErrorAction SilentlyContinue)) {
        Set-Content -Path $Path -Value $newContent -NoNewline
        return $true
    }
    return $false
}

$port = Get-RdsHostPort
Write-Host "Puerto RDS detectado: $port" -ForegroundColor Cyan

$envPath = Join-Path $Root ".env"
if (-not (Test-Path $envPath)) {
    Write-Error "Falta .env en la raíz del repo."
}

$envChanged = Set-EnvValue $envPath "RDS_PORT_OVERRIDE" $port
$tfvarsPath = Join-Path $Root "infra/terraform.tfvars"
$tfvarsChanged = Set-TfvarsPort $tfvarsPath $port

if ($envChanged) {
    Write-Host "  OK .env → RDS_PORT_OVERRIDE=$port" -ForegroundColor Green
} else {
    Write-Host "  .env ya tenía RDS_PORT_OVERRIDE=$port" -ForegroundColor DarkGray
}

if ($tfvarsChanged) {
    Write-Host "  OK infra/terraform.tfvars → rds_port_override = $port" -ForegroundColor Green
} else {
    Write-Host "  terraform.tfvars ya tenía rds_port_override = $port" -ForegroundColor DarkGray
}

$pgPath = Join-Path $Root "ops/pgadmin/servers.json"
if (Test-Path $pgPath) {
    $pg = Get-Content $pgPath -Raw
    $pgNew = [regex]::Replace($pg, '(?s)("Name": "RDS MiniStack tp-dw-db \(bronce\+gold\)".*?"Port": )\d+', "`${1}$port")
    if ($pgNew -ne $pg) {
        Set-Content -Path $pgPath -Value $pgNew -NoNewline
        Write-Host "  OK ops/pgadmin/servers.json → Port=$port (recreá pgadmin si ya estaba importado)" -ForegroundColor Green
    }
}

if ($envChanged -or $tfvarsChanged) {
    Write-Host ""
    Write-Host "Siguiente (si Airflow/Lambda ya estaban levantados):" -ForegroundColor Yellow
    Write-Host "  docker compose up -d --force-recreate airflow-scheduler airflow-webserver"
    Write-Host "  docker compose --profile iac run --rm tp-iac apply"
}

if ($RecreateAirflow) {
    Write-Host ""
    Write-Host "Recreando Airflow..." -ForegroundColor Cyan
    docker compose up -d --force-recreate airflow-scheduler airflow-webserver
    Write-Host "  OK Airflow recreado" -ForegroundColor Green
}
