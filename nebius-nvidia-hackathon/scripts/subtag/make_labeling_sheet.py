"""Altın set etiketleme dosyası (Finance, Technology, Politics + Emir verisi), docs/taksonomi.md kararlarıyla.

Yöntem: önce ipucusuz 15 haber (kategorilerden dengeli, sabit tohum) → Bircan etiketler; sonra kalanlar için
LLM ön etiketi üretilir ve Bircan onaylar. İlk 15, ön etiketin ne kadar güvenilir olduğunu da ölçer.
Kullanım:
    .venv\\Scripts\\python.exe scripts\\subtag\\make_labeling_sheet.py
Çıktı: data/processed/etiketleme_v2.md (git dışında; Bircan'ın çalışma dosyası, varsa üzerine yazmaz)
"""
import html
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402

OUT = ROOT / "data" / "processed" / "etiketleme_v2.md"
SAMPLE = ROOT / "data" / "raw" / "sampleNews"
BAD = re.compile(r"not a robot|captcha|Text extraction failed|Security Verification|Incompatible browser|"
                 r"Javascript disabled|solve a puzzle|403 ERROR|technical difficulties", re.I)
PREFIX = {"Finance": "f", "Politics": "p", "Technology": "t"}
BLIND = {"Finance": 4, "Politics": 4, "Technology": 4, "Emir": 3}

HEADER = """# Altın set etiketleme v2 (Finance, Technology, Politics, Emir)

Biçim: `[tür | konu1, konu2 | bayrak1, bayrak2]` — tür TEK, konu ÇOKLU, bayrak isteğe bağlı. Tanımlar: docs/taksonomi.md.

- **Tür (ortak):** lansman-duyuru · inceleme-rehber · pazar-finans · duzenleme-hukuk · olay-kriz · gorus-analiz · sponsorlu · eglence-yasam · gelisme-haber
- **Konu / Technology:** yapay-zeka/model-urun · yapay-zeka/politika-guvenlik · yapay-zeka/is-ticaret · yapay-zeka/arastirma · donanim-cip · tuketici-cihaz · yazilim-gelistirici · bulut-altyapi · guvenlik-gizlilik · platform-sosyal · other
- **Konu / Finance:** kripto-blokzincir · borsa-piyasa · sirket-sonuc · makro-ticaret · tuketici-perakende · girisimcilik · other
- **Konu / Politics:** secim-parti · yasama-hukumet · ekonomi-vergi · dis-politika-catisma · other
- **Bayrak:** kategori-disi · dusuk-kalite · birinci-taraf

Emir verisi teknoloji haberidir (Technology konuları). Kararsız kaldığın satıra `?` ekle; tartışırız.
"""


def first_sentence(text: str, max_chars: int = 180) -> str:
    text = html.unescape(text or "").replace("\n", " ").strip()
    end = text.find(". ")
    return (text[: end + 1] if 0 < end < max_chars else text[:max_chars]).strip()


def load_items() -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = {}
    for f in sorted(SAMPLE.glob("*.json")):
        items = json.loads(f.read_text(encoding="utf-8"))
        cat = items[0]["category"]
        if cat not in PREFIX:
            continue
        groups[cat] = [{"id": f"{PREFIX[cat]}{i:02d}", "source": x["source"], "title": html.unescape(x["title"]).strip(),
                        "hint": first_sentence(x.get("content", ""))}
                       for i, x in enumerate(items) if not (BAD.search(x.get("content", "")[:400]) or len(x.get("content", "")) < 200)]
    emir = load_corpus("emir")
    summaries = json.loads(corpus_file("article_summaries.json", "emir").read_text(encoding="utf-8"))
    groups["Emir"] = [{"id": aid, "source": a["source"], "title": a["title"], "hint": summaries.get(aid, first_sentence(a["content"]))}
                      for aid, a in emir.items()]
    return groups


def main() -> None:
    if OUT.exists():
        raise SystemExit(f"{OUT} zaten var; üzerine yazmıyorum (Bircan'ın etiketleri kaybolmasın).")
    rng = random.Random(20261010)
    groups = load_items()
    blind, rest = [], []
    for cat, items in groups.items():
        picked = set(x["id"] for x in rng.sample(items, BLIND[cat]))
        blind += [(cat, x) for x in items if x["id"] in picked]
        rest += [(cat, x) for x in items if x["id"] not in picked]
    rng.shuffle(blind)  # kategori sırası ipucu vermesin
    lines = [HEADER, f"## 1. İpucusuz etiketleme ({len(blind)} haber) — önce bunları bitir", ""]
    lines += [f"{i}. `{x['id']}` ({cat}, {x['source']}) **{x['title']}** — {x['hint']}  `[ ]`" for i, (cat, x) in enumerate(blind, 1)]
    lines += ["", f"## 2. Kalanlar ({len(rest)} haber) — ilk bölüm bitince ön etiketle gelecek", ""]
    lines += [f"- `{x['id']}` ({cat}) {x['title']}" for cat, x in rest]
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(blind)} ipucusuz + {len(rest)} kalan -> {OUT}")


if __name__ == "__main__":
    main()
