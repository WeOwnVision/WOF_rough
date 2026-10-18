"""Sohbet testi: baş model (+ yedek) çok turlu konuşmada; her cevap Nemotron doğrulayıcıdan geçer.

İki doğrulama modu aynı koşudan ölçülür:
  akış   — cevap akarken gösterilir, doğrulama rozeti sonra gelir (görünme = ilk metin anı)
  önce   — cevap doğrulandıktan sonra gösterilir (görünme = baş model + doğrulayıcı)
Kullanım:
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_chat.py --estimate
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_chat.py --dry-run
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_chat.py          # GERÇEK çağrı (kredi harcar)
Çıktı: data/processed/chat_eval/<ana>__<konuşma>.json
"""
import argparse
import functools
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))  # aynı klasördeki betikler

from eval_head import HINT, USER_KEYS_NOTE, check, mock_chat, semantic_setup  # noqa: E402
from src.orchestrator.verifier import sources_from_calls  # noqa: E402
from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.agent import SCOPE_RULES, SYSTEM_PROMPT, date_note, run_turn  # noqa: E402
from src.orchestrator.dictionary import KeywordDict  # noqa: E402
from src.orchestrator.tools import NewsTools, corpus_file, load_corpus  # noqa: E402
from src.orchestrator.verifier import VERIFIER_MODEL, verify  # noqa: E402

SCENARIOS = ROOT / "eval" / "chat_scenarios.json"
OUT_DIR = ROOT / "data" / "processed" / "chat_eval"
V4, V41 = "deepseek-ai/DeepSeek-V4-Flash-0731", "deepseek-ai/DeepSeek-V4.1-Flash"
CONFIGS = [[V4, V41], [V41, V4]]  # [ana, yedek]


class FailOnce:
    """Ana modelin bir sonraki çağrısına HTTP 500 enjekte eder (yedeğe geçiş testi)."""

    def __init__(self, chat, primary: str):
        self.chat, self.primary, self.armed = chat, primary, False

    def __call__(self, model, messages, tools):
        if self.armed and model == self.primary:
            self.armed = False
            raise nebius.APIError("HTTP 500: injected failure")
        return self.chat(model, messages, tools)


def sources_for(tools: NewsTools) -> dict[str, dict]:
    return sources_from_calls(tools)


