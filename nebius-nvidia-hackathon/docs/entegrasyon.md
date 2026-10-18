# Entegrasyon: orkestrasyon → sunucu (Talha) ve arayüz (Ludi)

Model tarafı iki fonksiyon verir. HTTP sunucusu, veritabanı ve arayüz bu repoda yok; onlar sizde.

| Kim | Ne çağırır | Ne zaman |
|---|---|---|
| Talha (sunucu) | `ingest(haber, chat, embed)` | Yeni haber veritabanına girerken, bir kez |
| Talha (sunucu) | `Assistant.ask(oturum, mesaj, ilgi_alanları, on_event, profile)` | Kullanıcı mesaj gönderince |
| Talha (sunucu) | `Assistant.ozet(oturum, ilgi_alanları, on_event, profile)` | "Bana özel özet" düğmesine basılınca |
| Ludi (arayüz) | Sunucunun ilettiği olaylar (aşağıda) | Cevap akarken |

Gereken: Python 3.12, repo kökünde `.env` içinde `NEBIUS_API_KEY`. Ek paket yok (yalnız standart kütüphane).

## 1. Soru → cevap: `Assistant.ask`

```python
from src.orchestrator.assistant import Assistant

asst = Assistant("emir")          # korpus: "automotive" | "emir" (veritabanı bağlanınca değişecek, aşağıya bakın)
asst.interests()                  # arayüzdeki ilgi alanı seçenekleri: [{"key": "konu:ev", "label": "ev", "articles": 4}, ...]

def on_event(event: dict):        # her olayı arayüze ilet (ör. SSE: "event: <type>\ndata: <json>\n\n")
    ...

result = asst.ask("oturum-123", "Anthropic bu hafta ne duyurdu?", interests=["konu:ev"], on_event=on_event)
```

`ask` bloklayan bir çağrıdır (bir tur 3–20 s). Sunucu onu ayrı bir thread/işçi içinde çalıştırıp olayları akıtmalı. Aynı `Assistant` nesnesi birden çok oturumu taşır (oturum geçmişi şu an bellekte).

### Kullanıcıya özel bağlam (profil) ve kişiye özel özet

İsteğe bağlı `profile` verilirse sistem prompt'una "kullanıcı bağlamı" olarak eklenir; verilmezse hiçbir şey eklenmez.
İşaretlenen `konular` her olayın bu konular açısından anlatılmasını sağlar (ör. kullanıcı "yapay zekâ"yı işaretlemişse bir finans olayının yapay zekâ boyutu); haberlerde bağlantı yoksa uydurulmaz. Profil cevabın odağını, derinliğini ve biçimini değiştirir; "yalnız haberlerden cevap ver, atıf yap" kurallarını değiştiremez,
doğrulayıcı da aynen çalışır. Profil kullanıcı ayarlarında tutulur (veritabanı, Talha) ve her çağrıda güncel hâli gönderilir.

```python
profile = {
    "konular": ["yapay zekâ", "finans"],              # işaretlenen konular: olay bunların kesişiminden anlatılır
    "seviye": "orta",                                 # basit | orta | uzman
    "bicim": "ayrintili",                             # kisa | madde | ayrintili
    # isteğe bağlı serbest metin (en çok 300 karakter): "ad", "hakkinda", "odak"
}
asst.ask("oturum-123", "Anthropic bu hafta ne duyurdu?", profile=profile, on_event=on_event)
asst.ozet("oturum-123", interests=["konu:ev"], profile=profile, on_event=on_event)   # kişiye özel haber özeti
```

Bütün alanlar isteğe bağlı; tanınmayan `seviye`/`bicim` değerleri yok sayılır. `ozet` aynı olayları ve dönüşü verir.
Örnek profiller: `profiller/`. Terminalde: `python sohbet.py --profil profiller/ai-finans.json`, sonra `/ozet`.

### Olaylar (sırayla)

| type | alanlar | Arayüz ne yapar |
|---|---|---|
| `status` | `text`: "Aranıyor: electric vehicle", "Okunuyor: <başlık>" | Cevap alanının üstünde ince gri satır / spinner |
| `delta` | `text`: cevabın bir parçası | Cevap alanına ekle (akış) |
| `reset` | — | O ana kadar akan cevabı sil (model tool çağırdı ya da ana model düştü, yedek baştan yazacak) |
| `sources` | `items`: [{`id`, `title`, `source`, `date`, `url`}] | Cevabın altında kaynak listesi; cevaptaki `[e015]` gibi atıfları bunlara bağla |
| `answer` | `text` (tam cevap), `model` | Akan metni bununla değiştir (son hali) |
| `badge` | `badge`, `claims` | Doğrulama rozeti (aşağıda); cevaptan 3–10 s sonra gelir |
| `error` | `text`, `attempts` | "Cevap üretilemedi, tekrar dene" |

