"""Korpustaki her haber için arama vektörü üret (Qwen3-Embedding-8B), data/processed/article_vecs[_<korpus>].json.

Metin: başlık + metnin ilk 6000 karakteri (ingest ve arama ile aynı). Anlamsal arama ve eşik (0,46) bu vektörlere göre.
Kullanım:
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_vectors.py --corpus emir2 --estimate
    .venv\\Scripts\\python.exe scripts\\hazirlik\\build_vectors.py --corpus emir2           # GERÇEK çağrı (çok ucuz)
Kaldığı yerden devam eder: vektörü olan haber yeniden istenmez.
"""
import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # toplu.py

from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.ingest import EMBED_MODEL  # noqa: E402
from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402
from toplu import load_done, save  # noqa: E402

BATCH = 32  # istek başına metin


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--corpus", default="automotive")
    args = ap.parse_args()
    corpus, table = load_corpus(args.corpus), nebius.prices()
    out_file = corpus_file("article_vecs.json", args.corpus)
    done = load_done(out_file)
    todo = [aid for aid in corpus if aid not in done]
    texts = {aid: corpus[aid]["title"] + "\n\n" + corpus[aid]["content"][:6000] for aid in todo}
    est = nebius.cost(EMBED_MODEL, sum(len(t) for t in texts.values()) // 4, 0, table)
    print(f"{len(corpus)} haber, {len(done)} vektörlü, bu koşuda {len(todo)} | tahmini ≈ {est:.4f} $")
    if args.estimate or not todo:
        return
    nebius.load_env()
    tokens, t0 = 0, time.perf_counter()
    for i in range(0, len(todo), BATCH):
        ids = todo[i:i + BATCH]
        for attempt in range(3):
            try:
                vecs, used = nebius.embed([texts[a] for a in ids], EMBED_MODEL)
                break
            except Exception as e:  # geçici hata: bekle, yeniden dene; üçüncüde kaydedip dur
                if attempt == 2:
                    save(out_file, done)
                    sys.exit(f"durdu ({type(e).__name__}: {str(e)[:150]}); yeniden çalıştırınca kaldığı yerden devam eder")
                time.sleep(3)
        done.update(zip(ids, vecs))
        tokens += used
        if (i // BATCH) % 5 == 4 or i + BATCH >= len(todo):  # dosya büyük (1000 haber ≈ 80 MB): 5 istekte bir kaydet
            save(out_file, done)
        print(f"  [{min(i + BATCH, len(todo))}/{len(todo)}] {time.perf_counter() - t0:.0f} s", flush=True)
    print(f"{len(done)} vektör, {tokens} token ≈ {nebius.cost(EMBED_MODEL, tokens, 0, table):.4f} $ -> {out_file}")


if __name__ == "__main__":
    main()