def run_conversation(conv: dict, models: list[str], chat, verify_chat, corpus: dict, tool_kwargs: dict,
                     system_prompt: str, table: dict, dry: bool) -> dict:
    tools = NewsTools(corpus, None, conv.get("content_patch"), **tool_kwargs)
    chat = FailOnce(chat, models[0])
    history, turns = None, []
    for i, turn in enumerate(conv["turns"]):
        chat.armed = bool(turn.get("fail_primary"))
        res = run_turn(chat, models, turn["user"], tools, history=history, system_prompt=system_prompt)
        history = res["messages"] if res["status"] == "ok" else history
        steps = [s for a in res["attempts"] for s in a["steps"]]
        head_cost = sum(nebius.cost(a["model"], sum(s["prompt_tokens"] for s in a["steps"]),
                                    sum(s["completion_tokens"] for s in a["steps"]), table) for a in res["attempts"])
        head_ms = sum(s["ms"] for s in steps)
        final = steps[-1] if steps else {}
        stream_ms = head_ms - final.get("ms", 0) + (final.get("ttft_ms") or final.get("ms", 0))
        sources = sources_for(tools)
        ver = verify(verify_chat, res["answer"], sources) if res["answer"] and verify_chat else \
            {"verdict": "no_answer", "claims": [], "ms": 0, "prompt_tokens": 0, "completion_tokens": 0}
        ver_cost = nebius.cost(VERIFIER_MODEL, ver["prompt_tokens"], ver["completion_tokens"], table)
        turns.append({
            "turn": i + 1, "user": turn["user"], "answer": res["answer"], "status": res["status"],
            "answered_by": res["answered_by"], "attempts": [{k: a[k] for k in ("model", "status", "error")} for a in res["attempts"]],
            "checks": check(turn, res, tools), "verify": {k: ver[k] for k in ("verdict", "claims", "ms")},
            "flagged": [c for c in ver["claims"] if c.get("verdict") != "supported"],
            "head_ms": head_ms, "visible_stream_ms": round(stream_ms), "visible_blocking_ms": head_ms + ver["ms"],
            "badge_ms": head_ms + ver["ms"], "cost_usd": 0.0 if dry else head_cost + ver_cost,
            "steps": len(steps), "tool_calls": len([c for s in steps for c in s["tool_calls"]]),
            "source_ids": list(sources), "fetched_ids": sorted({json.loads(c["args"]).get("id") for c in tools.calls
                                                               if c["name"] == "get_article" and c["valid"] and not c["error"]}),
        })
    return {"conversation": conv["id"], "models": models, "turns": turns}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--search", choices=["keyword", "semantic"], default="keyword")
    ap.add_argument("--min-score", type=float, default=None, help="anlamsal arama eşiği")
    ap.add_argument("--page-size", type=int, default=10)
    ap.add_argument("--no-hint", action="store_true", help="'korpus İngilizce' ipucunu kapat")
    ap.add_argument("--convs", nargs="+", help="yalnız bu konuşmalar")
    ap.add_argument("--primary-only", action="store_true", help="yalnız V4-Flash ana ayarını koş")
    ap.add_argument("--no-verify", action="store_true", help="doğrulayıcıyı atla")
    ap.add_argument("--dictionary", action="store_true", help="anahtar kelime sözlüğü kanalını aç")
    ap.add_argument("--summaries", action="store_true", help="a: arama sonucunda haber özeti")
    ap.add_argument("--scope-rules", action="store_true", help="b: etiket-önce ve özet-önce kuralları")
    ap.add_argument("--user-keys", nargs="+", help="d: kullanıcının seçtiği sözlük anahtarları, ör. konu:ev")
    ap.add_argument("--read-budget", type=int, default=None, help="c: tur başına en fazla tam metin")
    args = ap.parse_args()

    convs = [c for c in json.loads(SCENARIOS.read_text(encoding="utf-8"))["conversations"]
             if not args.convs or c["id"] in args.convs]
    configs = CONFIGS[:1] if args.primary_only else CONFIGS
    table = nebius.prices()
    # kaba üst sınır: tur başına 3 adım; bağlam her turda ~4K token büyür; doğrulama tur başına ~5K girdi
    est = 0.0
    for models in configs:
        for conv in convs:
            for t in range(len(conv["turns"])):
                est += nebius.cost(models[0], 3 * (2500 + 4000 * t), 3 * 800, table)
                est += 0 if args.no_verify else nebius.cost(VERIFIER_MODEL, 5000 + 2000 * t, 2000, table)
    print(f"{len(configs)} ayar × {len(convs)} konuşma ({sum(len(c['turns']) for c in convs)} tur): "
          f"tahmini üst sınır ≈ {est:.3f} $")
    if args.estimate:
        return

    corpus = load_corpus()
    tool_kwargs = {"page_size": args.page_size, "min_score": args.min_score}
    if args.dry_run:
        chat = mock_chat

        def verify_chat(model, messages, tools):
            return {"message": {"content": '{"claims": [], "verdict": "ok"}'}}, {}, 1.0
    else:
        nebius.load_env()
        # 45 s veri gelmezse zaman aşımı → yedek model (Emir testinde ilk çağrı ~3 dk takıldı)
        chat = verify_chat = functools.partial(nebius.chat, stream=True, timeout=45)
    if args.no_verify:
        verify_chat = None
    if args.search == "semantic":
        embedder, vecs, _ = semantic_setup(corpus, args.dry_run)
        tool_kwargs |= {"query_embedder": embedder, "article_vecs": vecs}
    if args.dictionary:
        tool_kwargs["dictionary"] = KeywordDict.load()
    system_prompt = SYSTEM_PROMPT + date_note() + ("" if args.no_hint else HINT)
    if args.summaries:
        tool_kwargs["summaries"] = json.loads(corpus_file("article_summaries.json").read_text(encoding="utf-8"))
    if args.read_budget is not None:
        tool_kwargs["read_budget"] = args.read_budget
    if args.user_keys:
        tool_kwargs["user_keys"] = args.user_keys
        tool_kwargs.setdefault("dictionary", KeywordDict.load())
        system_prompt += USER_KEYS_NOTE.format(", ".join(args.user_keys))
    if args.scope_rules:
        system_prompt += SCOPE_RULES
    variant = ("dry_run" if args.dry_run else "run") + ("_semantic" if args.search == "semantic" else "") \
        + (f"_t{args.min_score}" if args.min_score is not None else "") + ("_nohint" if args.no_hint else "") + ("_dict" if args.dictionary else "") + ("_sum" if args.summaries else "") + ("_scope" if args.scope_rules else "") + (f"_budget{args.read_budget}" if args.read_budget is not None else "") + ("_user" if args.user_keys else "")
    out_dir = OUT_DIR / variant
    out_dir.mkdir(parents=True, exist_ok=True)

    jobs = [(conv, models) for models in configs for conv in convs]
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        results = list(pool.map(lambda j: run_conversation(j[0], j[1], chat, verify_chat, corpus, tool_kwargs,
                                                           system_prompt, table, args.dry_run), jobs))
    for r in results:
        (out_dir / f"{r['models'][0].replace('/', '_')}__{r['conversation']}.json").write_text(
            json.dumps(r, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n{'ana model':<28} {'konuşma':<20} tur  cevaplayan    geçti doğrulama  işaret  akış(s) önce(s)      $")
    for r in results:
        for t in r["turns"]:
            who = "ana" if t["answered_by"] == r["models"][0] else ("yedek" if t["answered_by"] else "—")
            print(f"{r['models'][0].split('/')[-1][:27]:<28} {r['conversation']:<20} {t['turn']:>3}  {who:<12} "
                  f"{'✓' if t['checks']['passed'] else '✗':^5} {t['verify']['verdict']:<10} {len(t['flagged']):>6} "
                  f"{t['visible_stream_ms'] / 1000:7.1f} {t['visible_blocking_ms'] / 1000:7.1f} {t['cost_usd']:7.4f}")
    for models in configs:
        ts = [t for r in results if r["models"] == models for t in r["turns"]]
        avg = lambda k: sum(t[k] for t in ts) / len(ts) / 1000  # noqa: E731
        print(f"\n{models[0].split('/')[-1]}: geçti {sum(t['checks']['passed'] for t in ts)}/{len(ts)}, "
              f"doğrulayıcı işaretledi {sum(t['verify']['verdict'] == 'flag' for t in ts)}, "
              f"ort. görünme akış {avg('visible_stream_ms'):.1f} s / önce {avg('visible_blocking_ms'):.1f} s, "
              f"maliyet {sum(t['cost_usd'] for t in ts):.4f} $")
    print(f"-> {out_dir}")


if __name__ == "__main__":
    main()
