"""Anlamsal arama eşiğini kalibre et: alakalı haberler eşiğin üstünde, alakasızlar altında kalsın.

Makale vektörleri önbellekten (data/processed/article_vecs.json); yalnız sorgular embedding'e çevrilir (kuruşun altı).
Kullanım:
    .venv\\Scripts\\python.exe scripts\\olcum\\calibrate_threshold.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # aynı klasördeki betikler

from eval_head import EMBED_MODEL, semantic_setup  # noqa: E402
from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.tools import cosine, load_corpus  # noqa: E402

# TASLAK — sorgu -> alakalı haber id'leri (Bircan gözden geçirecek). Boş küme = korpusta cevabı yok.
QUERIES = {
    "elektrikli araç": {"a00", "a13", "a15"},
    "Tesla isim değişikliği": {"a14"},
    "Porsche satışları": {"a09"},
    "hibrit sistem": {"a10", "a11"},
    "uçan araba": {"a02"},
    "akü şarj cihazı": {"a04"},
    "Paris otomobil fuarı Çinli markalar": {"a06"},
    "Kia K5 incelemesi": {"a12"},
    "kablosuz şarj yolu": {"a00"},
    "self-driving name change Europe": {"a14"},
    "Italian supercar": {"a08"},
    "Ferrari elektrikli model": set(),
    "uçak bileti fiyatları": set(),
}


def main() -> None:
    nebius.load_env()
    corpus = load_corpus()
    embed_query, vecs, used = semantic_setup(corpus, dry_run=False)
    scores = {q: {aid: cosine(embed_query(q), v) for aid, v in vecs.items()} for q in QUERIES}

    for q, rel in QUERIES.items():
        top = sorted(scores[q].items(), key=lambda kv: -kv[1])[:5]
        print(f"{q:<38} " + "  ".join(f"{aid}{'*' if aid in rel else ''}:{s:.3f}" for aid, s in top))

    best = None
    print(f"\n{'eşik':>6} {'kesinlik':>9} {'duyarlılık':>11} {'F1':>6} {'boş sorgu sızıntısı':>20}")
    for i in range(30, 71):
        t = i / 100
        tp = sum(scores[q][a] >= t for q, rel in QUERIES.items() for a in rel)
        fp = sum(scores[q][a] >= t for q, rel in QUERIES.items() for a in scores[q] if a not in rel)
        fn = sum(scores[q][a] < t for q, rel in QUERIES.items() for a in rel)
        leak = sum(any(s >= t for s in scores[q].values()) for q, rel in QUERIES.items() if not rel)
        prec = tp / (tp + fp) if tp + fp else 0.0
        rec = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0.0
        if i % 2 == 0 or (best and abs(t - best[0]) < 0.011):
            print(f"{t:6.2f} {prec:9.2f} {rec:11.2f} {f1:6.2f} {leak:>20}")
        if best is None or f1 > best[1]:
            best = (t, f1)
    print(f"\nen iyi F1 eşiği: {best[0]:.2f} (F1 {best[1]:.2f}) | embedding {used[0]} token "
          f"≈ {used[0] * nebius.prices()[EMBED_MODEL][0]:.6f} $")


if __name__ == "__main__":
    main()
