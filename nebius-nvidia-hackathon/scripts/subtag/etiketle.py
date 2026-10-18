"""Haberleri alt etiketlere ayır (tür | konu | bayrak). Eski try_laya.py'nin yerine, ürünün kendi sınıflandırıcısıyla.

Ürünle aynı çağrı: ingest.classify_article (Nemotron-3-Nano, düşünme açık), tanımlar src/orchestrator/taxonomy.py.
Ölçülen doğruluk (etiket seti v2, üç model uzlaşısına karşı): tür %79, net vakalarda %88; konu Jaccard 0,79.
Konu etiketleri kategoriye özeldir: --kategori Automotive | Technology | Finance | Politics. automotive ve emir
korpusunda varsayılan vardır; karışık korpusta (emir2) kategoriyi siz verin.

Kullanım:
    .venv\\Scripts\\python.exe scripts\\subtag\\etiketle.py --corpus emir --limit 20 --estimate   # maliyet tahmini, çağrı yok
    .venv\\Scripts\\python.exe scripts\\subtag\\etiketle.py --corpus emir --limit 20              # GERÇEK çağrı (kredi harcar)
    .venv\\Scripts\\python.exe scripts\\subtag\\etiketle.py --corpus emir2 --kategori Technology
    .venv\\Scripts\\python.exe scripts\\subtag\\etiketle.py --corpus emir --report                # kayıtlı etiketler (ücretsiz)
Çıktı: data/processed/subtags_<korpus>.json  {id: {"title", "category", "tur", "konu", "flags"}}.
Daha önce etiketlenen haberler atlanır; yarıda kesilirse kaldığı yerden devam eder.
"""
import argparse
import functools
import json
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.ingest import CLASSIFY_MODEL, classify_article  # noqa: E402
from src.orchestrator.taxonomy import KONU, prompt_for  # noqa: E402
from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402

DEFAULT_CATEGORY = {"automotive": "Automotive", "emir": "Technology"}


def out_file(corpus: str) -> Path:
    return ROOT / "data" / "processed" / f"subtags_{corpus}.json"


def report(labels: dict) -> None:
    tur = Counter(v["tur"] for v in labels.values())
    konu = Counter(k for v in labels.values() for k in v["konu"])
    flags = Counter(f for v in labels.values() for f in v["flags"])
    print(f"{len(labels)} haber etiketli")
    print("  tür :", ", ".join(f"{k} {n}" for k, n in tur.most_common()))
    print("  konu:", ", ".join(f"{k} {n}" for k, n in konu.most_common(12)))
    print("  bayrak:", ", ".join(f"{k} {n}" for k, n in flags.most_common()) or "-")
    print("\nÖrnekler:")
    for v in list(labels.values())[:8]:
        print(f"  [{v['tur']} | {', '.join(v['konu'])}{' | ' + ', '.join(v['flags']) if v['flags'] else ''}]  {v['title'][:80]}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Haberleri alt etiketlere ayır (tür | konu | bayrak).")
    ap.add_argument("--corpus", default="emir", help="automotive | emir | data/raw altındaki klasör adı (ör. emir2)")
    ap.add_argument("--kategori", choices=sorted(KONU), help="konu ekseni için kategori")
    ap.add_argument("--limit", type=int, help="en fazla bu kadar yeni haber etiketle")
    ap.add_argument("--estimate", action="store_true", help="yalnız maliyet tahmini (ücretsiz)")
    ap.add_argument("--report", action="store_true", help="kayıtlı etiketleri özetle (ücretsiz)")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    path = out_file(args.corpus)
    labels = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    if args.report:
        return report(labels)
    category = args.kategori or DEFAULT_CATEGORY.get(args.corpus)
    if not category:
        ap.error(f"{args.corpus} korpusu için --kategori verin ({', '.join(sorted(KONU))})")

    corpus = load_corpus(args.corpus)
    sum_file = corpus_file("article_summaries.json", args.corpus)
    summaries = json.loads(sum_file.read_text(encoding="utf-8")) if sum_file.exists() else {}
    todo = [aid for aid in corpus if aid not in labels][:args.limit]
    table = nebius.prices()
    system_chars = len(prompt_for(category)[0])
    # üst sınır: girdi = sistem prompt'u + başlık + özet + 900 karakter metin; çıktı (düşünme dahil) ~1000 token
    est = sum(nebius.cost(CLASSIFY_MODEL, (system_chars + len(corpus[a]["title"]) + len(summaries.get(a, "")) + 900) // 4 + 50,
                          1000, table) for a in todo)
    print(f"{args.corpus}: {len(corpus)} haber, {len(labels)} etiketli, bu koşuda {len(todo)} | kategori {category} | "
          f"tahmini üst sınır ≈ {est:.4f} $")
    if args.estimate or not todo:
        return

    nebius.load_env()
    chat = functools.partial(nebius.chat, timeout=90)
    spent, t0, failed = 0.0, time.perf_counter(), 0

    def one(aid):
        a = corpus[aid]
        return aid, *classify_article(chat, {**a, "summary": summaries.get(aid)}, category)

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(one, aid) for aid in todo]
        for i, fut in enumerate(as_completed(futures), 1):
            try:
                aid, lab, usage = fut.result()
            except Exception as e:  # tek haberin hatası koşuyu durdurmasın; sonraki koşuda yeniden denenir
                failed += 1
                print(f"  hata: {type(e).__name__}: {str(e)[:120]}")
                continue
            spent += nebius.cost(CLASSIFY_MODEL, usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0), table)
            labels[aid] = {"title": corpus[aid]["title"], "category": category, "tur": lab.get("tur"),
                           "konu": lab.get("konu", []), "flags": lab.get("flags", [])}
            if i % 10 == 0 or i == len(todo):
                path.write_text(json.dumps(labels, ensure_ascii=False, indent=1), encoding="utf-8")  # ara kayıt
                print(f"  [{i}/{len(todo)}] {time.perf_counter() - t0:.0f} s, {spent:.4f} $")
    path.write_text(json.dumps(labels, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\nbitti: {len(todo) - failed} etiketlendi, {failed} hata | maliyet {spent:.4f} $ -> {path}\n")
    report(labels)


if __name__ == "__main__":
    main()
