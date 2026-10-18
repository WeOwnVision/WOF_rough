"""Korpustaki her haber için kısa özet üret (Nemotron-Nano), data/processed/article_summaries.json.

Kullanım:
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_summaries.py --estimate
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_summaries.py           # GERÇEK çağrı (kredi harcar)
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # toplu.py

from src.orchestrator import nebius  # noqa: E402
from toplu import load_done, run_batch  # noqa: E402
from src.orchestrator.ingest import SUMMARY_MODEL, summarize_article  # noqa: E402
from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--corpus", default="automotive")
    args = ap.parse_args()
    corpus, table = load_corpus(args.corpus), nebius.prices()
    out_file = corpus_file("article_summaries.json", args.corpus)
    done = load_done(out_file)  # kaldığı yerden devam: özeti olan haber yeniden istenmez
    todo = {aid: a for aid, a in corpus.items() if aid not in done}
    est = sum(nebius.cost(SUMMARY_MODEL, min(len(a["content"]), 6000) // 4 + 150, 120, table) for a in todo.values())
    print(f"{len(corpus)} haber, {len(done)} özetli, bu koşuda {len(todo)} | tahmini üst sınır ≈ {est:.4f} $")
    if args.estimate or not todo:
        return
    nebius.load_env()
    usages, failed = run_batch(todo, lambda a: summarize_article(nebius.chat, a), done, out_file)
    spent = sum(nebius.cost(SUMMARY_MODEL, u.get("prompt_tokens", 0), u.get("completion_tokens", 0), table) for u in usages)
    print(f"maliyet {spent:.4f} $, {len(failed)} hata (yeniden çalıştırınca denenir) -> {out_file}")
    for aid in list(todo)[:4]:
        print(f"  {aid}: {done.get(aid)}")


if __name__ == "__main__":
    main()
