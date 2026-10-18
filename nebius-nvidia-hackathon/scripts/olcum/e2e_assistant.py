"""Uçtan uca son test: ürünün kullanacağı Assistant.ask arayüzü, gerçek modeller, doğrulayıcı açık.

Otomotiv: eval/chat_scenarios.json'daki c1 ve c2 (çok turlu). Emir: eval/emir_scenarios.json (tek tur).
c3 (enjekte hata + gömülü talimat) burada yok: Assistant'ın içine hata enjekte edilmez (eval_chat.py ölçtü).
Profil: --profil ile eval/profile_scenarios.json (emir2 korpusu; kullanıcıya özel bağlam, kişiye özel özet).
Kullanım:
    .venv\\Scripts\\python.exe scripts\\olcum\\e2e_assistant.py        # GERÇEK çağrı (kredi harcar, ~5 sent)
    .venv\\Scripts\\python.exe scripts\\olcum\\e2e_assistant.py --profil   # yalnız profil senaryoları (~5–10 sent)
    .venv\\Scripts\\python.exe scripts\\olcum\\e2e_assistant.py c1_takip    # yalnız adı verilen oturumlar
Çıktı: data/processed/e2e_assistant[_profil].json
"""
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from src.orchestrator.assistant import Assistant  # noqa: E402

NOT_FOUND = ["bulunamadı", "bulamadım", "yer almıyor", "bulunmuyor", "yok", "içermiyor", "not found", "no information"]
OUT = ROOT / "data" / "processed" / "e2e_assistant.json"


def passed(checks: dict, answer: str) -> bool:
    low = (answer or "").lower()
    ok = all(any(alt.lower() in low for alt in group) for group in checks.get("cite_all", []))
    ok &= not any(s.lower() in low for s in checks.get("must_not", []))
    if checks.get("not_found"):
        ok &= any(k in low for k in NOT_FOUND)
    return ok


def run_turns(asst: Assistant, session: str, turns: list[dict]) -> list[dict]:
    out = []
    for turn in turns:
        t0, marks, events = time.perf_counter(), {}, []

        def on_event(e, marks=marks, events=events, t0=t0):
            events.append(e["type"])
            marks.setdefault(e["type"], round(time.perf_counter() - t0, 1))
        profile = turn.get("profile")
        if isinstance(profile, str):  # dosya yolu (ör. profiller/ai-finans.json)
            profile = json.loads((ROOT / profile).read_text(encoding="utf-8"))
        if turn.get("ozet"):
            r = asst.ozet(session, on_event=on_event, profile=profile)
        else:
            r = asst.ask(session, turn["user"], on_event=on_event, profile=profile)
        out.append({"session": session, "user": turn.get("user") or "(özet)", "status": r["status"], "model": r.get("model"),
                    "badge": r.get("badge"), "claims": r.get("claims"), "answer": r.get("answer"),
                    "sources": r.get("sources"), "passed": passed(turn.get("checks", {}), r.get("answer")),
                    "first_text_s": marks.get("delta"), "answer_s": marks.get("answer"), "badge_s": marks.get("badge"),
                    "statuses": events.count("status"), "resets": events.count("reset"), "cost_usd": r.get("cost_usd")})
    return out


def profile_jobs() -> list[tuple]:
    scen = json.loads((ROOT / "eval" / "profile_scenarios.json").read_text(encoding="utf-8"))["scenarios"]
    asst = Assistant("emir2")
    return [(asst, s["id"], [{"user": s.get("prompt"), "checks": s["checks"], "profile": s.get("profile"),
                              "ozet": s.get("ozet", False)}]) for s in scen]


def main() -> None:
    args = sys.argv[1:]
    if "--profil" in args:
        args.remove("--profil")
        return report(run(profile_jobs(), args), OUT.with_name("e2e_assistant_profil.json"))
    chat = [c for c in json.loads((ROOT / "eval" / "chat_scenarios.json").read_text(encoding="utf-8"))["conversations"]
            if c["id"] in ("c1_takip", "c2_duzeltme")]
    emir = json.loads((ROOT / "eval" / "emir_scenarios.json").read_text(encoding="utf-8"))["scenarios"]
    auto_asst, emir_asst = Assistant("automotive"), Assistant("emir")
    jobs = [(auto_asst, c["id"], c["turns"]) for c in chat] + \
           [(emir_asst, s["id"], [{"user": s["prompt"], "checks": s["checks"]}]) for s in emir]
    report(run(jobs, args), OUT)


def run(jobs: list[tuple], only: list[str]) -> list[dict]:
    jobs = [j for j in jobs if not only or j[1] in only]  # ör. c1_takip c2_duzeltme: yalnız bu oturumlar
    if not jobs:
        sys.exit(f"eşleşen oturum yok: {only}")
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        return [r for rs in pool.map(lambda j: run_turns(*j), jobs) for r in rs]


def report(results: list[dict], out: Path) -> None:
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{'oturum':<26} {'durum':<6} geçti rozet          ilk-metin cevap rozet-s  model")
    for r in results:
        print(f"{r['session'][:25]:<26} {r['status']:<6} {'✓' if r['passed'] else '✗':^5} {str(r['badge']):<14} "
              f"{str(r['first_text_s']):>8} {str(r['answer_s']):>6} {str(r['badge_s']):>7}  {(r['model'] or '-').split('/')[-1]}")
    ok = sum(r["passed"] for r in results)
    cost = sum(r["cost_usd"] or 0 for r in results)
    print(f"\ngeçti {ok}/{len(results)} | maliyet {cost:.4f} $ | rozetler: {[r['badge'] for r in results]} -> {out}")


if __name__ == "__main__":
    main()
