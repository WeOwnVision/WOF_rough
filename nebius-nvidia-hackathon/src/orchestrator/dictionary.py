"""Dinamik anahtar kelime sözlüğü: Türkçe/İngilizce terimden habere köprü.

Kurallar (Claude taslağı, Bircan'ın isteğiyle; değiştirilebilir). v3 — alt ajanın çökme raporundan sonra
(40 çöken senaryo: büyük I, önek yanlış alarmları, zincirleme birleşme, kısa adlar):
  K1  Kavramlar taksonomiden gelir: sınıflandırıcının konu/tür etiketleri TOPIC_SEEDS'teki TR/EN eş anlamlılarla
      sözlüğe tohum olur; haber listesi etiketlerden. (v1'de LLM konu çevirisi parçalı ve hatalıydı.)
  K2  Varlıklar LLM'den gelir: Nemotron-Nano her haberden yalnız özel isimleri çıkarır (marka, model, kurum, kişi)
      ve kullanıcının yazabileceği kısa biçimleri (VW, CR-V). Çeviri istenmez.
  K3  Kanonik anahtar katlanmış küçük harf. Anahtarlar birleştirilmez (v2'deki zincirleme birleşme "model y" ile
      bütün Tesla haberlerini getiriyordu); bir takma ad birden çok anahtara bağlanabilir.
  K4  Gürültü: genel kelimeler, sayılar/yıllar, şirket ekleri (corp, inc) takma ad olamaz; haberlerin yarısından
      fazlasında geçen varlık ayırt edici değildir.
  K4b Belirsiz takma ad: 3+ anahtara bağlanan takma ad hepsinden düşer (Emir verisinde "claude" 11 anahtara
      bağlanıp her sorguda 24 haberi eşiksiz getiriyordu; e3 13K → 68K token).
  K4c Yaygın anahtarın adı ("claude", "anthropic": haberlerin yarısından fazlası) başka anahtara takma ad olamaz.
  K5  Eşleşme: sorgu ve takma ad katlanır (I/İ→i, Türkçe harf→ASCII, aksan düşer; "sarj" = "şarj", "Intel" bozulmaz).
      Takma adın her kelimesi sorguda bir kelimeyle eşleşmeli: tam aynı ya da kök + Türkçe ek zinciri
      ("araç"+"larla"; "pazartesi" eşleşmez çünkü "tesi" ek değil), son ünsüz yumuşaması dahil ("destek"→"desteği").
      3 harften kısa takma adlar ("ev", "vw") yalnız sorguda BÜYÜK harfle ayrı kelime olarak yazılmışsa eşleşir
      ("EV haberleri" evet, "ev kredisi" hayır). Tek harfli kelime içeren takma ad ("model y") bitişik ve sıralı olmalı.
  K6  Sıralama: haber, eşleşen anahtar sayısına göre.
  K7  Kullanıcı bağlamı: seçilen ilgi alanları aramaya haber EKLEMEZ (v2'de "Ferrari" sorusuna EV haberleri
      dönüyordu); yalnız sıralamayı etkiler ve sistem prompt'unda modele bildirilir.
  K8  Dinamiklik: yeni haber geldikçe K1–K4 artımlı uygulanır.
"""
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DICT_FILE = ROOT / "data" / "processed" / "keyword_dict.json"
EXTRACT_MODEL = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B"
STOPLIST = {"car", "cars", "vehicle", "vehicles", "news", "new", "model", "models", "report", "company", "price",
            "araba", "arac", "otomobil", "haber", "yeni", "fiyat", "corp", "corporation", "inc", "ltd", "co",
            "general manager"}  # katlanmış biçimde
MAX_DF_RATIO = 0.5

