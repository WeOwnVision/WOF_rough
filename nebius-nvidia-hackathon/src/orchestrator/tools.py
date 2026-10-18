"""Baş model testi için haber tool'ları (yerel Automotive korpusu üzerinde, ücretsiz).

Etiketler altın setten gelir: üst akıştaki sınıflandırıcının çıktısını taklit eder.
Uç durumlar senaryo bazında enjekte edilir: tool hatası (`faults`) ve içerik ekleme (`content_patch`).
Geçici hatalar (timeout) tool katmanında yeniden denenir; model yalnız son sonucu görür.
"""
import hashlib
import html
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUMMARIES_FILE = ROOT / "data" / "processed" / "article_summaries.json"  # scripts/hazirlik/build_summaries.py
RAW_DIR = ROOT / "data" / "raw"  # toplayıcı çıktıları (git dışında)
EMIR_RAW = RAW_DIR / "emir" / "emir_sample.json"  # Emir'in sorgu tabanlı toplayıcısı, eski biçim
# metin alanına yazılmış hata/bot/çerez sayfaları (Veri sorunları v2, E1)
BAD_TEXT = re.compile(r"metni yüksek güvenlik|Prove your humanity|not a robot|captcha|cloudflare|access denied|"
                      r"subscribe to continue|sign in to|cookie", re.I)

from src.orchestrator.automotive_gold import RAW, labels_of, load_gold  # noqa: E402
from src.orchestrator.dictionary import normalize  # noqa: E402  (katlama: Türkçe/İngilizce)
from src.orchestrator.ingest import clean_text  # noqa: E402

TOOL_SCHEMAS = [
    {"type": "function", "function": {
        "name": "search_news",
        "description": "Search the news corpus. Returns the total match count and id, title, source, date, labels and a short "
                       "snippet for a page of matching articles (best first for text queries); use offset to page. Empty query with no filters lists everything.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string", "description": "keywords; all must appear in title or text (case-insensitive)"},
            "tur": {"type": "string", "description": "article type label: lansman-duyuru, inceleme-rehber, pazar-finans, duzenleme-hukuk, olay-kriz, gorus-analiz, sponsorlu, eglence-yasam, gelisme-haber"},
            "konu": {"type": "string", "description": "topic label, e.g. ev, hibrit, konvansiyonel, performans-ozel, bakim-aksesuar, otonom-asistan, other"},
            "offset": {"type": "integer", "description": "number of results to skip (default 0)"},
        }},
    }},
    {"type": "function", "function": {
        "name": "get_article",
        "description": "Fetch the full text of one article by id.",
        "parameters": {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]},
    }},
]


def corpus_file(base: str, corpus: str = "automotive") -> Path:
    """Korpusa özel ara ürün yolu: automotive için eski adlar korunur (article_vecs.json), diğerlerine _<ad> eklenir."""
    p = ROOT / "data" / "processed" / base
    return p if corpus == "automotive" else p.with_name(f"{p.stem}_{corpus}{p.suffix}")


def load_emir_corpus() -> dict[str, dict]:
    """Emir verisi: bozuk/kısa metinler elenir, etiket yok (teknoloji taksonomisi henüz tanımlanmadı)."""
    corpus = {}
    for i, art in enumerate(json.loads(EMIR_RAW.read_text(encoding="utf-8"))):
        text = art.get("extracted_full_text") or ""
        if len(text) < 300 or BAD_TEXT.search(text[:500]):
            continue
        text = clean_text(art["title"], text)  # site menüsü/yorumlar (ingest.py); özet ve vektörler buna göre yeniden üretilmeli
        corpus[f"e{i:03d}"] = {"title": html.unescape(art["title"]).strip(), "source": art.get("source_name"),
                               "url": art.get("source_url"), "date": art.get("published_date") or None,
                               "tur": None, "konu": None, "content": text}
    return corpus


def load_feed_corpus(folder: Path) -> dict[str, dict]:
    """Ortak çıktı biçimindeki toplayıcı verisi (docs/entegrasyon.md §3): klasördeki her JSON bir haber listesi.

    id toplayıcının id'sinden türer (n + ilk 6 hane): kısa olduğu için atıfta ucuz, kararlı olduğu için klasöre yeni
    dosya eklenince özet/vektör önbellekleri bozulmaz. Aynı url birden çok dosyada varsa bir kez alınır.
    """
    corpus, seen = {}, set()
    for path in sorted(folder.glob("*.json")):
        for art in json.loads(path.read_text(encoding="utf-8")):
            text = art.get("content") or ""
            if art.get("content_status") != "ok" or len(text) < 300 or BAD_TEXT.search(text[:500]):
                continue
            if art["url"] in seen:
                continue
            seen.add(art["url"])
            key = art.get("id") or hashlib.md5(art["url"].encode()).hexdigest()
            n = 6
            while f"n{key[:n]}" in corpus:  # önek çakışması: id'yi uzat
                n += 2
            corpus[f"n{key[:n]}"] = {"title": html.unescape(art["title"]).strip(), "source": art.get("source"),
                                     "url": art["url"], "date": art.get("published_at") or None,
                                     "tur": None, "konu": None, "content": clean_text(art["title"], text)}
    return corpus


