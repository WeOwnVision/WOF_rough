"""İkinci etiketleyici: farklı aileden bir LLM gümüş seti görmeden etiketler; uyum ölçülür, uzlaşı seti çıkar.

Kullanım:
    .venv\\Scripts\\python.exe scripts\\subtag\\second_annotator.py label --estimate
    .venv\\Scripts\\python.exe scripts\\subtag\\second_annotator.py label            # GERÇEK çağrı (kredi harcar)
    .venv\\Scripts\\python.exe scripts\\subtag\\second_annotator.py compare          # uyum + uzlaşı seti (ücretsiz)
Çıktı: data/processed/annotations_<model>.json, data/processed/gold_v2_consensus.json
Uzlaşı kuralı: tür aynı VE konu kesişimi boş değil → "uzlasi" (konu = kesişim, bayrak = kesişim); değilse "anlasmazlik".
Bu set insan altın seti değildir: iki bağımsız modelin uzlaşısı + Claude hakemliği (docs/taksonomi.md).
"""
import argparse
import html
import json
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator import nebius  # noqa: E402
from src.orchestrator.taxonomy import prompt_for  # noqa: E402
from src.orchestrator.tools import corpus_file, load_corpus  # noqa: E402

SILVER = ROOT / "data" / "processed" / "gold_v2_silver.json"
CONSENSUS = ROOT / "data" / "processed" / "gold_v2_consensus.json"
SAMPLE = ROOT / "data" / "raw" / "sampleNews"
FILES = {"f": "finance.json", "p": "politics.json", "t": "technology.json"}


def load_texts() -> dict[str, dict]:
    """id -> kategori, kaynak, başlık ve modelin göreceği kısa metin (Emir'de özet + baş, diğerlerinde metnin başı)."""
    silver = json.loads(SILVER.read_text(encoding="utf-8"))
    emir = load_corpus("emir")
    summaries = json.loads(corpus_file("article_summaries.json", "emir").read_text(encoding="utf-8"))
    raw = {k: json.loads((SAMPLE / f).read_text(encoding="utf-8")) for k, f in FILES.items()}
    out = {}
    for x in silver:
        aid = x["id"]
        if aid.startswith("e"):
            a = emir[aid]
            text, source = summaries.get(aid, "") + "\n\n" + a["content"][:600], a["source"]
        else:
            art = raw[aid[0]][int(aid[1:])]
            text, source = html.unescape(art.get("content", ""))[:900], art["source"]
        out[aid] = {"category": x["category"], "source": source, "title": x["title"], "text": text}
    return out


def label_one(model: str, item: dict) -> tuple[dict, dict]:
    system, schema = prompt_for(item["category"])
    user = f"Category: {item['category']}\nSource: {item['source']}\nTitle: {item['title']}\n\n{item['text']}"
    choice, usage, _ = nebius.chat(model, [{"role": "system", "content": system}, {"role": "user", "content": user}],
                                   None, max_tokens=3000,
                                   response_format={"type": "json_schema", "json_schema": {"name": "label", "schema": schema}})
    return json.loads(choice["message"]["content"]), usage


def out_file(model: str, tag: str = "") -> Path:
    return ROOT / "data" / "processed" / f"annotations_{model.split('/')[-1]}{'_' + tag if tag else ''}.json"


