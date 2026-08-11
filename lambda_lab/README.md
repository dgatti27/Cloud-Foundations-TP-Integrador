# `lambda/` — archivos del lab 14

## `handler.py`

La función Lambda `validar-pago`. Dos responsabilidades:

- **Lógica de negocio:** aprueba montos entre 1 y 50.000; rechaza el resto con HTTP 402.
  Un 402 es un rechazo de negocio, no una falla de plataforma — Lambda lo trata como
  ejecución exitosa.
- **Observabilidad de cold start:** `BOOT_TS` y `COLD` viven fuera del handler, en el
  ámbito del entorno de ejecución. La primera vez que Lambda crea el entorno (cold start),
  `COLD = True`. Las invocaciones siguientes en el mismo entorno reusan el proceso y
  `COLD = False`. El log imprime esa diferencia, que después aparece en la línea `REPORT`
  como `Init Duration`.

## `trust_policy.json`

La *trust policy* del rol de ejecución. Define **quién puede asumir el rol**:
en este caso, el servicio `lambda.amazonaws.com`. Sin esta política, Lambda no puede
obtener credenciales temporales para correr el código.

No confundir con:
- **Permissions policy** (`AWSLambdaBasicExecutionRole`): qué puede *hacer* el código
  (en este caso, escribir logs en CloudWatch).
- **Resource policy** de la función: quién puede *invocar* la función (API Gateway,
  otro servicio, una cuenta cruzada). No la usamos en este lab.

## Dependencias del `lambda_demo.py`

El script `scripts/lambda_demo.py` zipea `handler.py` en memoria antes de pasarlo
a `create_function`. No hace falta correr `zip` manualmente.
