# Corridas OpenTofu

Cada `.\test\capture-apply.ps1` deja una carpeta:

`<fecha>_<hora>-<acción>-OK/` o `<fecha>_<hora>-<acción>-FAIL/`

- `RESULT.txt` — `OK` / `FAIL` + exit code  
- `tofu.log` — salida completa (el error va acá si falló)

Vacío hasta la próxima corrida vía el script.
