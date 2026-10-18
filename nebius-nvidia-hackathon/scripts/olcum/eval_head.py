"""Baş model adaylarını senaryolarla ölç (eval/head_scenarios.json).

Kullanım:
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_head.py --stage 1 --estimate     # yalnız maliyet tahmini, çağrı yok
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_head.py --stage 1 --dry-run      # sahte modelle tesisat testi, ücretsiz
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_head.py --stage 1                # GERÇEK çağrı (kredi harcar)
    .venv\\Scripts\\python.exe scripts\\olcum\\eval_head.py --stage 2 --models moonshotai/Kimi-K3 ...
Sonuçlar: data/processed/head_eval/stage<N>/<model>__<senaryo>.json (varsa tekrar çağrılmaz; --force ile yeniden)
"""
import argparse
import functools
import hashlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.agent import HINT, SCOPE_RULES, SYSTEM_PROMPT, USER_KEYS_NOTE, date_note, run_agent  # noqa: E402
from src.orchestrator.dictionary import KeywordDict  # noqa: E402
from src.orchestrator.clusters import cluster  # noqa: E402
from src.orchestrator.tools import NewsTools, corpus_file, load_corpus  # noqa: E402

SCENARIOS = ROOT / "eval" / "head_scenarios.json"
OUT_DIR = ROOT / "data" / "processed" / "head_eval"
PILOT_MODELS = [
    "nvidia/nemotron-3-super-120b-a12b",
    "Qwen/Qwen3.5-397B-A17B",
    "zai-org/GLM-5.3-Flash",
    "MiniMaxAI/MiniMax-M3",
    "deepseek-ai/DeepSeek-V4-Flash-0731",
    "deepseek-ai/DeepSeek-V4-Pro-0813",
    "moonshotai/Kimi-K2.6",
    "moonshotai/Kimi-K3",
]
# Kaba üst sınır tahmini: senaryo -> (adım sayısı, okunan metin token'ı). Bağlam her adımda yeniden gönderilir.
ESTIMATE = {"p1_ev_ozet": (4, 3000), "s1_igne_uzun_metin": (3, 2600), "s2_cok_adimli_karsilastirma": (4, 2000),
            "s3_korpusta_yok": (3, 500), "s4_tool_hatasi": (5, 1200), "s5_prompt_injection": (4, 1500), "s5b_injection_fiyat": (4, 1500),
            "s6_tum_korpus_toplama": (16, 16000), "e1_haftanin_gelismeleri": (6, 8000), "e2_neden": (4, 5000),
            "e3_zaman_sirasi": (4, 4000), "e4_korpusta_yok": (3, 1000)}
BASE_TOKENS, OUT_PER_STEP = 1500, 1000
EMBED_MODEL = "Qwen/Qwen3-Embedding-8B"
QUERY_PREFIX = "Instruct: Given a news search query, retrieve news articles relevant to the query\nQuery: "
NOT_FOUND = ["bulunamadı", "bulamadım", "yer almıyor", "bulunmuyor", "yok", "içermiyor", "not found", "no information"]


def estimate(model: str, scenario_id: str, table: dict) -> float:
    steps, fetched = ESTIMATE[scenario_id]
    prompt = steps * BASE_TOKENS + steps * fetched // 2  # bağlam doğrusal büyür
    return nebius.cost(model, prompt, steps * OUT_PER_STEP, table)


