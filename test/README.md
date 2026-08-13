# Evidencia de pruebas e IaC

Logs de corridas reales: emuladores (Compose) + OpenTofu (`infra/`) + smoke HTTP/AWS CLI.

**No hay secretos acá** (no `SecretString`, no `.env`, no `tfstate`).

## ¿Un error de IaC queda acá?

**Sí, si corrés el apply con el script de captura.** OpenTofu **no** escribe solo en `test/`; hay que invocar:

```powershell
.\test\capture-apply.ps1              # tofu apply -auto-approve
.\test\capture-apply.ps1 -Action plan
.\test\capture-apply.ps1 -Action destroy
```

Cada corrida crea `test/iac-runs/<fecha>-<acción>-OK/` o **`-FAIL/`**:

| Archivo | Contenido |
|---------|-----------|
| `RESULT.txt` | `result=OK` o `result=FAIL` + `exit_code` |
| `tofu.log` | stdout + stderr completo |
| `00-meta.txt` | host, acción, timestamp |

Si hacés `cd infra; tofu apply` a mano y falla, **ese error no se copia solo** a `test/`. Usá `capture-apply.ps1` (o pegá el log en `iac-runs/`).

`capture-smoke.ps1` registra fallos de **verificación** (IAM/S3/HTTP), no el apply.

## Corridas registradas

| Carpeta | Fecha | Qué cubre |
|---------|-------|-----------|
| [`2026-08-13-smoke/`](./2026-08-13-smoke/) | 13 ago 2026 | Apply Hobby OK + smoke **sin ETL** |
| [`iac-runs/`](./iac-runs/) | (siguientes apply/plan) | Cada IaC, incluyendo **FAIL** |

Resumen smoke: [`2026-08-13-smoke/SUMMARY.md`](./2026-08-13-smoke/SUMMARY.md).

## Recapturar smoke (post-apply)

```powershell
.\test\capture-smoke.ps1
.\test\capture-smoke.ps1 -Name 2026-08-13-smoke
```

Comandos equivalentes (manual): README §5.
