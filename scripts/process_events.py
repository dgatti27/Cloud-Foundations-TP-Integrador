import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / "data" / "raw" / "events.jsonl"
target_path = ROOT / "data" / "processed" / "signups.json"
environment = os.getenv("APP_ENV", "local")

events = []

with source_path.open() as source:
    for line in source:
        events.append(json.loads(line))

signups = [event for event in events if event["event"] == "signup"]

target_path.parent.mkdir(parents=True, exist_ok=True)

with target_path.open("w") as target:
    json.dump(signups, target, indent=2)

print(f"Environment: {environment}")
print(f"Eventos leidos: {len(events)}")
print(f"Signups encontrados: {len(signups)}")
print(f"Salida: {target_path}")