def mock_chat(model, messages, tools):
    """Ücretsiz sahte model: ara -> ilk sonucu getir (+ bir geçersiz çağrı) -> cevap ver."""
    tool_msgs = [m for m in messages if m["role"] == "tool"]
    usage = {"prompt_tokens": len(json.dumps(messages)) // 4, "completion_tokens": 50}

    def call(i, name, args):
        return {"id": f"c{len(messages)}_{i}", "type": "function", "function": {"name": name, "arguments": json.dumps(args)}}
    if not tool_msgs:
        msg = {"content": "", "tool_calls": [call(0, "search_news", {"query": ""})]}
    elif len(tool_msgs) == 1:
        first = json.loads(tool_msgs[0]["content"])["results"][0]["id"]
        msg = {"content": "", "tool_calls": [call(0, "get_article", {"id": first}), call(1, "get_article", {"wrong": 1})]}
    else:
        msg = {"content": "mock cevap [a00]"}
    return {"message": msg, "finish_reason": "stop"}, usage, 1.0


def check(sc: dict, result: dict, tools: NewsTools) -> dict:
    answer = (result.get("answer") or "")
    low = answer.lower()
    fetched = set()
    for c in tools.calls:
        if c["name"] == "get_article" and c["valid"] and not c["error"]:
            try:
                fetched.add(json.loads(c["args"]).get("id"))
            except json.JSONDecodeError:
                pass
    rules = sc.get("checks", {})
    out = {}
    if "must_fetch" in rules:
        out["must_fetch"] = all(i in fetched for i in rules["must_fetch"])
    if "cite_all" in rules:
        out["cite_all"] = all(any(alt.lower() in low for alt in group) for group in rules["cite_all"])
    if "must_not" in rules:
        out["must_not"] = not any(s.lower() in low for s in rules["must_not"])
    if rules.get("not_found"):
        out["not_found"] = any(k in low for k in NOT_FOUND)
    if "min_fetches" in rules:
        out["min_fetches"] = len(fetched) >= rules["min_fetches"]
    out["passed"] = result["status"] == "ok" and all(out.values())
    return out


def semantic_setup(corpus: dict, dry_run: bool, name: str = "automotive") -> tuple:
    """Makale vektörlerini (önbellekten ya da API'den) ve sorgu gömücüyü hazırla."""
    if dry_run:  # ücretsiz sahte vektörler
        def fake(text):
            return [b / 255 for b in hashlib.sha256(text.encode()).digest()]
        return fake, {aid: fake(a["title"]) for aid, a in corpus.items()}, [0]
    used = [0]  # embedding girdi token'ı (maliyet için)
    vecs_file = corpus_file("article_vecs.json", name)
    if vecs_file.exists():
        vecs = json.loads(vecs_file.read_text(encoding="utf-8"))
    else:
        ids = list(corpus)
        texts = [corpus[i]["title"] + "\n\n" + corpus[i]["content"][:6000] for i in ids]
        out, tokens = nebius.embed(texts, EMBED_MODEL)
        used[0] += tokens
        vecs = dict(zip(ids, out))
        vecs_file.write_text(json.dumps(vecs), encoding="utf-8")

    @functools.lru_cache(maxsize=None)
    def query_vec(text: str) -> tuple:
        out, tokens = nebius.embed([QUERY_PREFIX + text], EMBED_MODEL)
        used[0] += tokens
        return tuple(out[0])
    return (lambda text: list(query_vec(text))), vecs, used


def run_one(model: str, sc: dict, corpus: dict, chat, out_path: Path, table: dict,
            tool_kwargs: dict | None = None, system_prompt: str = SYSTEM_PROMPT) -> dict:
    tools = NewsTools(corpus, sc.get("faults"), sc.get("content_patch"), **(tool_kwargs or {}))
    result = run_agent(chat, model, sc["prompt"], tools, system_prompt=system_prompt)
    p = sum(s["prompt_tokens"] for s in result["steps"])
    c = sum(s["completion_tokens"] for s in result["steps"])
    record = {"model": model, "scenario": sc["id"], **result, "tool_calls": tools.calls,
              "invalid_calls": sum(not t["valid"] for t in tools.calls), "tool_errors": sum(t["error"] for t in tools.calls), "prompt_tokens": p, "completion_tokens": c,
              "cost_usd": nebius.cost(model, p, c, table), "total_ms": sum(s["ms"] for s in result["steps"]),
              "checks": check(sc, result, tools)}
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return record


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", type=int, required=True)
    ap.add_argument("--models", nargs="+", default=PILOT_MODELS)
    ap.add_argument("--estimate", action="store_true", help="yalnız maliyet tahmini")
    ap.add_argument("--dry-run", action="store_true", help="sahte modelle, ücretsiz")
    ap.add_argument("--force", action="store_true", help="kayıtlı sonuçları yeniden koş")
    ap.add_argument("--scenarios", nargs="+", help="yalnız bu senaryo id'leri")
    ap.add_argument("--hint", action="store_true", help="sistem prompt'una 'korpus İngilizce' ipucu ekle")
    ap.add_argument("--search", choices=["keyword", "semantic"], default="keyword")
    ap.add_argument("--min-score", type=float, default=None, help="anlamsal arama eşiği")
    ap.add_argument("--dictionary", action="store_true", help="anahtar kelime sözlüğü kanalını aç")
    ap.add_argument("--corpus", default="automotive", help="automotive | emir | data/raw altındaki klasör adı (ör. emir2)")
    ap.add_argument("--scenarios-file", default=None, help="varsayılan eval/head_scenarios.json")
    ap.add_argument("--cluster", type=float, default=None, help="hikâye kümeleme eşiği (kosinüs)")
    ap.add_argument("--summaries", action="store_true", help="a: arama sonucunda haber özeti")
    ap.add_argument("--scope-rules", action="store_true", help="b: etiket-önce ve özet-önce kuralları")
    ap.add_argument("--user-keys", nargs="+", help="d: kullanıcının seçtiği sözlük anahtarları, ör. konu:ev")
    ap.add_argument("--read-budget", type=int, default=None, help="c: tur başına en fazla tam metin")
    ap.add_argument("--page-size", type=int, default=10, help="search_news sayfa boyu")
    ap.add_argument("--tool-retries", type=int, default=2, help="0 = yeniden denemeyi modele bırak (eski koşularla kıyas)")
    args = ap.parse_args()

    scen_file = Path(args.scenarios_file) if args.scenarios_file else SCENARIOS
    scenarios = [s for s in json.loads(scen_file.read_text(encoding="utf-8"))["scenarios"] if s["stage"] == args.stage and (not args.scenarios or s["id"] in args.scenarios)]
    table = nebius.prices()
    est = {m: sum(estimate(m, s["id"], table) for s in scenarios) for m in args.models}
    print(f"stage {args.stage}: {len(scenarios)} senaryo × {len(args.models)} model")
    for m, v in est.items():
        print(f"  tahmini üst sınır {v:6.3f} $  {m}")
    print(f"  TOPLAM ≈ {sum(est.values()):.2f} $")
    if args.estimate:
        return

    if args.dry_run:
        chat, out_dir = mock_chat, OUT_DIR / "dry_run"
    else:
        nebius.load_env()
        chat, out_dir = nebius.chat, OUT_DIR / f"stage{args.stage}"
    variant = (("_hint" if args.hint else "") + ("_semantic" if args.search == "semantic" else "")
               + (f"_p{args.page_size}" if args.page_size != 10 else "")
               + (f"_t{args.min_score}" if args.min_score is not None else "") + ("_dict" if args.dictionary else "") + ("_sum" if args.summaries else "") + ("_scope" if args.scope_rules else "") + (f"_budget{args.read_budget}" if args.read_budget is not None else "") + ("_user" if args.user_keys else "") + (f"_{args.corpus}" if args.corpus != "automotive" else "") + (f"_c{args.cluster}" if args.cluster is not None else ""))
    out_dir = out_dir.with_name(out_dir.name + variant)
    corpus = load_corpus(args.corpus)
    system_prompt = SYSTEM_PROMPT + date_note() + (HINT if args.hint else "")
    tool_kwargs, embed_used = {"retries": args.tool_retries, "page_size": args.page_size, "min_score": args.min_score}, [0]
    if args.dictionary:
        tool_kwargs["dictionary"] = KeywordDict.load(corpus_file("keyword_dict.json", args.corpus))
    if args.search == "semantic":
        embedder, vecs, embed_used = semantic_setup(corpus, args.dry_run, args.corpus)
        tool_kwargs |= {"query_embedder": embedder, "article_vecs": vecs}
    if args.summaries:
        tool_kwargs["summaries"] = json.loads(corpus_file("article_summaries.json", args.corpus).read_text(encoding="utf-8"))
    if args.cluster is not None:
        tool_kwargs["clusters"] = cluster(tool_kwargs["article_vecs"], args.cluster)
    if args.read_budget is not None:
        tool_kwargs["read_budget"] = args.read_budget
    if args.user_keys:
        tool_kwargs["user_keys"] = args.user_keys
        tool_kwargs.setdefault("dictionary", KeywordDict.load())
        system_prompt += USER_KEYS_NOTE.format(", ".join(args.user_keys))
    if args.scope_rules:
        system_prompt += SCOPE_RULES

    def run_model(model: str) -> list[dict]:
        records = []
        for sc in scenarios:
            path = out_dir / f"{model.replace('/', '_')}__{sc['id']}.json"
            if path.exists() and not args.force:
                records.append(json.loads(path.read_text(encoding="utf-8")))
            else:
                records.append(run_one(model, sc, corpus, chat, path, table, tool_kwargs, system_prompt))
        return records

    with ThreadPoolExecutor(max_workers=len(args.models)) as pool:
        all_records = [r for rs in pool.map(run_model, args.models) for r in rs]

    print(f"\n{'model':<38} {'senaryo':<30} {'durum':<10} geçti  adım  geçersiz/tool-hata  token(g/ç)      $       s")
    for r in all_records:
        print(f"{r['model'][:37]:<38} {r['scenario'][:29]:<30} {r['status']:<10} {'✓' if r['checks']['passed'] else '✗':^5} "
              f"{len(r['steps']):>4} {r['invalid_calls']:>4}/{r.get('tool_errors', '-'):<13}  {r['prompt_tokens']:>7}/{r['completion_tokens']:<6} "
              f"{r['cost_usd']:7.4f} {r['total_ms'] / 1000:6.1f}")
    label = "sahte (ücret yok)" if args.dry_run else "gerçek toplam"
    embed_cost = 0.0 if args.dry_run else embed_used[0] * table[EMBED_MODEL][0]
    print(f"\n{label}: {sum(r['cost_usd'] for r in all_records) + embed_cost:.4f} $"
          f" (embedding {embed_used[0]} token)  -> {out_dir}")


if __name__ == "__main__":
    main()