# K1: taksonomi etiketi -> TR/EN eş anlamlılar (konu ve tür eksenleri)
TOPIC_SEEDS = {
    ("konu", "ev"): ["elektrikli", "elektrikli araç", "elektrikli otomobil", "ev", "bev", "electric vehicle",
                     "electric car", "elektrikli suv", "şarj", "şarj istasyon"],
    ("konu", "hibrit"): ["hibrit", "hybrid", "plug-in", "phev", "şarj edilebilir hibrit"],
    ("konu", "konvansiyonel"): ["benzinli", "dizel", "içten yanmalı", "gasoline", "diesel", "conventional"],
    ("konu", "performans-ozel"): ["süper otomobil", "spor otomobil", "spor araba", "supercar", "sports car",
                                  "performans", "lüks"],
    ("konu", "bakim-aksesuar"): ["bakım", "aksesuar", "akü", "şarj cihaz", "temizlik", "car care", "accessory",
                                 "battery charger"],
    ("konu", "otonom-asistan"): ["otonom", "sürücüsüz", "sürüş asistan", "sürücü destek", "self-driving",
                                 "autopilot", "fsd", "adas"],
    ("tur", "sponsorlu"): ["sponsorlu", "reklam", "sponsored", "advertorial"],
    ("tur", "inceleme-rehber"): ["inceleme", "test sürüş", "değerlendirme", "karşılaştırma", "rehber", "review"],
    ("tur", "lansman-duyuru"): ["lansman", "tanıtım", "tanıttı", "duyuru", "duyurdu", "launch", "unveil"],
    ("tur", "pazar-finans"): ["satış", "ön sipariş", "gelir", "yatırım", "hisse", "borsa", "sales", "revenue",
                              "pre-order", "funding"],
    ("tur", "duzenleme-hukuk"): ["düzenleme", "yasa", "dava", "mahkeme", "yasak", "regulation", "lawsuit"],
    ("tur", "olay-kriz"): ["olay", "kriz", "kaza", "skandal", "güvenlik açığı", "incident", "breach"],
    ("tur", "gorus-analiz"): ["görüş", "yorum", "analiz", "röportaj", "opinion", "interview"],
    ("tur", "eglence-yasam"): ["eğlence", "dizi", "belgesel", "etkinlik", "entertainment"],
    ("tur", "gelisme-haber"): ["istifa", "seçim sonucu", "atama", "resign", "by-election"],
}

EXTRACT_PROMPT = (
    "List the named entities in this news article that a reader might search for: brands, specific vehicle "
    "models, organizations and people who are the subject of the story (not the author). For each give: key "
    "(lowercase full name), type (brand|model|org|person), aliases (0-3 short forms a user might type, e.g. "
    "'vw' for volkswagen, 'cr-v' for honda cr-v). No generic words, no numbers or years. At most 8 entities."
)
EXTRACT_SCHEMA = {
    "type": "object",
    "properties": {"entities": {"type": "array", "items": {
        "type": "object",
        "properties": {"key": {"type": "string"}, "type": {"type": "string"},
                       "aliases": {"type": "array", "items": {"type": "string"}}},
        "required": ["key", "type", "aliases"]}}},
    "required": ["entities"],
}


FOLD = str.maketrans("çğıöşüâîû", "cgiosuaiu")
# Türkçe isim ekleri, katlanmış ve ünlü uyumu varyantlarıyla; kökten sonra kalan kısım bunların zinciri olmalı
SUFFIXES = ("lar ler lari leri larin lerin i u in un nin nun si su sin sun yi yu ya ye a e da de ta te dan den tan ten "
            "la le yla yle li lu siz suz daki deki taki teki ki dir dur tir tur ca ce nda nde ndan nden na ne")
SUFFIX_RE = re.compile(r"(?:%s)+" % "|".join(sorted(SUFFIXES.split(), key=len, reverse=True)))
SOFTEN = {"p": "b", "t": "d", "k": "g"}  # ç→c katlamada zaten aynı; k→ğ katlamada g


def normalize(text: str) -> str:
    """Katlama: I/İ→i (Intel ve NVIDIA bozulmaz), Türkçe harf→ASCII, aksanlar düşer, noktalama ayırır."""
    text = text.replace("İ", "i").replace("I", "i").lower().translate(FOLD)
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))
    return " ".join(re.findall(r"[0-9a-z]+", text))


