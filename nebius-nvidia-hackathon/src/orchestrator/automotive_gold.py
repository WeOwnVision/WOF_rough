"""Automotive altın seti: taksonomi açıklamaları ve etiket okuyucu (LLM ölçümleri kullanır)."""
import re
from pathlib import Path

from .taxonomy import KONU, TUR

ROOT = Path(__file__).resolve().parents[2]

RAW = ROOT / "data" / "raw" / "sampleNews" / "automotive.json"
LABELS = ROOT / "data" / "processed" / "titles_by_category.md"
AXES = ("tur", "konu")

# TASLAK açıklamalar — etiket adları Bircan'ın; açıklamaları Bircan gözden geçirecek (Tur 3).
# tanımların tek kaynağı: src/orchestrator/taxonomy.py
CRITERIA = {"tur": TUR, "konu": KONU["Automotive"]}
QUESTIONS = {
    "tur": "What type of automotive article is this?",
    "konu": "Which vehicle segment or technology is this article mainly about?",
}


def labels_of(value: str | None) -> set[str]:
    """Çoklu etiket: "performans-ozel, ev" -> {"performans-ozel", "ev"} (Bircan kararı 2026-10-10)."""
    return {v.strip() for v in (value or "").split(",") if v.strip()}


def load_gold() -> dict[str, tuple[str, str]]:
    """Başlık -> (tür, konu). Konu virgülle ayrılmış birden çok etiket olabilir; üçüncü alan (bayraklar) atlanır.

    Biçim: `[tür | konu1, konu2 | bayrak1, bayrak2]` (docs/taksonomi.md)."""
    text = LABELS.read_text(encoding="utf-8")
    section = text.split("## Automotive", 1)[1].split("\n## ", 1)[0]
    gold = {}
    for m in re.finditer(r"\*\*(.+?)\*\*.*`\[\s*([^|\]]+?)\s*\|\s*([^|\]]+?)\s*(?:\|[^\]]*)?\]`", section):
        gold[m.group(1).strip()] = (m.group(2), m.group(3))
    return gold
