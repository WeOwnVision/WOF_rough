"""Korpustan anahtar kelime sözlüğünü kur (Nemotron-Nano ile çıkarım).

Kullanım:
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_dictionary.py --estimate
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_dictionary.py           # GERÇEK çağrı (kredi harcar)
Çıktı: data/processed/keyword_dict.json (+ ham çıkarım: keyword_extract.json)
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # toplu.py

from src.orchestrator import nebius  # noqa: E402
from toplu import load_done, run_batch  # noqa: E402
from src.orchestrator.dictionary import EXTRACT_MODEL, KeywordDict, extract_entities  # noqa: E402
from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402



def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--from-cache", action="store_true", help="kayıtlı varlık çıkarımından kur (ücretsiz)")
    ap.add_argument("--corpus", default="automotive")
    args = ap.parse_args()
    corpus = load_corpus(args.corpus)
    raw_file, dict_file = corpus_file("entity_extract.json", args.corpus), corpus_file("keyword_dict.json", args.corpus)
    table = nebius.prices()
    extracted = {aid: v for aid, v in load_done(raw_file).items() if aid in corpus}  # kaldığı yerden devam
    todo = {aid: a for aid, a in corpus.items() if aid not in extracted}
    est = sum(nebius.cost(EXTRACT_MODEL, (len(a["title"]) + min(len(a["content"]), 3000)) // 4 + 200, 400, table)
              for a in todo.values())
    print(f"{len(corpus)} haber, {len(extracted)} çıkarımı hazır, bu koşuda {len(todo)} | tahmini üst sınır ≈ {est:.4f} $")
    if args.estimate:
        return

    if args.from_cache:
        extracted = json.loads(raw_file.read_text(encoding="utf-8"))
        d = KeywordDict.build(extracted, {aid: {"tur": a["tur"], "konu": a["konu"]} for aid, a in corpus.items()})
        d.save(dict_file)
        print(f"{len(d.entries)} anahtar (önbellekten) -> {dict_file}")
        return
    spent, failed = 0.0, []
    if todo:
        nebius.load_env()
        usages, failed = run_batch(todo, lambda a: extract_entities(nebius.chat, a), extracted, raw_file)
        spent = sum(nebius.cost(EXTRACT_MODEL, u.get("prompt_tokens", 0), u.get("completion_tokens", 0), table) for u in usages)
    d = KeywordDict.build(extracted, {aid: {'tur': a['tur'], 'konu': a['konu']} for aid, a in corpus.items() if aid in extracted})
    d.save(dict_file)
    print(f"{len(d.entries)} anahtar, maliyet {spent:.4f} $, {len(failed)} hata (yeniden çalıştırınca denenir) -> {dict_file}")
    for key, e in sorted(d.entries.items(), key=lambda kv: -len(kv[1]["articles"]))[:12]:
        print(f"  {key:<28} {e['type']:<7} {sorted(e['articles'])}  takma: {sorted(e['aliases'])[:4]}")


if __name__ == "__main__":
    main()