def token_matches(alias_tok: str, q: str) -> bool:
    """Kök + Türkçe ek zinciri; son ünsüz yumuşaması (destek→desteği, hibrit→hibride)."""
    if q == alias_tok:
        return True
    stems = {alias_tok}
    if len(alias_tok) >= 3 and alias_tok[-1] in SOFTEN:
        stems.add(alias_tok[:-1] + SOFTEN[alias_tok[-1]])
    return any(len(st) >= 3 and q.startswith(st) and (q == st or SUFFIX_RE.fullmatch(q[len(st):])) for st in stems)


def clean_alias(alias: str) -> str | None:
    a = normalize(alias)
    if not a or a in STOPLIST or re.fullmatch(r"[0-9 ]+", a):
        return None
    return a


def extract_entities(chat, article: dict) -> tuple[list[dict], dict]:
    """K2: tek haberden özel isimler. Dönüş: (varlıklar, kullanım)."""
    messages = [{"role": "system", "content": EXTRACT_PROMPT},
                {"role": "user", "content": f"Title: {article['title']}\n\n{article['content'][:3000]}"}]
    choice, usage, _ = chat(EXTRACT_MODEL, messages, None, max_tokens=800,
                            response_format={"type": "json_schema", "json_schema": {"name": "ent", "schema": EXTRACT_SCHEMA}},
                            chat_template_kwargs={"enable_thinking": False})
    return json.loads(choice["message"]["content"])["entities"], usage


def alias_matches(alias: str, query_tokens: list[str], query: str, upper_tokens: set[str] | None = None) -> bool:
    """K5. upper_tokens: sorguda büyük harfle yazılmış kelimeler (katlanmış), kısa adlar için."""
    if len(alias) < 3:
        return alias in (upper_tokens or set())
    words = alias.split()
    if any(len(w) == 1 for w in words):
        return f" {alias} " in f" {query} "
    return all(any(token_matches(w, t) for t in query_tokens) for w in words)


def upper_tokens_of(raw_query: str) -> set[str]:
    return {normalize(w) for w in re.findall(r"\w+", raw_query) if len(w) >= 2 and w.isupper()}


