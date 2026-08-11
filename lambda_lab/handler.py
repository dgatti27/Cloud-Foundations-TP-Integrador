import json
import time

# --- init (fuera del handler): se ejecuta sólo en cold start ---
# Todo lo que inicializás acá se paga una vez por entorno de ejecución,
# no por invocación. Acá irían clientes SDK, pools de conexión, config, etc.
BOOT_TS = time.time()
COLD = True


def handler(event, context):
    global COLD
    was_cold = COLD
    COLD = False

    monto = float(event.get("monto", 0))
    aprobado = 0 < monto <= 50000

    get_remaining = getattr(context, "get_remaining_time_in_millis", None)
    print(json.dumps({
        "request_id": context.aws_request_id,
        "cold_start": was_cold,
        "init_age_ms": round((time.time() - BOOT_TS) * 1000, 1),
        "remaining_ms": get_remaining() if get_remaining else None,
    }))

    return {
        "statusCode": 200 if aprobado else 402,
        "body": json.dumps({"aprobado": aprobado, "monto": monto}),
    }
