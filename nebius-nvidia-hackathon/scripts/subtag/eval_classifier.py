"""Sınıflandırıcıyı (varsayılan Nemotron-3-Nano) etiket seti v2'ye karşı ölç.

Etiket seti insan altın seti değil: üç model uzlaşısı/çoğunluğu (docs/taksonomi.md). Sonuç "uzlaşıyla uyum" diye okunur.
Kullanım:
    .venv\\Scripts\\python.exe scripts\\subtag\\eval_classifier.py --estimate
    .venv\\Scripts\\python.exe scripts\\subtag\\eval_classifier.py               # GERÇEK çağrı (kredi harcar)
    .venv\\Scripts\\python.exe scripts\\subtag\\eval_classifier.py --report      # kayıtlı tahminleri yeniden raporla (ücretsiz)
"""
import argparse
import json
import sys
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # aynı klasördeki betikler

from second_annotator import load_texts, prompt_for  # noqa: E402
from src.orchestrator import nebius  # noqa: E402

GOLD = ROOT / "data" / "processed" / "gold_v2.json"
MODEL = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B"


def pred_file(model: str) -> Path:
    return ROOT / "data" / "processed" / f"classifier_{model.split('/')[-1]}.json"


def classify(model: str, item: dict) -> tuple[dict, dict, float]:
    system, schema = prompt_for(item["category"])
    user = f"Category: {item['category']}\nSource: {item['source']}\nTitle: {item['title']}\n\n{item['text']}"
    t = time.perf_counter()
    choice, usage, _ = nebius.chat(model, [{"role": "system", "content": system}, {"role": "user", "content": user}],
                                   None, max_tokens=4000, chat_template_kwargs={"enable_thinking": True},
                                   response_format={"type": "json_schema", "json_schema": {"name": "label", "schema": schema}})
    return json.loads(choice["message"]["content"] or "{}"), usage, (time.perf_counter() - t) * 1000


def report(model: str) -> None:
    gold = {x["id"]: x for x in json.loads(GOLD.read_text(encoding="utf-8"))}
    pred = json.loads(pred_file(model).read_text(encoding="utf-8"))
    groups = defaultdict(lambda: [0, 0, 0.0])  # doğru tür, toplam, konu Jaccard toplamı
    confusion = Counter()
    flag_tp = flag_fp = flag_fn = 0
    for aid, g in gold.items():
        p = pred.get(aid, {})
        ok = p.get("tur") == g["tur"]
        gk, pk = set(g["konu"]), set(p.get("konu", []))
        jac = len(gk & pk) / len(gk | pk) if gk | pk else 1.0
        cat = "Technology" if g["category"] == "Emir" else g["category"]
        for key in ("HEPSİ", f"durum:{g['status']}", f"kategori:{cat}"):
            groups[key][0] += ok
            groups[key][1] += 1
            groups[key][2] += jac
        if not ok:
            confusion[(g["tur"], p.get("tur"))] += 1
        gf, pf = set(g["flags"]), set(p.get("flags", []))
        flag_tp, flag_fp, flag_fn = flag_tp + len(gf & pf), flag_fp + len(pf - gf), flag_fn + len(gf - pf)
    print(f"{model} — etiket seti v2'ye karşı (üç model uzlaşısı, insan altını değil)")
    for key in ["HEPSİ"] + sorted(k for k in groups if k != "HEPSİ"):
        c, n, j = groups[key]
        print(f"  {key:<24} tür {c:>3}/{n:<3} = {c / n:5.0%}   konu Jaccard {j / n:.2f}")
    print(f"  bayrak: doğru {flag_tp}, fazladan {flag_fp}, kaçan {flag_fn}")
    print("  en sık tür karışıklıkları (gerçek → tahmin):", confusion.most_common(6))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if args.report:
        return report(args.model)
    items, table = load_texts(), nebius.prices()
    est = sum(nebius.cost(args.model, (len(prompt_for(x["category"])[0]) + len(x["text"]) + len(x["title"])) // 4 + 50, 1000, table)
              for x in items.values())
    print(f"{len(items)} haber, {args.model}, tahmini üst sınır ≈ {est:.3f} $")
    if args.estimate:
        return
    nebius.load_env()
    with ThreadPoolExecutor(max_workers=8) as pool:
        res = dict(zip(items, pool.map(lambda x: classify(args.model, x), items.values())))
    spent = sum(nebius.cost(args.model, u.get("prompt_tokens", 0), u.get("completion_tokens", 0), table) for _, u, _ in res.values())
    ms = sorted(m for _, _, m in res.values())
    pred_file(args.model).write_text(json.dumps({k: v for k, (v, _, _) in res.items()}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"maliyet {spent:.4f} $ | medyan {ms[len(ms) // 2] / 1000:.1f} s/haber -> {pred_file(args.model)}")
    report(args.model)


if __name__ == "__main__":
    main()