class KeywordDict:
    def __init__(self, entries: dict[str, dict], n_articles: int):
        self.entries, self.n_articles = entries, n_articles  # key -> {"type", "aliases", "articles"}
        # ön ek indeksi: takma adın ilk kelimesinin ilk 3 harfi -> (anahtar, takma ad); kısa adlar ayrı.
        # Sorgu yalnız kendi kelimelerinin ön ekleriyle eşleşen adayları dener (50K haberde 13,7 s/sorgu idi).
        self._index: dict[str, list[tuple[str, str]]] = {}
        self._short: list[tuple[str, str]] = []
        for key, e in entries.items():
            for alias in e["aliases"]:
                if len(alias) < 3:
                    self._short.append((key, alias))
                else:
                    self._index.setdefault(alias[:3], []).append((key, alias))

    @classmethod
    def build(cls, entities: dict[str, list[dict]], labels: dict[str, dict]) -> "KeywordDict":
        """entities: haber -> varlıklar (K2); labels: haber -> {"tur", "konu"} (K1)."""
        entries: dict[str, dict] = {}
        for (axis, label), aliases in TOPIC_SEEDS.items():  # K1
            arts = {aid for aid, lab in labels.items() if label in {v.strip() for v in (lab.get(axis) or "").split(",")}}
            if arts:
                entries[f"{axis}:{label}"] = {"type": "topic", "aliases": {a for a in map(clean_alias, aliases) if a},
                                              "articles": arts}
        for aid, ents in entities.items():  # K2
            for ent in ents:
                key = clean_alias(ent["key"])
                if not key:
                    continue
                e = entries.setdefault(key, {"type": ent.get("type"), "aliases": {key}, "articles": set()})
                e["aliases"].update(a for a in map(clean_alias, ent.get("aliases", [])) if a)
                e["articles"].add(aid)
        # K4b/K4c: belirsiz ve yaygın takma adları ayıkla (konu tohumlarına dokunma)
        n = len(labels)
        common = {k for k, e in entries.items() if e["type"] != "topic" and len(e["articles"]) > MAX_DF_RATIO * n}
        owners: dict[str, set[str]] = {}
        for k, e in entries.items():
            if e["type"] != "topic":
                for a in e["aliases"]:
                    owners.setdefault(a, set()).add(k)
        for k, e in entries.items():
            if e["type"] == "topic":
                continue
            e["aliases"] = {a for a in e["aliases"]
                            if a == k or (len(owners[a]) < 3 and not (a in common and a != k))}
        return cls(entries, n)

    def add(self, aid: str, entities: list[dict], labels: dict | None = None) -> None:
        """K8: yeni haberi artımlı ekle (yeniden kurmadan). Belirsiz takma ad temizliği (K4b/K4c) toplu kurulumda."""
        self.n_articles += 1
        for (axis, label), aliases in TOPIC_SEEDS.items():
            if label in {v.strip() for v in ((labels or {}).get(axis) or "").split(",")}:
                key = f"{axis}:{label}"
                if key not in self.entries:
                    self.entries[key] = {"type": "topic", "aliases": {a for a in map(clean_alias, aliases) if a},
                                         "articles": set()}
                    self._index_aliases(key)
                self.entries[key]["articles"].add(aid)
        for ent in entities:
            key = clean_alias(ent["key"])
            if not key:
                continue
            new = key not in self.entries
            e = self.entries.setdefault(key, {"type": ent.get("type"), "aliases": {key}, "articles": set()})
            e["aliases"].update(a for a in map(clean_alias, ent.get("aliases", [])) if a)
            e["articles"].add(aid)
            self._index_aliases(key, rebuild=not new)

    def _index_aliases(self, key: str, rebuild: bool = False) -> None:
        if rebuild:
            self._short = [(k, a) for k, a in self._short if k != key]
            for p in list(self._index):
                self._index[p] = [(k, a) for k, a in self._index[p] if k != key]
        for alias in self.entries[key]["aliases"]:
            (self._short if len(alias) < 3 else self._index.setdefault(alias[:3], [])).append((key, alias))

    def match(self, query: str, extra_keys: list[str] | None = None) -> tuple[list[str], dict[str, int]]:
        """K5–K7: sorguyla eşleşen anahtarlar ve haber -> eşleşme sayısı."""
        q = normalize(query)
        tokens = q.split()
        upper = upper_tokens_of(query)
        candidates = self._short + [c for p in {t[:3] for t in tokens} for c in self._index.get(p, [])]
        matched = []
        for key, alias in candidates:
            e = self.entries[key]
            if key in matched or (e["type"] != "topic" and len(e["articles"]) > MAX_DF_RATIO * self.n_articles):
                continue
            if alias_matches(alias, tokens, q, upper):
                matched.append(key)
        matched += [k for k in (extra_keys or []) if k in self.entries and k not in matched]
        hits: dict[str, int] = {}
        for key in matched:
            for aid in self.entries[key]["articles"]:
                hits[aid] = hits.get(aid, 0) + 1
        return matched, hits

    def save(self, path: Path = DICT_FILE) -> None:
        data = {"n_articles": self.n_articles, "entries": {
            k: {"type": e["type"], "aliases": sorted(e["aliases"]), "articles": sorted(e["articles"])}
            for k, e in sorted(self.entries.items())}}
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    @classmethod
    def load(cls, path: Path = DICT_FILE) -> "KeywordDict":
        data = json.loads(path.read_text(encoding="utf-8"))
        entries = {k: {"type": e["type"], "aliases": set(e["aliases"]), "articles": set(e["articles"])}
                   for k, e in data["entries"].items()}
        return cls(entries, data["n_articles"])
