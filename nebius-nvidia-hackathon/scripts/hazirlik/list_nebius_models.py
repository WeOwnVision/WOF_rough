"""Nebius Token Factory bağlantısını doğrula ve model listesini çek.

Anahtar .env içindeki NEBIUS_API_KEY'den okunur, ekrana basılmaz.
Kullanım:
    .venv\\Scripts\\python.exe scripts\\hazirlik\\list_nebius_models.py
"""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator.nebius import BASE_URL, load_env  # noqa: E402


def main() -> None:
    load_env()
    key = os.environ.get("NEBIUS_API_KEY", "")
    if not key:
        raise SystemExit("NEBIUS_API_KEY boş ya da .env bulunamadı.")
    print(f"anahtar yüklendi ({len(key)} karakter)")

    req = urllib.request.Request(f"{BASE_URL}/models?verbose=true", headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            models = json.load(resp)["data"]
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}")

    print(f"{len(models)} model\n")
    for m in sorted(models, key=lambda m: m["id"].lower()):
        print(m["id"])
    out = ROOT / "data" / "processed" / "nebius_models.json"
    out.write_text(json.dumps(models, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n-> {out}")


if __name__ == "__main__":
    main()
