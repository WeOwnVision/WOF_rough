"""Ürün giriş noktası: Talha'nın sunucusu ve Ludi'nin arayüzü bunu çağırır (docs/entegrasyon.md).

    asst = Assistant("emir")
    asst.ask("oturum-1", "Anthropic bu hafta ne duyurdu?", interests=["konu:ev"], on_event=print)

ask() bir turu baştan sona yürütür: arama/okuma (baş model + yedek), akışlı cevap, kaynaklar, doğrulama rozeti.
Her adım on_event({"type": ...}) ile bildirilir; sunucu bunları SSE/WebSocket ile arayüze iletebilir.
Ölçümlerin dayandığı ayar (docs/model-eval-2026-10-10.md): V4-Flash ana, V4.1-Flash yedek, Nemotron-Super doğrulayıcı,
"korpus İngilizce" ipucu, eşikli (0,46) anlamsal + anahtar kelime + sözlük araması, 5'lik sayfa, özet-önce ve
etiket-önce kuralları, çağrı başına 45 s zaman aşımı.
"""
import functools
import json
import threading

from . import nebius
from .agent import DIGEST_QUESTION, HINT, SCOPE_RULES, SYSTEM_PROMPT, USER_KEYS_NOTE, date_note, profile_note, run_turn
from .dictionary import KeywordDict
from .tools import NewsTools, SearchIndex, corpus_file, load_corpus
from .verifier import VERIFIER_MODEL, sources_from_calls, verify

PRIMARY, BACKUP = "deepseek-ai/DeepSeek-V4-Flash-0731", "deepseek-ai/DeepSeek-V4.1-Flash"
EMBED_MODEL = "Qwen/Qwen3-Embedding-8B"
QUERY_PREFIX = "Instruct: Given a news search query, retrieve news articles relevant to the query\nQuery: "


