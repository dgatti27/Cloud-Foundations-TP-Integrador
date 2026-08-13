# Corre OpenTofu y **siempre** deja el log en test/iac-runs/, OK o FAIL.
# Uso (raíz del repo, emuladores ya up):
#   .\test\capture-apply.ps1                 # tofu apply -auto-approve
#   .\test\capture-apply.ps1 -Action plan
#   .\test\capture-apply.ps1 -Action destroy
#   .\test\capture-apply.ps1 -Action init
# No escribe tfstate ni SecretString (solo stdout/stderr + exit_code).

[CmdletBinding()]
param(
  [ValidateSet("apply", "plan", "destroy", "init")]
  [string]$Action = "apply",
  [switch]$NoAutoApprove
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root "compose.yaml"))) {
  $Root = (Get-Location).Path
}
$Infra = Join-Path $Root "infra"
if (-not (Test-Path (Join-Path $Infra "main.tf"))) {
  Write-Error "No encuentro infra/main.tf (cwd=$Root)"
  exit 1
}

$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:PYTHONIOENCODING = "utf-8"

$Utf8 = New-Object System.Text.UTF8Encoding $false
function Save-Utf8([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, ($Text.TrimEnd() + "`n"), $Utf8)
}

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$runs = Join-Path $Root "test\iac-runs"
New-Item -ItemType Directory -Force -Path $runs | Out-Null
$tmpOut = Join-Path $runs "$stamp-$Action-pending"
New-Item -ItemType Directory -Force -Path $tmpOut | Out-Null

$tofuArgs = @("-no-color")
switch ($Action) {
  "init" { $tofuArgs = @("init", "-input=false") }
  "plan" { $tofuArgs = @("plan", "-no-color", "-input=false", "-detailed-exitcode") }
  "apply" {
    $tofuArgs = @("apply", "-no-color", "-input=false")
    if (-not $NoAutoApprove) { $tofuArgs += "-auto-approve" }
  }
  "destroy" {
    $tofuArgs = @("destroy", "-no-color", "-input=false")
    if (-not $NoAutoApprove) { $tofuArgs += "-auto-approve" }
  }
}

Save-Utf8 (Join-Path $tmpOut "00-meta.txt") @"
TP Integrador — corrida IaC (OpenTofu)
action=$Action
args=$($tofuArgs -join ' ')
fecha_local=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
host=$env:COMPUTERNAME
cwd=$Infra
"@

Write-Host "IaC $Action → log en $tmpOut"
Write-Host ("tofu " + ($tofuArgs -join " "))

Push-Location $Infra
$started = Get-Date
$output = & tofu @tofuArgs 2>&1 | Out-String
$exit = $LASTEXITCODE
$elapsed = [int]((Get-Date) - $started).TotalSeconds
Pop-Location

# plan: 0=no changes, 2=changes; ambos son corrida OK. 1=error.
$ok = if ($Action -eq "plan") { ($exit -eq 0) -or ($exit -eq 2) } else { $exit -eq 0 }
$status = if ($ok) { "OK" } else { "FAIL" }

Save-Utf8 (Join-Path $tmpOut "tofu.log") @"
=== tofu $Action ===
utc=$(Get-Date -Format o)
elapsed_s=$elapsed
exit_code=$exit
result=$status

$output
"@

Save-Utf8 (Join-Path $tmpOut "RESULT.txt") @"
result=$status
action=$Action
exit_code=$exit
elapsed_s=$elapsed
# apply/destroy/init: 0=OK, !=0=FAIL
# plan: 0=no changes (OK), 2=hay diff (OK), 1=error (FAIL)
log=tofu.log
"@

$final = Join-Path $runs "$stamp-$Action-$status"
if (Test-Path $final) { Remove-Item -Recurse -Force $final }
Rename-Item -LiteralPath $tmpOut -NewName (Split-Path $final -Leaf)

Write-Host ""
Write-Host "result=$status  exit=$exit  ${elapsed}s"
Write-Host "log=$final\tofu.log"
if (-not $ok) {
  Write-Host "ERROR de IaC registrado en test/iac-runs/ (carpeta *-FAIL)."
  exit $exit
}
exit 0
