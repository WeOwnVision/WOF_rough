"""Buradan başla: terminalde haber asistanıyla konuş.

Kullanım (proje kökünden):
    .venv\\Scripts\\python.exe sohbet.py                                  # emir korpusu, sohbet
    .venv\\Scripts\\python.exe sohbet.py --corpus automotive               # başka korpus
    .venv\\Scripts\\python.exe sohbet.py -q "Anthropic bu hafta ne duyurdu?"   # tek soru sor, çık
    .venv\\Scripts\\python.exe sohbet.py --ilgi konu:ev                    # ilgi alanı (arama sırasında öne alınır)
    .venv\\Scripts\\python.exe sohbet.py --profil profiller/ai-finans.json     # kişiye özel bağlam (sistem prompt'una eklenir)

Sohbette /ozet yazarsan profil ve ilgi alanlarına göre kişiye özel haber özeti gelir.
Profil alanları (hepsi isteğe bağlı): ad, hakkinda, seviye (basit|orta|uzman), bicim (kisa|madde|ayrintili), odak.

Her soru gerçek modelleri çağırır (Nebius kredisi, soru başına ~1 sent). NEBIUS_API_KEY .env içinde olmalı.
Çıkmak için boş satır ya da Ctrl+C. Sunucu ve arayüz de aynı Assistant.ask çağrısını kullanır (docs/entegrasyon.md).
"""
import argparse
import json
import sys

from src.orchestrator.assistant import Assistant

BADGE = {
    "ok": "✓ Doğrulandı: cevaptaki iddiaların hepsi kaynaklarda var.",
    "unsupported": "⚠ Bazı iddialar kaynaklarda bulunamadı:",
    "contradicted": "✗ Kaynakla çelişen iddia var:",
    "skipped": "(Doğrulama yapılmadı: cevap haber kaynağına dayanmıyor.)",
    "unavailable": "(Doğrulayıcıya ulaşılamadı; cevap doğrulanmadı.)",
    "parse_error": "(Doğrulayıcının cevabı okunamadı; cevap doğrulanmadı.)",
}


class Printer:
    """Assistant olaylarını sohbet gibi yazdırır: durum satırları, akan cevap, kaynaklar, rozet."""

    def __init__(self):
        self.streaming = False

    def __call__(self, e: dict) -> None:
        kind = e["type"]
        if kind == "status":
            print(f"  … {e['text']}", flush=True)
        elif kind == "delta":
            if not self.streaming and not e["text"].strip():  # tool çağrısından önceki boşluk: cevap başlamadı
                return
            if not self.streaming:
                print("\nAsistan: ", end="")
                self.streaming = True
            print(e["text"], end="", flush=True)
        elif kind == "reset":  # model yarıda kaldı ya da arama yapmaya döndü: yazılanı yok say
            if self.streaming:
                print("\n  (yeniden yazılıyor)", flush=True)
            self.streaming = False
        elif kind == "sources":
            print("\n\nKaynaklar:")
            for s in e["items"]:
                date = f", {s['date'][:10]}" if s.get("date") else ""
                print(f"  [{s['id']}] {s['title']} — {s['source']}{date}")
                if s.get("url"):
                    print(f"         {s['url']}")
        elif kind == "badge":
            print("\n" + BADGE.get(e["badge"], e["badge"]))
            for c in e.get("claims", []):
                print(f"  - {c.get('claim')}")
        elif kind == "error":
            print(f"\nHata: {e['text']}")
            for a in e.get("attempts", []):
                print(f"  {a['model']}: {a['status']} {a.get('error') or ''}")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # Windows konsolunda ✓ ⚠ ✗
    ap = argparse.ArgumentParser(description="Haber asistanıyla terminalde konuş.")
    ap.add_argument("--corpus", default="emir", help="automotive | emir | data/raw altındaki klasör adı (ör. emir2)")
    ap.add_argument("-q", "--soru", help="tek soru sor ve çık")
    ap.add_argument("--ilgi", nargs="*", default=None, help="ilgi alanı anahtarları, ör. konu:ev")
    ap.add_argument("--profil", help="kullanıcı profili JSON dosyası (ör. profiller/ai-finans.json)")
    args = ap.parse_args()

    print(f"Korpus yükleniyor: {args.corpus} …", flush=True)
    asst = Assistant(args.corpus)
    profile = None
    if args.profil:
        with open(args.profil, encoding="utf-8") as f:
            profile = json.load(f)
    print(f"{len(asst.corpus)} haber hazır." + (f" Profil: {args.profil}." if profile else "")
          + " Soru yaz, kişiye özel özet için /ozet (çıkmak için boş satır).")
    session = "terminal"
    questions = [args.soru] if args.soru else None
    while True:
        if questions is not None:
            if not questions:
                break
            question = questions.pop(0)
            print(f"\nSen: {question}")
        else:
            try:
                question = input("\nSen: ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not question:
                break
        printer = Printer()
        if question.lower() == "/ozet":
            result = asst.ozet(session, interests=args.ilgi, on_event=printer, profile=profile)
        else:
            result = asst.ask(session, question, interests=args.ilgi, on_event=printer, profile=profile)
        if result.get("cost_usd") is not None:
            print(f"\n(maliyet: {result['cost_usd'] * 100:.2f} sent)")


if __name__ == "__main__":
    main()
