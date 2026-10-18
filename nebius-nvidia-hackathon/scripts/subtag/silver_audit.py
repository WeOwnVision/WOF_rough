"""Gümüş set denetimi: rastgele 15 haber, etiketler gizli → Bircan etiketler → uyum ölçülür.

Kullanım:
    .venv\\Scripts\\python.exe scripts\\subtag\\silver_audit.py make      # data/processed/denetim_15.md (varsa üzerine yazmaz)
    .venv\\Scripts\\python.exe scripts\\subtag\\silver_audit.py compare   # Bircan'ın etiketleri ile gümüş seti karşılaştır
Uyum: tür birebir eşleşme oranı, konu kümelerinde Jaccard ortalaması, bayrak eşleşmesi; ayrışan satırlar listelenir.
"""
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SILVER = ROOT / "data" / "processed" / "gold_v2_silver.json"
SHEET = ROOT / "data" / "processed" / "denetim_15.md"
LABEL = re.compile(r"`(\w+)`.*`\[\s*([^|\]]+?)\s*\|\s*([^|\]]*?)\s*(?:\|\s*([^\]]*?)\s*)?\]`")

HEADER = """# Gümüş set denetimi (15 haber, etiketler gizli)

Her satırın sonundaki `[ ]` içine kendi etiketini yaz: `[tür | konu1, konu2 | bayrak]` (bayrak yoksa `[tür | konu]`).
Tanımlar ve sınır kuralları: docs/taksonomi.md. Bitince: `.venv\\Scripts\\python.exe scripts\\subtag\\silver_audit.py compare`

- Tür: lansman-duyuru · inceleme-rehber · pazar-finans · duzenleme-hukuk · olay-kriz · gorus-analiz · sponsorlu · eglence-yasam · gelisme-haber
- Konu / Technology (Emir dahil): yapay-zeka/model-urun · yapay-zeka/politika-guvenlik · yapay-zeka/is-ticaret · yapay-zeka/arastirma · donanim-cip · tuketici-cihaz · yazilim-gelistirici · bulut-altyapi · guvenlik-gizlilik · platform-sosyal · other
- Konu / Finance: kripto-blokzincir · borsa-piyasa · sirket-sonuc · makro-ticaret · tuketici-perakende · girisimcilik · other
- Konu / Politics: secim-parti · yasama-hukumet · ekonomi-vergi · dis-politika-catisma · other
- Bayrak: kategori-disi · dusuk-kalite · birinci-taraf
"""


def make() -> None:
    if SHEET.exists():
        raise SystemExit(f"{SHEET} zaten var; üzerine yazmıyorum.")
    items = json.loads(SILVER.read_text(encoding="utf-8"))
    picked = random.Random(20261011).sample(items, 15)
    lines = [HEADER] + [f"{i}. `{x['id']}` ({x['category']}) **{x['title']}**  `[ ]`" for i, x in enumerate(picked, 1)]
    SHEET.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"15 haber -> {SHEET}")


def split(s: str | None) -> set[str]:
    return {v.strip() for v in (s or "").split(",") if v.strip()}


def compare() -> None:
    silver = {x["id"]: x for x in json.loads(SILVER.read_text(encoding="utf-8"))}
    rows = [m for m in map(LABEL.search, SHEET.read_text(encoding="utf-8").splitlines()) if m]
    if not rows:
        raise SystemExit("Etiketli satır bulunamadı.")
    tur_ok, jac, flag_ok, diffs = 0, 0.0, 0, []
    for m in rows:
        aid, tur, konu, flags = m.group(1), m.group(2).strip(), split(m.group(3)), split(m.group(4))
        s = silver[aid]
        s_konu, s_flags = set(s["konu"]), set(s["flags"])
        j = len(konu & s_konu) / len(konu | s_konu) if konu | s_konu else 1.0
        tur_ok += tur == s["tur"]
        jac += j
        flag_ok += flags == s_flags
        if tur != s["tur"] or j < 1 or flags != s_flags:
            diffs.append(f"  {aid}: sen [{tur} | {', '.join(sorted(konu))} | {', '.join(sorted(flags))}]  "
                         f"gümüş [{s['tur']} | {', '.join(s['konu'])} | {', '.join(s['flags'])}]"
                         f"{'  (gümüşte ? vardı)' if s['uncertain'] else ''}")
    n = len(rows)
    print(f"{n} haber | tür uyumu {tur_ok}/{n} = {tur_ok / n:.0%} | konu Jaccard ort. {jac / n:.2f} | bayrak uyumu {flag_ok}/{n}")
    print("Ayrışanlar:" if diffs else "Ayrışma yok.")
    print("\n".join(diffs))


if __name__ == "__main__":
    {"make": make, "compare": compare}[sys.argv[1] if len(sys.argv) > 1 else "make"]()