def label(model: str, estimate_only: bool, disputed_only: bool = False, tag: str = "") -> None:
    items, table = load_texts(), nebius.prices()
    if disputed_only:  # üçüncü etiketleyici: yalnız ilk ikisinin anlaşamadığı haberler
        disputed = {r['id'] for r in json.loads(CONSENSUS.read_text(encoding='utf-8')) if r['status'] != 'uzlasi'}
        items = {k: v for k, v in items.items() if k in disputed}
    est = sum(nebius.cost(model, (len(prompt_for(x["category"])[0]) + len(x["text"]) + len(x["title"])) // 4 + 50, 600, table)
              for x in items.values())
    print(f"{len(items)} haber, {model}, tahmini üst sınır ≈ {est:.3f} $")
    if estimate_only:
        return
    nebius.load_env()
    with ThreadPoolExecutor(max_workers=8) as pool:
        res = dict(zip(items, pool.map(lambda x: label_one(model, x), items.values())))
    spent = sum(nebius.cost(model, u.get("prompt_tokens", 0), u.get("completion_tokens", 0), table) for _, u in res.values())
    out_file(model, tag).write_text(json.dumps({k: v for k, (v, _) in res.items()}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"maliyet {spent:.4f} $ -> {out_file(model, tag)}")


def kappa(a: list[str], b: list[str]) -> float:
    n = len(a)
    po = sum(x == y for x, y in zip(a, b)) / n
    ca, cb = Counter(a), Counter(b)
    pe = sum(ca[k] * cb[k] for k in set(a) | set(b)) / (n * n)
    return (po - pe) / (1 - pe) if pe < 1 else 1.0


def compare(model: str) -> None:
    silver = {x["id"]: x for x in json.loads(SILVER.read_text(encoding="utf-8"))}
    other = json.loads(out_file(model).read_text(encoding="utf-8"))
    ids = [i for i in silver if i in other]
    tur_a, tur_b = [silver[i]["tur"] for i in ids], [other[i]["tur"] for i in ids]
    jac = [len(set(silver[i]["konu"]) & set(other[i]["konu"])) / len(set(silver[i]["konu"]) | set(other[i]["konu"])) for i in ids]
    flag_ok = sum(set(silver[i]["flags"]) == set(other[i]["flags"]) for i in ids)
    out, disagree = [], []
    for i in ids:
        s, o = silver[i], other[i]
        konu = [k for k in s["konu"] if k in o["konu"]]
        ok = s["tur"] == o["tur"] and bool(konu)
        rec = {"id": i, "category": s["category"], "title": s["title"], "status": "uzlasi" if ok else "anlasmazlik",
               "tur": s["tur"] if ok else None, "konu": konu if ok else None,
               "flags": [f for f in s["flags"] if f in o["flags"]] if ok else None,
               "silver": {k: s[k] for k in ("tur", "konu", "flags")}, "second": o, "second_model": model}
        out.append(rec)
        if not ok:
            disagree.append(rec)
    CONSENSUS.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    n = len(ids)
    print(f"{n} haber | tür uyumu {sum(x == y for x, y in zip(tur_a, tur_b)) / n:.0%} (kappa {kappa(tur_a, tur_b):.2f}) | "
          f"konu Jaccard ort. {sum(jac) / n:.2f} | bayrak birebir {flag_ok}/{n}")
    print(f"uzlaşı {n - len(disagree)}/{n}, anlaşmazlık {len(disagree)} -> {CONSENSUS}")
    print("tür karışıklıkları:", Counter((x, y) for x, y in zip(tur_a, tur_b) if x != y).most_common(8))


def vote(third: str, second: str = "openai/gpt-oss-120b", tag: str = "") -> None:
    """Anlaşmazlıklarda 3 etiketleyici (Claude gümüş, ikinci, üçüncü) çoğunluk oyu; Claude hakemliğinin yerine geçer.

    Tür: en az 2 oy. Konu/bayrak: etiket başına en az 2 oy (konu boş kalırsa tür çoğunluğundakilerin kesişimi).
    Üçü de farklı türse "cozulemedi" (Claude hakemliği kalır, işaretli).
    """
    recs = json.loads(CONSENSUS.read_text(encoding="utf-8"))
    third_ann = json.loads(out_file(third, tag).read_text(encoding="utf-8"))
    second_ann = json.loads(out_file(second, tag).read_text(encoding="utf-8")) if tag else None  # yeni tanımlarla tekrar
    final = json.loads((ROOT / "data" / "processed" / "gold_v2.json").read_text(encoding="utf-8"))
    by_id = {x["id"]: x for x in final}
    stats = Counter()
    for r in recs:
        if r["status"] == "uzlasi" or r["id"] not in third_ann:
            continue
        anns = [r["silver"], second_ann[r["id"]] if second_ann else r["second"], third_ann[r["id"]]]
        tur, n = Counter(a["tur"] for a in anns).most_common(1)[0]
        x = by_id[r["id"]]
        if n < 2:
            x.update({"status": "cozulemedi"})
            stats["cozulemedi"] += 1
            continue
        konu = [k for k, c in Counter(k for a in anns for k in set(a["konu"])).items() if c >= 2]
        if not konu:
            agree = [set(a["konu"]) for a in anns if a["tur"] == tur]
            konu = sorted(set.intersection(*agree)) or sorted(agree[0])
        flags = [f for f, c in Counter(f for a in anns for f in set(a["flags"])).items() if c >= 2]
        stats["claude_hakemi_ile_ayni" if (tur == r["tur"] and set(konu) == set(r["konu"] or [])) else "degisti"] += 1
        x.update({"tur": tur, "konu": konu, "flags": flags, "status": "cogunluk",
                  "note": f"3 etiketleyici: Claude/{second.split('/')[-1]}/{third.split('/')[-1]} → tür {n}/3"})
        x.pop("guven", None)
    (ROOT / "data" / "processed" / "gold_v2.json").write_text(json.dumps(final, ensure_ascii=False, indent=2), encoding="utf-8")
    print(dict(stats), "| durum:", dict(Counter(x["status"] for x in final)))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["label", "compare", "vote"])
    ap.add_argument("--model", default="openai/gpt-oss-120b")
    ap.add_argument("--estimate", action="store_true")
    ap.add_argument("--disputed-only", action="store_true", help="yalnız anlaşmazlıkları etiketle (üçüncü etiketleyici)")
    ap.add_argument("--tag", default="", help="çıktı dosyası eki (ör. tanım sürümü: v2)")
    ap.add_argument("--second", default="openai/gpt-oss-120b", help="vote: ikinci etiketleyici modeli")
    args = ap.parse_args()
    if args.cmd == "label":
        label(args.model, args.estimate, args.disputed_only, args.tag)
    elif args.cmd == "compare":
        compare(args.model)
    else:
        vote(args.model, args.second, args.tag)