def load_corpus(name: str = "automotive") -> dict[str, dict]:
    if name == "emir":
        return load_emir_corpus()
    if (RAW_DIR / name).is_dir():  # ör. "emir2" → data/raw/emir2/*.json
        return load_feed_corpus(RAW_DIR / name)
    gold = load_gold()
    corpus = {}
    for i, art in enumerate(json.loads(RAW.read_text(encoding="utf-8"))):
        title = html.unescape(art["title"]).strip()
        tur, konu = gold.get(title, (None, None))
        corpus[f"a{i:02d}"] = {"title": title, "source": art["source"], "date": art["published_date"],
                               "tur": tur, "konu": konu, "content": art["content"]}
    return corpus


def cosine(a: list[float], b: list[float]) -> float:
    return math.sumprod(a, b) / (math.sqrt(math.sumprod(a, a)) * math.sqrt(math.sumprod(b, b)) or 1.0)


def unit(v: list[float]) -> list[float]:
    n = math.sqrt(math.sumprod(v, v)) or 1.0
    return [x / n for x in v]


class SearchIndex:
    """Korpus başına bir kez hesaplanan arama verisi: birim vektörler ve kelime kümeleri.

    Assistant bütün oturumlara aynı nesneyi verir. Önceden her aramada makale vektörlerinin normu, her oturumun ilk
    aramasında da bütün korpusun kelime kümeleri yeniden hesaplanıyordu (1026 haberde arama başına ~0,8 s, oturumun
    ilk aramasında ~2,3 s; şimdi ~0,1 s).
    """

    def __init__(self, corpus: dict[str, dict], article_vecs: dict[str, list[float]] | None = None):
        self.tokens = {aid: set(normalize(a["title"] + " " + a["content"]).split()) for aid, a in corpus.items()}
        self.unit_vecs = {aid: unit(v) for aid, v in article_vecs.items()} if article_vecs else None