Örnek akış: `status` → `delta`… → `sources` → `answer` → `badge`. Yedek modele geçişte: `delta`… → `reset` → `status` → `delta`… .

### Doğrulama rozeti (`badge`)

| badge | Anlamı | Gösterim önerisi |
|---|---|---|
| `ok` | Bütün iddialar kaynaklarda var | ✓ yeşil, küçük |
| `unsupported` | Bazı iddialar kaynakta bulunamadı (çoğu zaman zararsız) | ⚠ sönük sarı; tıklayınca `claims` |
| `contradicted` | Bir iddia kaynakla çelişiyor | ✗ kırmızı, belirgin; `claims` göster |
| `skipped` / `unavailable` / `parse_error` | Doğrulama yapılamadı | Rozet gösterme ya da gri "doğrulanamadı" |

Ölçüm: bilerek bozulmuş 6 sayının 6'sı `contradicted` çıktı; yanlış alarmların hepsi `unsupported` idi.

### Dönüş değeri

`{"status": "ok", "answer", "model", "sources": [id...], "badge", "claims", "cost_usd"}` (`cost_usd`: baş model + doğrulayıcı, tur başına; loglanabilir) ya da `{"status": "api_error" | "empty_answer" | "max_steps", "answer": None}`.

## 2. Haber gelince: `ingest`

```python
from src.orchestrator import nebius
from src.orchestrator.ingest import ingest
from src.orchestrator.dictionary import KeywordDict

nebius.load_env()
embed = lambda texts: nebius.embed(texts, "Qwen/Qwen3-Embedding-8B")[0]
out = ingest({"title": ..., "content": ..., "source": ...}, nebius.chat, embed, category="Technology")
# out = {"content": temiz metin, "summary": 2 cümle, "vector": 4096 float, "entities": [...],
#        "labels": {"tur": ..., "konu": [...], "flags": [...]}, "cost_tokens": {...}}
sozluk.add(haber_id, out["entities"], {"tur": out["labels"]["tur"], "konu": ", ".join(out["labels"]["konu"])})
```

Maliyet: haber başına ~0,05 sent (Nemotron-Nano özet + varlık + sınıflandırma, Qwen embedding). Süre: ~6–10 s, sınıflandırma düşünme modunda (paralel çalıştırılabilir).
Sınıflandırma doğruluğu (etiket seti v2, üç model uzlaşısı): tür %79, net vakalarda %88; konu Jaccard 0,79. `category` verilmezse etiket üretilmez.

## 3. Veritabanında tutulması gerekenler (Talha)

Haber başına (Ludi/Emir'in ortak çıktı biçimine ek olarak, "Veri sorunları (v2)"):

| Alan | Kaynak |
|---|---|
| `id`, `title`, `source`, `url`, `published_at`, `content_status` | toplayıcı (Ludi/Emir) |
| `content` | `ingest` → temizlenmiş metin |
| `summary` | `ingest` |
| `vector` (4096 float) | `ingest`; arama bunu kullanır (pgvector vb. uygun) |
| `entities` | `ingest`; sözlük bundan kurulur |
| `tur`, `konu` (çoklu), `flags` | `ingest(..., category=...)` → `labels` |

Oturum başına: mesaj geçmişi (`Assistant.sessions[id]["history"]`, OpenAI mesaj biçimi). Kalıcı yapılacaksa sunucu bunu kaydedip geri yükler.

**Şu anki sınır:** `Assistant` korpusu `data/` altındaki JSON dosyalarından okuyor (`load_corpus`). Veritabanı hazır olunca tek değişiklik `load_corpus` + özet/vektör/sözlük yüklemesini veritabanından okuyan bir fonksiyonla değiştirmek; arama, ajan ve doğrulayıcı aynı kalır. Bunu birlikte bağlarız.

## 4. Gecikme ve maliyet (ölçülmüş, 16–82 haberlik korpus)

| | Değer |
|---|---|
| İlk metnin görünmesi (akış) | ort. ~2–3 s; tool kullanan ilk turda ~5–9 s |
| Doğrulama rozeti | cevaptan sonra ~3–10 s |
| Tur başına maliyet | ~0,2–0,5 sent (baş model + doğrulayıcı) |
| Zaman aşımı | 45 s veri gelmezse yedek modele geçer |

Ayrıntılı ölçümler: `docs/model-eval-2026-10-10.md`. Taksonomi: `docs/taksonomi.md`.
