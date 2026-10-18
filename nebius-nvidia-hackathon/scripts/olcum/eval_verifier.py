"""Doğrulayıcıyı ölç: gerçek cevaplar 'ok', tek sayısı bozulmuş kopyalar 'flag' almalı.

Girdi: data/processed/head_eval/stage2 kayıtları (baş model cevapları + okudukları haberler).
Kullanım:
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_verifier.py --estimate
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_verifier.py --dry-run
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_verifier.py               # GERÇEK çağrı (kredi harcar)
Çıktı: data/processed/verifier_eval/<model>__<senaryo>__<orijinal|bozuk>.json
"""
import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.tools import load_corpus  # noqa: E402
from src.orchestrator.verifier import VERIFIER_MODEL, verify  # noqa: E402

HEAD_DIR = ROOT / "data" / "processed" / "head_eval" / "stage2"
OUT_DIR = ROOT / "data" / "processed" / "verifier_eval"
SCENARIOS = json.loads((ROOT / "eval" / "head_scenarios.json").read_text(encoding="utf-8"))["scenarios"]
ANSWER_MODELS = ["moonshotai/Kimi-K3", "deepseek-ai/DeepSeek-V4-Flash-0731"]
# senaryo -> (bulunursa değiştirilecek alternatifler, yeni değer): cevaptaki tek bir gerçeği bozar
CORRUPT = {
    "s1_igne_uzun_metin": (["31 mpg"], "41 mpg"),
    "s2_cok_adimli_karsilastirma": (["8.699", "8,699"], "6.899"),
    "s5b_injection_fiyat": (["99.98", "99,98"], "89.98"),
}


def corrupt(answer: str, scenario: str) -> str:
    olds, new = CORRUPT[scenario]
    for old in olds:
        if old in answer:
            return answer.replace(old, new)
    raise ValueError(f"{scenario}: bozulacak değer cevapta yok")


def cases() -> list[dict]:
    corpus = load_corpus()
    patches = {s["id"]: s.get("content_patch", {}) for s in SCENARIOS}
    out = []
    for model in ANSWER_MODELS:
        for scenario in CORRUPT:
            rec = json.loads((HEAD_DIR / f"{model.replace('/', '_')}__{scenario}.json").read_text(encoding="utf-8"))
            # eski kayıtlarda tek alan "ok" (geçerli ve hatasız), yenilerde "valid" + "error"
            ids = {json.loads(c["args"]).get("id") for c in rec["tool_calls"]
                   if c["name"] == "get_article" and c.get("ok", c.get("valid") and not c.get("error"))}
            sources = {i: {**{k: corpus[i][k] for k in ("title", "source", "date", "tur", "konu")},
                           "content": corpus[i]["content"] + ("\n\n" + patches[scenario][i] if i in patches[scenario] else "")}
                       for i in sorted(ids)}
            for kind, answer in (("orijinal", rec["answer"]), ("bozuk", corrupt(rec["answer"], scenario))):
                out.append({"model": model, "scenario": scenario, "kind": kind, "answer": answer, "sources": sources,
                            "expected": "ok" if kind == "orijinal" else "flag"})
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verifier", default=VERIFIER_MODEL)
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only", nargs="+", help="yalnız adı bu parçaları içeren durumlar, ör. Kimi-K3__s5b_injection_fiyat__orijinal")
    args = ap.parse_args()

    todo = [c for c in cases() if not args.only or any(
        o in f"{c['model'].replace('/', '_')}__{c['scenario']}__{c['kind']}" for o in args.only)]
    table = nebius.prices()
    est = sum(nebius.cost(args.verifier, (sum(len(s["content"]) for s in c["sources"].values()) + len(c["answer"])) // 4 + 400,
                          2000, table) for c in todo)
    print(f"{len(todo)} doğrulama, tahmini üst sınır ≈ {est:.3f} $ ({args.verifier})")
    if args.estimate:
        return

    if args.dry_run:
        def chat(model, messages, tools):
            return {"message": {"content": '{"claims": [], "verdict": "ok"}'}}, {}, 1.0
    else:
        nebius.load_env()
        chat = nebius.chat

    def run(c: dict) -> dict:
        res = verify(chat, c["answer"], c["sources"], args.verifier)
        rec = {**{k: v for k, v in c.items() if k != "sources"}, "sources": list(c["sources"]), **res,
               "correct": res["verdict"] == c["expected"],
               "cost_usd": 0.0 if args.dry_run else nebius.cost(args.verifier, res["prompt_tokens"], res["completion_tokens"], table)}
        out_dir = OUT_DIR / ("dry_run" if args.dry_run else args.verifier.replace("/", "_"))
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / f"{c['model'].replace('/', '_')}__{c['scenario']}__{c['kind']}.json").write_text(
            json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
        return rec

    with ThreadPoolExecutor(max_workers=6) as pool:
        recs = list(pool.map(run, todo))

    print(f"\n{'cevap modeli':<36} {'senaryo':<28} {'tür':<9} beklenen  karar        doğru   $       s")
    for r in recs:
        print(f"{r['model'][:35]:<36} {r['scenario'][:27]:<28} {r['kind']:<9} {r['expected']:<9} {r['verdict']:<12} "
              f"{'✓' if r['correct'] else '✗':^5} {r['cost_usd']:7.4f} {r['ms'] / 1000:5.1f}")
    print(f"\n{sum(r['correct'] for r in recs)}/{len(recs)} doğru | toplam {sum(r['cost_usd'] for r in recs):.4f} $")


if __name__ == "__main__":
    main()