class EventTools(NewsTools):
    """Tool çağrılarını arayüze "status" olayı olarak bildirir ("aranıyor…", "okunuyor…")."""

    def __init__(self, *args, emit=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.emit = emit or (lambda event: None)

    def call(self, name: str, raw_args: str) -> tuple[str, bool]:
        try:
            args = json.loads(raw_args or "{}")
        except json.JSONDecodeError:
            args = {}
        if name == "search_news":
            what = args.get("query") or ", ".join(f"{k}={v}" for k, v in args.items() if k in ("tur", "konu"))
            self.emit({"type": "status", "text": f"Aranıyor: {what or 'tüm haberler'}"})
        elif name == "get_article" and args.get("id") in self.corpus:
            self.emit({"type": "status", "text": f"Okunuyor: {self.corpus[args['id']]['title']}"})
        return super().call(name, raw_args)


class Assistant:
    """Bir korpus üzerinde çok oturumlu sohbet. Oturum durumu bellekte; kalıcılık sunucunun işi (Talha)."""

    def __init__(self, corpus: str = "automotive", models: tuple[str, ...] = (PRIMARY, BACKUP),
                 verifier: str | None = VERIFIER_MODEL, chat=None, embed=None, timeout: int = 45):
        """chat/embed verilmezse Nebius kullanılır (NEBIUS_API_KEY .env'de). Testte sahte fonksiyon verilebilir."""
        if chat is None or embed is None:
            nebius.load_env()
        self.corpus_name, self.models, self.verifier = corpus, list(models), verifier
        self._chat = chat or functools.partial(nebius.chat, stream=True, timeout=timeout)
        self._embed = embed or (lambda texts: nebius.embed(texts, EMBED_MODEL)[0])
        self.corpus = load_corpus(corpus)
        self.summaries = self._load_json("article_summaries.json")
        self.index = SearchIndex(self.corpus, self._load_json("article_vecs.json"))  # bir kez; oturumlar paylaşır
        dict_file = corpus_file("keyword_dict.json", corpus)
        self.dictionary = KeywordDict.load(dict_file) if dict_file.exists() else None
        self._query_vec = functools.lru_cache(maxsize=4096)(lambda text: tuple(self._embed([QUERY_PREFIX + text])[0]))
        self.sessions: dict[str, dict] = {}
        self._lock = threading.Lock()

    def _load_json(self, base: str) -> dict:
        path = corpus_file(base, self.corpus_name)
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}

    def _cost(self, usage: list[tuple[str, int, int]]) -> float | None:
        """Tur maliyeti (Nebius fiyat listesinden); fiyat bilinmeyen model (sahte testte) varsa None."""
        try:
            table = nebius.prices()
            return round(sum(nebius.cost(m, p, c, table) for m, p, c in usage), 6)
        except (KeyError, FileNotFoundError):
            return None

    def interests(self) -> list[dict]:
        """Arayüzdeki ilgi alanı seçenekleri: sözlükteki konu/tür anahtarları."""
        if not self.dictionary:
            return []
        return [{"key": k, "label": k.split(":", 1)[1], "articles": len(e["articles"])}
                for k, e in sorted(self.dictionary.entries.items()) if e["type"] == "topic"]

    def _session(self, session_id: str, emit, interests: list[str] | None) -> dict:
        with self._lock:
            s = self.sessions.get(session_id)
            if s is None:
                tools = EventTools(self.corpus, summaries=self.summaries or None, page_size=5,
                                   query_embedder=(lambda q: list(self._query_vec(q))) if self.index.unit_vecs else None,
                                   index=self.index, min_score=0.46, dictionary=self.dictionary)
                s = self.sessions[session_id] = {"tools": tools, "history": None}
        s["tools"].emit, s["tools"].user_keys = emit, interests or None
        return s

    def ask(self, session_id: str, message: str, interests: list[str] | None = None, on_event=None,
            profile: dict | None = None) -> dict:
        """Bir tur. Olaylar sırayla: status*, delta*, (reset), sources, answer, badge — ya da error.

        profile: kullanıcıya özel bağlam (agent.profile_note); verilirse sistem prompt'una eklenir, verilmezse eklenmez.
        Her çağrıda güncel profil gönderilir (kalıcılık sunucuda); oturumun önceki turları da yeni prompt'la sürer.
        """
        emit = on_event or (lambda event: None)
        s = self._session(session_id, emit, interests)
        tools, since = s["tools"], len(s["tools"].calls)

        def chat(model, messages, tool_schemas):
            buf = []

            def on_delta(text):
                buf.append(text)
                emit({"type": "delta", "text": text})
            try:
                choice, usage, ms = self._chat(model, messages, tool_schemas, on_delta=on_delta)
            except Exception as e:
                if buf:  # yarıda kalan akış: arayüz yazılanı silsin, yedek model baştan yazacak
                    emit({"type": "reset"})
                # her hata yedeğe geçişi tetiklesin (kopan bağlantı, bozuk akış…), yalnız HTTP/zaman aşımı değil
                raise e if isinstance(e, nebius.APIError) else nebius.APIError(f"{type(e).__name__}: {e}") from e
            if buf and choice["message"].get("tool_calls"):  # model tool çağırmadan önce metin yazdıysa
                emit({"type": "reset"})
            return choice, usage, ms

        system_prompt = SYSTEM_PROMPT + date_note() + HINT + SCOPE_RULES
        if interests:
            system_prompt += USER_KEYS_NOTE.format(", ".join(interests))
        system_prompt += profile_note(profile)
        # ilgi alanı/profil turdan tura değişebilir: geçmişteki sistem mesajı bu turdan önce güncellenir
        # (run_agent geçmiş varken system_prompt'u değil geçmişin ilk mesajını kullanır; sonradan güncellemek bir tur geç kalıyordu)
        if s["history"] and s["history"][0]["role"] == "system":
            s["history"][0] = {"role": "system", "content": system_prompt}
        result = run_turn(chat, self.models, message, tools, history=s["history"], system_prompt=system_prompt)
        if result["status"] != "ok":
            emit({"type": "error", "text": "Cevap üretilemedi.", "attempts": [
                {k: a[k] for k in ("model", "status", "error")} for a in result["attempts"]]})
            return {"status": result["status"], "answer": None}
        s["history"] = result["messages"]

        # bu turda görülenler + önceki turlardan cevapta atıf yapılanlar (geçmişten cevaplanan turlar da doğrulansın)
        session_sources = sources_from_calls(tools)
        cited = [aid for aid in session_sources if f"[{aid}]" in result["answer"]]
        sources = {**sources_from_calls(tools, since), **{aid: session_sources[aid] for aid in cited}}
        emit({"type": "sources", "items": [{"id": aid, "title": self.corpus[aid]["title"], "source": self.corpus[aid]["source"],
                                            "date": self.corpus[aid]["date"], "url": self.corpus[aid].get("url")}
                                           for aid in cited]})
        emit({"type": "answer", "text": result["answer"], "model": result["answered_by"]})

        usage = [(a["model"], s["prompt_tokens"], s["completion_tokens"]) for a in result["attempts"] for s in a["steps"]]
        badge = {"badge": "skipped", "claims": []}
        if self.verifier and sources:
            try:
                v = verify(self._chat, result["answer"], sources, self.verifier)
                usage.append((self.verifier, v["prompt_tokens"], v["completion_tokens"]))
                badge = {"badge": v["badge"], "claims": [c for c in v["claims"] if c.get("verdict") != "supported"]}
            except Exception as e:  # doğrulayıcı düşerse cevap yine geçerli; rozet "unavailable"
                badge = {"badge": "unavailable", "claims": [], "error": str(e)[:200]}
        emit({"type": "badge", **badge})
        return {"status": "ok", "answer": result["answer"], "model": result["answered_by"], "sources": cited,
                "cost_usd": self._cost(usage), **badge}

    def ozet(self, session_id: str, interests: list[str] | None = None, on_event=None, profile: dict | None = None) -> dict:
        """Kişiye özel haber özeti: profil ve ilgi alanlarıyla sabit bir soru (ask ile aynı olaylar ve dönüş)."""
        return self.ask(session_id, DIGEST_QUESTION, interests=interests, on_event=on_event, profile=profile)