class NewsTools:
    """Bir senaryo koşusu boyunca durum tutar (hata sayaçları, çağrı kaydı)."""

    def __init__(self, corpus: dict[str, dict], faults: dict | None = None, content_patch: dict | None = None,
                 retries: int = 2, query_embedder=None, article_vecs: dict[str, list[float]] | None = None,
                 page_size: int = 10, min_score: float | None = None, dictionary=None,
                 user_keys: list[str] | None = None, summaries: dict[str, str] | None = None,
                 read_budget: int | None = None, clusters: dict[str, int] | None = None,
                 index: SearchIndex | None = None):
        # clusters: haber -> hikâye kümesi; arama sonucunda her hikâyeden tek temsilci gösterilir
        self.clusters = clusters
        # summaries: arama sonucunda kısa alıntı yerine özet; read_budget: tur başına en fazla tam metin sayısı
        self.summaries, self.read_budget, self.reads_this_turn = summaries, read_budget, 0
        # sözlük kanalı: Türkçe/İngilizce terim -> haber (dictionary.py); user_keys: kullanıcının seçtiği ilgi alanları
        self.dictionary, self.user_keys = dictionary, user_keys
        self.min_score = min_score  # anlamsal aramada eşik altı sonuçlar gizlenir ("sonuç yok" sinyali)
        self.page_size = page_size  # sayfa başına sonuç; anlamsal aramada küçük tutmak token'ı düşürür
        # anlamsal arama: query_embedder(sorgu) -> vektör; yoksa anahtar kelime araması
        self.query_embedder, self.article_vecs = query_embedder, article_vecs
        self.retries = retries  # geçici hatada ek deneme sayısı; 0 = yeniden denemeyi modele bırak
        self.corpus = {k: dict(v) for k, v in corpus.items()}
        for aid, extra in (content_patch or {}).items():
            self.corpus[aid]["content"] += "\n\n" + extra
        self.faults = {aid: n for aid, n in (faults or {}).get("get_article", {}).items()}  # id -> kaç kez hata
        self.calls: list[dict] = []
        # index verilirse paylaşılır (Assistant); içeriği self.corpus ile aynı olmalı, yani content_patch ile birlikte verilmez
        self.index = index or SearchIndex(self.corpus, article_vecs)

    def search_news(self, query: str = "", tur: str | None = None, konu: str | None = None, offset: int = 0) -> dict:
        semantic = bool(query.strip()) and self.query_embedder is not None and self.index.unit_vecs is not None
        qvec = unit(self.query_embedder(query)) if semantic else None
        words = normalize(query).split()
        # K7: ilgi alanları haber eklemez, yalnız sıralamada öne alır (dictionary.py)
        matched, dict_hits = self.dictionary.match(query) if self.dictionary and query.strip() else ([], {})
        interest = set()
        for key in self.user_keys or []:
            interest |= (self.dictionary.entries.get(key, {}).get("articles", set()) if self.dictionary else set())
        hits = []
        for aid, a in self.corpus.items():
            if (tur and tur not in labels_of(a["tur"])) or (konu and konu not in labels_of(a["konu"])):
                continue
            hit = {"id": aid, "title": a["title"], "source": a["source"], "date": a["date"],
                   "tur": a["tur"], "konu": a["konu"]}
            if self.summaries and aid in self.summaries:
                hit["summary"] = self.summaries[aid]
            else:
                hit["snippet"] = a["content"][:200]
            # kelime sınırlı: "ev" artık "every", "ai" artık "said" içinde eşleşmez (alt ajan bulgusu)
            toks = self.index.tokens[aid]
            keyword_match = (bool(words) and all(w in toks or w + "s" in toks for w in words)) or aid in dict_hits
            if aid in dict_hits:
                hit["keyword_matches"] = dict_hits[aid]
            if semantic:
                hit["score"] = round(math.sumprod(qvec, self.index.unit_vecs[aid]), 3)
                # eşik altı ama anahtar kelimeyle eşleşen haber yine döner (birleşim); hiçbiri yoksa "sonuç yok"
                if self.min_score is not None and hit["score"] < self.min_score and not keyword_match:
                    continue
            elif words and not keyword_match:
                continue
            hits.append(hit)
        hits = self._rank(hits, interest)
        if self.clusters:  # aynı hikâyenin kopyalarını tek sonuçta topla
            members: dict[int, list[str]] = {}
            for aid, cid in self.clusters.items():
                members.setdefault(cid, []).append(aid)
            seen, grouped = set(), []
            for h in hits:
                cid = self.clusters.get(h["id"])
                if cid in seen:
                    continue
                seen.add(cid)
                others = [a for a in members.get(cid, []) if a != h["id"]]
                if others:  # uzun id listesi token şişiriyordu: sayı + ilk 3 id
                    h["same_story_count"] = len(others)
                    h["same_story_ids"] = others[:3]
                grouped.append(h)
            hits = grouped
        out = {"count": len(hits), "offset": offset, "results": hits[offset:offset + self.page_size]}
        if matched:
            out["matched_keywords"] = matched
        return out

    @staticmethod
    def _rank(hits: list[dict], interest: set[str], k: int = 60) -> list[dict]:
        """RRF: anlamsal skor sırası + sözlük/anahtar kelime sırası + ilgi alanı; tek bir kanal tek başına öne geçemez."""
        orders = [sorted(hits, key=lambda h: -h.get("score", 0)) if any("score" in h for h in hits) else hits,
                  sorted(hits, key=lambda h: -h.get("keyword_matches", 0))]
        if interest:
            orders.append(sorted(hits, key=lambda h: h["id"] not in interest))
        rrf = {h["id"]: 0.0 for h in hits}
        for order in orders:
            for rank, h in enumerate(order):
                rrf[h["id"]] += 1 / (k + rank)
        return sorted(hits, key=lambda h: -rrf[h["id"]])

    def new_turn(self) -> None:
        self.reads_this_turn = 0

    def get_article(self, id: str) -> dict:
        if id not in self.corpus:
            return {"error": f"unknown article id: {id}"}
        if self.read_budget is not None and self.reads_this_turn >= self.read_budget:
            return {"error": f"read budget of {self.read_budget} full articles per answer reached; "
                             "answer with what you have"}
        if self.faults.get(id, 0) > 0:
            self.faults[id] -= 1
            return {"error": "upstream timeout, please retry", "retryable": True}
        self.reads_this_turn += 1
        a = self.corpus[id]
        return {"id": id, "title": a["title"], "source": a["source"], "date": a["date"], "content": a["content"]}

    def call(self, name: str, raw_args: str) -> tuple[str, bool]:
        """Tool'u çalıştır. Dönüş: (JSON metin, geçerli_çağrı_mı)."""
        try:
            args = json.loads(raw_args or "{}")
            fn = {"search_news": self.search_news, "get_article": self.get_article}[name]
            result, ok, attempts = fn(**args), True, 1
            while result.get("retryable") and attempts <= self.retries:
                result, attempts = fn(**args), attempts + 1
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            result, ok, attempts = {"error": f"invalid tool call: {type(e).__name__}: {e}"}, False, 1
        # valid: model geçerli çağrı yaptı mı; error: tool hata döndü mü (enjekte edilen hatalar dahil)
        seen = [r["id"] for r in result.get("results", [])]  # arama sonucunda modelin gördüğü haberler
        self.calls.append({"name": name, "args": raw_args, "valid": ok, "error": "error" in result, "attempts": attempts,
                           **({"seen": seen} if seen else {})})
        return json.dumps(result, ensure_ascii=False), ok
