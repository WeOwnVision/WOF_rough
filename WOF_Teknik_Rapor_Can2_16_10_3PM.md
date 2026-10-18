# W.O.F × FeedProof — Teknik Rapor (Sunucu + Flutter)

**Tarih:** 18 Ekim 2026
**Kime:** Talha
**Kimden:** Can (PM / Flutter) — geliştirme Claude Code ile yapıldı
**Bu rapor**, daha önce gönderilen `WOF_Gelistirme_Raporu_Talha.md`'nin yerine geçer ve onu kapsar.

> Bu belgede API anahtarı, şifre ya da gizli değer yok. `.env` repoya girmiyor.

---

## 0. Durum özeti

| | |
|---|---|
| **Branch** | `feature/demand-driven-ingestion` |
| **Taban commit** | `2543508 fix(evidence): prioritize Tier-1 wire/science…` (senin son commit'in) |
| **Commit / push** | **Yok.** Değişiklikler sadece çalışma kopyasında. Push edilmedi. |
| **Değişen dosyalar** | 16 dosya (+1571 / −493 satır) |
| **Yeni dosyalar** | 14 (7 kod, 7 test) |
| **Senin kanıt sistemin** | Dokunulmadı. `evidence_verifier.py`, `/api/intelligence/*` mantığı ve Tavily doğrulaması aynen duruyor. |
| **Geri dönüş** | Laya (`ENRICHMENT_ENGINE=hybrid`) ve MiniLM (`EMBEDDING_BACKEND=local`) kodda duruyor. İkisi de ayarla geri açılabiliyor. |

**Tek cümleyle:**
- Haber toplama talebe dayalı hale getirildi.
- Kişiselleştirme genişletildi: "+" takip ve bağlam cümlesi eklendi.
- Laya ve MiniLM, Nebius'taki Nemotron-Nano ve Qwen3-Embedding ile değiştirildi.
- Ana sayfaya kişiye özel "Latest Developments" kartı eklendi.
- WAI üç kapsamlı (haber / son gelişmeler / alan) DeepSeek asistanına dönüştü.

---

## 1. Mimari: önce / sonra

```
ÖNCE
  Tavily (sabit, dönerek çalışan sorgular)
    → worker: Laya (yerel CPU, ~9 sn) → güven < 0.65 ise Qwen3-30B (haberlerin %78'i)
    → MiniLM (384d, sadece İngilizce)
  Ana sayfa "Daily Brief" = tek haberin Tavily doğrulaması (~13 kredi, ~47 sn)
  WAI = tek haber, Nemotron-Super

SONRA
  Tavily (talebe dayalı şablon sorgular, kredi rezervi, çoklu anahtar)
    → worker (nano): menü temizliği → Nano özet → Qwen konu kapısı → Nano etiket   [4 paralel]
    → Qwen3-Embedding-8B (1024d, çok dilli, sorgulara talimat ön eki)
  Ana sayfa "Latest Developments" = DeepSeek başlık + paragraf (kullanıcı başına önbellekli)
           "Daily Brief"         = o 8 haberin kendi özetleri
  WAI = DeepSeek; kapsam: haber | son gelişmeler | alan; ilk mesajı model yazar
```

Model haritası:

| İş | Model | Not |
|---|---|---|
| Etiket | `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B` (thinking açık, JSON schema) | `TAG_MODEL` |
| Özet | Nemotron-Nano (thinking kapalı) | `SUMMARY_MODEL`. Uzun özet `FAST_MODEL` ile kısaltılır |
| Konu kapısı | `FAST_MODEL` (`Qwen/Qwen3-30B-A3B-Instruct-2507`) | Başlık + özet üzerinden |
| Vektör | `Qwen/Qwen3-Embedding-8B`, 1024d | `EMBEDDING_BACKEND`, `EMBEDDING_DIM` |
| Latest Developments kartı | `deepseek-ai/DeepSeek-V4-Flash-0731` (thinking kapalı) | `LATEST_MODEL`. Yedek: `FAST_MODEL` |
| WAI | DeepSeek-V4-Flash (thinking kapalı) | `WAI_MODEL`. Yedek: `FAST_MODEL` |
| Çeviri (bağlam cümlesi) | `FAST_MODEL` | |
| Doğrulama, synthesize, eski article chat | Değişmedi (`REASONING_MODEL` vb.) | |

Model seçimleri, takımın demo projesindeki (`nebius-nvidia-hackathon`) seçimlere ve bizim ölçümlerimize dayanıyor (bkz. §4).

---

## 2. Sunucu değişiklikleri

### 2.1 Talebe dayalı haber toplama

**Yeni dosyalar:** `query_templates.json`, `query_scheduler.py`
**Değişen dosya:** `ingest_tavily.py` (baştan düzenlendi)

**Şablonlar (`query_templates.json`):**
- 7 kategori ve 66 alt konunun her birine sade bir arama ifadesi atandı. Örnekler: `fintech → "fintech"`, `models_research → "new AI models"`, `AI → "generative AI"`.
- Alt konuların türü `core` ya da `specific` olarak işaretli.
- Arama varsayılanları: `topic=news`, `max_results=20`, `search_depth=basic`, `filter_by_published_date=true`.
- "+" takip şablonu: `"{name} {category_term}"`.
- Test verisi gibi duran alt konular `review` notuyla işaretlendi (§7).

**Talep ve takvim (`query_scheduler.py`):**
- Sorgu yalnızca en az bir kullanıcı o kategori ya da alt konuyu takip ediyorsa çalışıyor. Takip bilgisi `users.preferred_*` alanlarından ve `user_follows` tablosundan geliyor.
- Aynı sorgu bütün kullanıcılar için ortak çalışıyor; maliyet kullanıcı sayısına bağlı değil.
- Sıklıklar:

  | Tür | Sıklık | `time_range` |
  |---|---|---|
  | Kategori | 6 saat | day |
  | Temel alt konu | 24 saat | day |
  | Spesifik alt konu | 48 saat | week |
  | Takip | 48 saat | week |

- **Düşük verim backoff'u:** Üst üste 2 çalışmada 2'den az yeni haber gelirse aralık ikiye katlanıyor (üst sınır 168 saat). Verimli bir çalışmada sıfırlanıyor.
- **Kredi rezervi:** `TAVILY_CREDIT_RESERVE` (varsayılan 150). Toplam kalan kredi bu sınırın altına inecekse otomatik toplama duruyor.
- **Tek toplayıcı garantisi:** `pg_advisory_lock(hashtext('wof_ingest_schedule'))`. `--loop` ile "hemen çek" aynı sorguyu aynı anda çalıştıramıyor.
- Durum `ingest_query_state` tablosunda tutuluyor.

**`ingest_tavily.py` modları:**

```bash
python ingest_tavily.py --once             # vadesi gelenleri bir kez çalıştır (varsayılan)
python ingest_tavily.py --loop --tick 600  # 10 dk'da bir kontrol; kontrolün kendisi kredi harcamaz
python ingest_tavily.py --seed             # tek seferlik doldurma: TÜM şablonlar (week)
python ingest_tavily.py --legacy           # eski TAXONOMY_QUERIES davranışı (tek sefer)
```

Yeni yardımcılar:
- `_looks_like_article_url`: ana sayfa, bölüm, borsa fiyatı, iş ilanı ve etiket sayfalarını eliyor; `?id=` gibi haber kimliği taşıyan URL'leri tutuyor.
- `HarvestDedup`, `_harvest_query`, `_credit_budget`, `_schedule_lock`.
- `run_demand_cycle`, `fetch_follow_now`, `fetch_user_interests_now`, `run_seed`.

**Anında çekim ("fetch now"):**
- `PUT /api/users/{id}/preferences` ve "+" takip ekleme, kullanıcının vadesi gelmiş sorgularını bir BackgroundTask içinde hemen çalıştırıyor.
- Yakın zamanda çekilmiş konular atlanıyor.

### 2.2 Tavily anahtar rotasyonu ve kredi hesabı (`tavily_service.py`, `query_scheduler.py`)

**Anahtar rotasyonu:**
- `TAVILY_API_KEYS=k1,k2,…` tanımlanabiliyor; tanımlı değilse `TAVILY_API_KEY` kullanılıyor.
- `UsageLimitExceededError` gelince o anahtar o ay için "bitti" sayılıyor ve sıradakine geçiliyor.
- Hepsi bitmişse `get_tavily_client()` → `None` ve `search_news` → `[]` dönüyor; sistem çökmüyor.
- `tavily_calls.key_id` alanında anahtarın kendisi değil, SHA1 özetinin ilk 10 karakteri tutuluyor.

**Kredi hesabı:**
- Tavily `/usage` sayacının saatlerce donduğunu gördük.
- Bu yüzden harcanan kredi şöyle hesaplanıyor: `max(reported + o andan beri loglanan, önceki tahmin + o andan beri loglanan)`.
- Tahmin ay içinde hiç düşmüyor ve `tavily_usage_seen.estimated_used` alanında saklanıyor.

**Durum ucu:** `GET /api/ingestion/status` anahtar başına harcanan ve kalan krediyi, aktif takvimi gösteriyor.

### 2.3 "+" takip (`routers/follows.py`, `routers/users.py`)

- **Tablo:** `user_follows(user_id, name, follow_key, macro, embedding vector(N), created_at)`.
- **Uçlar:**
  - `GET /api/users/{id}/follows`: liste.
  - `POST /api/users/{id}/follows` (`{name, macro}`): 2–40 karakter, link olamaz, `macro` bilinen bir kategori olmalı, kullanıcı başına en fazla 3.
  - `DELETE /api/users/{id}/follows/{follow_id}`.
- **Ekleme anında:** İsmin vektörü (`embed_query`) kaydediliyor ve ilk çekim arka planda yapılıyor.
- **Akış puanına katkısı:**

  | Eşleşme | Puan |
  |---|---|
  | İsim başlıkta, tam kelime (`\m…\M`) | +40 |
  | İsim TL;DR'de | +25 |
  | Anlamsal: cos ≥ `follow_min` (Qwen 0,50 / MiniLM 0,45) | +25 |
  | Takip, seçilmiş bir kategori gibi sayılıyor | +20 |

- **Kategori dışı haberler:** Takiple eşleşen haber, kullanıcının kategorileri dışında olsa bile akışa giriyor.
- **Yanıt:** Her haber için `matched_follows` dönüyor.
- **Kelime sınırı:** "C++" gibi sembolle biten adlarda kelime sınırı sadece harf ve rakam tarafına konuyor.

### 2.4 Bağlam cümlesi (`routers/users.py`, `schemas.py`)

- **Alan:** `PUT /preferences` gövdesinde `interest_context`, en fazla 200 karakter.
  - Alan gönderilmezse kayıtlı cümle korunuyor.
  - `""` gönderilirse siliniyor.
  - Metin gönderilirse kaydediliyor.
- **Kolonlar:** `users.interest_context` (yazıldığı hali) ve `users.interest_context_en` (`FAST_MODEL` ile çevrilmiş İngilizcesi).
- **Çeviri:** Aynı cümle tekrar kaydedilince yeniden çevrilmiyor. Çeviri başarısız olursa standart cümleye düşülüyor.
- **İlgi vektörü:**
  - Cümle varsa vektör `embed_query(context_en)` ile üretiliyor.
  - Yoksa `_standard_interest_text`: *"Technical news and updates in X, specifically focused on Y."* Alt konu yoksa son kısım ekleniyor; eski "focused on ." hatası ve "Ai" yazımı düzeltildi.
- **Yanıtlar:** Login, GET ve PUT `interest_context` döndürüyor.
- **Not:** Qwen3-Embedding Türkçeyi de iyi anlıyor (AUC 0,935 / İngilizce 0,940). Çeviri artık zorunlu değil ama İngilizce bir tık daha iyi olduğu için tutuldu.

### 2.5 Etiketleme ve özet: `ENRICHMENT_ENGINE=nano` (yeni `llm_enrichment.py`, `worker.py`)

**Akış (haber başına):**

1. **`strip_site_chrome(title, body)`:** Demodan alındı. Başlık metinde menüden sonra geçiyorsa oradan başlıyor, kısa madde ve sadece link olan satırları atıyor, linkleri metne indiriyor.
   - Neden: Windows Central, forex.com ve NYC Comptroller gibi sayfalarda ilk 1500+ karakter menüydü ve konu kapısı gerçek haberleri eliyordu.
2. **Özet:** Nano, thinking kapalı, en fazla 2 cümle ve ~45 kelime. Sondaki "(44 words)" artıkları temizleniyor.
   - 50 kelimeyi geçerse `FAST_MODEL` ile kısaltılıyor. Nano thinking kapalıyken metni değiştirmeden geri döndürüyor; Qwen kelime sayısı verilince güvenilir kısaltıyor.
3. **Konu kapısı:** `FAST_MODEL`, mevcut `SYSTEM_PROMPT_TOPIC_CHECK` prompt'u, **başlık + özet** üzerinden. Hata olursa haber tutuluyor.
4. **Etiket:** Nano, thinking açık, `response_format=json_schema`.
   - `macro_tag` 7 kategoriden biri olmak zorunda (enum).
   - `macro_tags` en fazla 3.
   - `micro_tags` 66 alt konudan en fazla 6.
   - `normalize_labels`, haberin kategorilerine ait olmayan alt konuları atıyor (Nano bir Finance haberine Hardware'den "transistors" ekleyebiliyordu).
   - Boş cevapta bir kez yeniden deniyor (ilk denemelerin ~%7-10'unda geçici boş cevap gördük).
5. **Yedek:** Nano iki kez başarısız olursa eski tek çağrılık `generate_full_enrichment` (`FAST_MODEL`) kullanılıyor.

**Diğer ayrıntılar:**
- **Paralellik:** `NANO_CONCURRENCY` (varsayılan 4) haber aynı anda işleniyor; batch boyutu 2×. Yerel embedder bir kilitle korunuyor.
- **Kaydedilen değerler:** `on_topic_score` 1,0 / 0,0. `confidence_score` boş (hiçbir yer okumuyordu).
- **`worker.py` yeniden düzenlemesi:** Döngü gövdesi `process_article(row, classifier, has_classifier)` fonksiyonuna taşındı. `hybrid` yolu satır satır aynı; sadece `continue` → `return` oldu ve off-topic metni `OFF_TOPIC_TLDR` sabitine taşındı (diff ile kontrol ettim).
- **Laya ikinci görüşü (hybrid modda kalıyor):** Laya "konu dışı" derse `confirm_on_topic()` `FAST_MODEL`'e bir kez daha soruyor. Kurtarılan haber `on_topic_score = 0.5` alıyor ve tam LLM sınıflandırmasından geçiyor. Ölçüm: 13 haberin 11'i kurtarıldı.

**Konu kapısı tasarımı nasıl seçildi:** 73 haber elle etiketlendi (49 gerçek haber, 16 çöp sayfa, 8 sınırda) ve 6 kurulum karşılaştırıldı.

| Kurulum | Elenen gerçek haber | Tutulan çöp |
|---|---|---|
| Qwen, ham metin | 6 | 4 |
| **Qwen, başlık + özet (seçilen)** | **1** | 8 |
| gpt-oss-120b, ham metin | 4 | 9 |
| gpt-oss-120b, özet | 2 | 10 |
| Nano thinking, ham / özet | 1 / 1 | 14 / 15 |

Gerçek haberi kaybetmemek önceliklendirildi. Tutulan çöplerin çoğu, yeni URL filtresinin zaten engellediği eski kayıtlar.

**Yeniden etiketleme:** Mevcut bütün haberler yeni akışla yeniden etiketlendi (236 haber, 453 sn, hata 0). Rollback için eski etiketlerin JSON yedeği bende duruyor.

### 2.6 Vektörler: Qwen3-Embedding (`embedder.py`, `migrate_embeddings.py`)

**Backend'ler:**
- `EMBEDDING_BACKEND=nebius` (varsayılan): `NebiusEmbedder`. Nebius embeddings API'si `dimensions=EMBEDDING_DIM` (varsayılan 1024) ile çağrılıyor. API'nin kırptığı vektör, tam vektörün kırpılmış haliyle 0,9999 benzerlikte; dönen vektörler birim uzunlukta.
- `EMBEDDING_BACKEND=local`: Eski `TextEmbedder` (MiniLM, 384d).

**Arayüz:**
- `embed_text` / `embed_batch`: belgeler (haberler) için.
- `embed_query`: sorgular için (arama metni, takip adı, ilgi cümlesi). Qwen'in talimat ön ekini ekliyor: `Instruct: Given a news search query, retrieve news articles relevant to the query\nQuery: `. Bu çağrılar LRU önbellekli (2048). MiniLM'de `embed_query == embed_text`.
- Batch 64, 2 deneme.

**Modele özel eşikler** (`SIMILARITY_THRESHOLDS`, `similarity_thresholds()`). Sabitler koddan buraya taşındı:

| Anahtar | Kullanıldığı yer | MiniLM (orijinal) | Qwen 1024 |
|---|---|---|---|
| `search_noise` | arama kesme noktası | 0,22 (dist 0,78) | 0,345 |
| `search_direct` | "Direct Focus" | 0,32 (dist 0,68) | 0,423 |
| `search_top` | relevance 99 noktası | 0,60 | 0,69 |
| `same_story` | worker story clustering | 0,55 (dist 0,45) | 0,643 |
| `digest_sibling` | daily digest kardeş kaynak | 0,52 (dist 0,48) | 0,622 |
| `follow_min` | "+" anlamsal eşleşme | 0,45 | 0,50 |
| `feed_floor` | akış puanı `25·(sim−floor)/(1−floor)` | 0 | 0,20 |

- **Kalibrasyon yöntemi:** Qwen eşikleri, MiniLM'in ilgisiz çiftlerden geçirdiği oranla aynı oranı geçirecek şekilde (kantil eşleme) seçildi.
- **`follow_min`:** 12 isim × 219 haberde elle seçildi.
- **`feed_floor`:** Qwen ilgisiz haberlere bile ~0,25 benzerlik veriyor. Taban çıkarılınca akış puanı MiniLM ölçeğine geri dönüyor (kategori içi ~7, dışı ~2,5 puan).
- **Senin için önemli:** `same_story` ve `digest_sibling` eşiklerinde MiniLM'in davranışını koruyacak şekilde eşleme yaptım. MiniLM 0,55'te 219 haberde 141 çift geçiriyordu; bu "aynı hikâye" için oldukça gevşek. Qwen'de gerçekten aynı hikâye olan çiftler ~0,85-0,96 civarında. Kanıt kümelemesini sıkılaştırmak istersen değerler `embedder.py`'de.

**Değişen çağrı noktaları:**
- `routers/search.py`: `embed_query`, eşikler, relevance formülü genelleştirildi.
- `routers/users.py`: ilgi vektörü `embed_query` ile, takip geri doldurma, `feed_floor`.
- `routers/follows.py`: `embed_query`.
- `worker.py`: kümeleme eşiği.
- `routers/intelligence.py`: digest kardeş eşiği.
- DDL'ler artık `embedding_dim()` kullanıyor: `worker.init_db_schema`, `query_scheduler.FOLLOWS_DDL`, `migrate_v1_tables.V1_DDL` (f-string). `schema.sql` 1024'e çekildi ve not eklendi.

**Taşıma: `python migrate_embeddings.py --rebuild`**
1. `articles.embedding`, `users.interest_embedding`, `user_follows.embedding` ve `story_clusters.centroid_embedding` kolonlarını `vector(N)` boyutuna getiriyor (`USING NULL`). Gerekirse HNSW indeksini düşürüp yeniden kuruyor.
2. Haberleri yeniden vektörleştiriyor. Metin: `title. tldr`; tldr yoksa `clean_text[:300]`.
3. Küme merkezlerini (centroid) üye haberlerin `AVG(embedding)` değeri olarak yeniden hesaplıyor.
4. Takipleri `embed_query(name)` ile yeniden üretiyor.
5. Kullanıcıları yeniden kuruyor: başlangıç cümlesi (`context_en` ya da standart cümle) üzerine like/dislike etkileşimleri `created_at` sırasıyla `ema_update` ile yeniden oynatılıyor. Öğrenilmiş ilgi kaybolmuyor.
   - EMA matematiği `routers/users.ema_update` fonksiyonuna taşındı. Endpoint ve taşıma aynı fonksiyonu kullanıyor; davranış değişmedi.
6. Parametresiz çalıştırınca eskisi gibi sadece eksik vektörleri dolduruyor.

**Bizdeki taşıma sonucu:** 236 haber, 339 küme, 2 takip, 5 kullanıcı. Maliyet < $0,01.

### 2.7 Latest Developments kartı (yeni `routers/latest.py`)

**Uç:** `GET /api/users/{id}/latest-developments` → `{headline, paragraph, articles, model, generated_at, refreshing}`. Onboarding bitmemişse 409.

**Girdi:** `get_personalized_feed_data(page_size=8)` (kullanıcının ilk 8 haberi) + kullanıcının konuları + bağlam cümlesi.

**Model:** `LATEST_MODEL` = DeepSeek-V4-Flash.
- `extra_body={"chat_template_kwargs": {"thinking": false, "enable_thinking": false}}`.
- `response_format=json_object`, temperature 0,2.
- Yedek: `FAST_MODEL`.

**Kurallar:**
- Başlık en fazla 70 karakter; kartta 26-28 px serif yazıyla en fazla 3 satır.
- Uzun başlık, karakter sayısıyla birlikte modele bir kez geri gönderiliyor. Hâlâ uzunsa kelime sınırından kesiliyor (`fit_headline`).
- Paragraf 3-4 cümle, en fazla 90 kelime.
- Sadece verilen özetlerdeki olgular kullanılıyor; fiyat ve liste sayfaları atlanıyor.

**Önbellek: `user_latest_developments` tablosu** (`profile_key`, `stories_key`, `headline`, `paragraph`, `articles` jsonb, `model`, `created_at`).
- Kayıtlı kart varsa anında dönüyor.
- Kart 60 dakikadan eskiyse ve ilk 8 haber ya da profil değiştiyse arka planda yenileniyor (`refreshing: true`).
- `PUT /preferences`, `forget_latest()` ile kartı siliyor; bir sonraki istek kartı hemen yeniden yazıyor.
- Profil değişikliği arka planda ele alınıyor, çünkü like'lar da kullanıcının konularını değiştiriyor.

**Ortak fonksiyon:** `latest_card(user_id, background=None)` WAI tarafından da kullanılıyor.

**Ölçüm:** 1,5-2,6 sn, ~$0,0002/kart. Thinking açıkken 9-18 sn sürüyordu ve kalite benzerdi.

**Tavily notu:** Ana sayfa artık `/api/intelligence/daily-digest`'i çağırmıyor. Uç ve kodu sunucuda aynen duruyor.

### 2.8 WAI asistanı (yeni `routers/wai.py`)

**Uçlar:**
- `POST /api/wai/open` (`WaiScope`) → `{mode, title, subtitle, opening, sources}`.
- `POST /api/wai/chat` (`WaiChatRequest`) → SSE: `data: {"token": …}`, en sonda `data: [DONE]`. Format eski article chat ile aynı.

**Kapsamlar:**

| `mode` | Nereden açılır | Malzeme |
|---|---|---|
| `story` | Haber kartı ("Ask WAI") | Haberin `clean_text`'i (10.000 karaktere kadar, eski chat gibi) |
| `latest` | Ana sayfa kartı ("Ask WAI about this") | Kart başlığı + paragraf + 8 haberin `[n]` numaralı özetleri |
| `area` | WAI sekmesi, alan seçimi | Kategori ya da alt konunun en yeni on-topic haberleri: son 7 gün, 4'ten azsa 30 gün, en fazla 10 |

**Açılış mesajını model yazıyor.** Moda göre talimat: en fazla 55 kelime ve İngilizce. Model okuduğunu söylüyor, en çarpıcı 1-2 konuyu açmadan ima ediyor ve "özetleyeyim mi / derine inelim mi" diye soruyor. Alanda hiç haber yoksa sabit bir metin dönüyor.

**Sistem prompt'u:**
- Sadece verilen malzemeden cevap veriyor; uydurma yok.
- latest ve area modlarında kaynakları `[n]` ile gösteriyor.
- Sorunun dilinde cevaplıyor; 150 kelimeyi aşmıyor.
- Okuyucunun konuları ve bağlam cümlesi prompt'a ekleniyor.

**Durumsuz (stateless) tasarım:**
- İstemci her mesajda kapsamı, `source_ids` listesini (numaralar sabit kalsın diye açılıştaki haberler) ve son 6 turu (açılış dahil) gönderiyor.
- Açılış geçmişte olduğu için "Yes please" gibi kısa cevaplar doğru anlaşılıyor.
- Sunucuda yeni tablo yok.

**Hız:** Mesaj başına tek model çağrısı yapılıyor, araç döngüsü yok. Ölçüm: açılış 0,8-1,3 sn (bir kez soğuk başlangıçta 4,4 sn), ilk token ~0,7 sn, mesaj başına ~$0,0003-0,0006.

**Yedek:** `WAI_MODEL` başarısız olursa `FAST_MODEL` deneniyor. Akış yarıda kesilirse istemciye `{"error"}` olayı gidiyor.

**Neden ajan değil:** Demodaki ajan (araç döngüsü) daha esnek ama 3-9 sn sürüyor. Çok adımlı sorular gerekirse sonra eklenebilir.

**Eski uç:** `/api/articles/{id}/chat` değişmedi. Flutter, sunucu kullanıcısı olmayan (yerel) modda onu kullanmaya devam ediyor.

### 2.9 Değişen mevcut dosyalar

| Dosya | Özet |
|---|---|
| `ingest_tavily.py` | §2.1 |
| `tavily_service.py` | §2.2; `search_news(filter_by_published_date)` cache anahtarına eklendi |
| `worker.py` | §2.5, §2.6; nano modu, `process_article` refactor, paralellik, kümeleme eşiği, DDL boyutu |
| `routers/users.py` | §2.3, §2.4, §2.6; `ema_update`, `USER_COLUMNS` / `_user_out`, `forget_latest` çağrısı |
| `routers/search.py` | §2.6 |
| `routers/intelligence.py` | §2.6 (sadece digest kardeş eşiği) |
| `embedder.py` | §2.6 |
| `migrate_embeddings.py` | §2.6 (`--rebuild`) |
| `migrate_v1_tables.py` | yeni DDL'ler (state, follows, credit, context, latest), boyut |
| `schema.sql` | yeni tablolar ve kolonlar, vector(1024) |
| `schemas.py` | `FollowCreate`, `interest_context` |
| `main.py`, `routers/__init__.py` | follows, ingestion, latest, wai router'ları |
| `.env.example`, `AGENTS.md`, `README.md` | dokümantasyon |

### 2.10 Veritabanı değişiklikleri

Hepsi idempotent. `migrate_v1_tables.py` uyguluyor; ayrıca ilgili uçlar ilk çağrıda tabloyu kendileri oluşturuyor.

| Tablo / kolon | Amaç |
|---|---|
| `ingest_query_state` | sorgu başına son çalışma, aralık, düşük verim sayacı |
| `user_follows` (+ `embedding`) | "+" takipler |
| `tavily_usage_seen` (+ `estimated_used`), `tavily_calls.key_id` | kredi hesabı |
| `users.interest_context`, `users.interest_context_en` | bağlam cümlesi |
| `user_latest_developments` | ana sayfa kartı önbelleği |
| Vektör kolonları `vector(384)` → `vector(1024)` | `migrate_embeddings.py --rebuild` |

### 2.11 Uçlar (yeni ve davranışı değişen)

| Uç | Durum |
|---|---|
| `GET/POST/DELETE /api/users/{id}/follows[/{fid}]` | yeni |
| `GET /api/ingestion/status` | yeni |
| `GET /api/users/{id}/latest-developments` | yeni |
| `POST /api/wai/open`, `POST /api/wai/chat` | yeni |
| `PUT /api/users/{id}/preferences` | `interest_context`, anında çekim, kartı unutma |
| `POST /api/users/login`, `GET /preferences` | `interest_context` dönüyor |
| `GET /api/feed/personalized` | takip puanları, `matched_follows`, `feed_floor` |
| `GET /api/search` | Qwen sorgu vektörü ve eşikleri (Türkçe arama çalışıyor) |

### 2.12 Ortam değişkenleri

| Değişken | Varsayılan | Not |
|---|---|---|
| `ENRICHMENT_ENGINE` | `nano` | `hybrid` = Laya |
| `NANO_CONCURRENCY` | 4 | |
| `SUMMARY_MODEL`, `TAG_MODEL` | Nemotron-3-Nano | isteğe bağlı |
| `EMBEDDING_BACKEND` | `nebius` | `local` = MiniLM |
| `EMBEDDING_DIM` | 1024 | değişince `--rebuild` gerekir |
| `EMBEDDING_MODEL` | Qwen3-Embedding-8B | isteğe bağlı |
| `LATEST_MODEL`, `WAI_MODEL` | DeepSeek-V4-Flash-0731 | isteğe bağlı |
| `TAVILY_API_KEYS` | — | virgülle ayrılmış; `TAVILY_API_KEY`'in yerine geçer |
| `TAVILY_CREDIT_RESERVE` | 150 | |

`AI_BASE_URL` Nebius'u göstermeli; bütün yeni modeller Nebius Token Factory üzerinden çağrılıyor.

### 2.13 Testler

Hepsi ağ ve DB gerektirmeyen birim testleri:

```bash
python tests/test_query_scheduler.py     # 10
python tests/test_tavily_keys.py         # 4
python tests/test_interest_context.py    # 3
python tests/test_llm_enrichment.py      # 6
python tests/test_embedder.py            # 3
python tests/test_latest.py              # 4
python tests/test_wai.py                 # 5
```

Mevcut `test_content_cleaner` ve `test_ingestion_and_cleaner` de geçiyor.

---

## 3. Flutter (`rss_ui`) değişiklikleri

### 3.1 Değişen ve yeni dosyalar

| Dosya | İçerik |
|---|---|
| `lib/services/api_service.dart` | Taxonomy, preferences, personalized feed, interactions, follows, latest-developments, `openWai` / `waiChatStream`. Varsayılan adres `127.0.0.1` (Windows'ta `localhost` önce IPv6 deniyordu). Onboarding'deki canlı web araması kaldırıldı (kredi harcıyor, kaydetmiyordu). |
| `lib/models/api_models.dart` | `AppUser` (+onboarding, tercihler, `interestContext`), `TaxonomyCategory`, `PersonalizedFeed`, `InteractionResult`, `UserFollow`, `LatestDevelopments`, `WaiOpening`… |
| `lib/state/app_state.dart` | Oturum, onboarding adımları, kişisel akış, like/dislike kuyruğu, takipler, latest kartı (onboarding sonunda önceden yükleniyor; `refreshing` ise 8 sn sonra bir kez daha soruluyor), WAI (`WaiThread`, `WaiMode`, açılış, yeniden deneme) |
| `lib/web/pages/web_onboarding_page.dart` (yeni) | 3 adım: seçim → beğeni testi (8 kart) → sonuç |
| `lib/web/widgets/interest_form.dart` (yeni) | Kategori ızgarası, alt konular (en fazla 12), "+" takip, bağlam cümlesi ve 4 örnek |
| `lib/web/pages/web_home_page.dart` | "LATEST DEVELOPMENTS" kartı, haber özetlerini gösteren "Daily Brief", "Ask WAI about this" |
| `lib/widgets/home_cards.dart` | `DailySummaryCard` esnetildi (etiket, başlık, özet, `onAsk`); yeni `StorySummariesCard` |
| `lib/web/pages/web_chat_page.dart` | WAI: 3 kapsam, alan seçici (3 boy), "What WAI read" paneli, moda göre öneriler, Markdown cevap |
| `lib/web/pages/web_feed_page.dart`, `web_profile_page.dart`, `web_gate.dart`, `web_shell.dart`, `web_ui.dart`, `seed_articles.dart` | Eşleşme rozeti, "Because you follow …", NOPE damgası, profil düzenleme, onboarding yönlendirmesi |
| `share_tunnel.ps1` | `-ApiUrl` parametresi; rastgele alt alan adı gelirse yeniden deneme |

### 3.2 WAI ekranında donma hatası (bulundu, düzeltildi)

**Belirti:** `flutter run -d chrome` ile WAI'ye soru gönderilince sayfa donuyor. Terminal log'u `[POST/stream] …/chat` satırında kalıyor. Eski article chat'te de aynısı oluyordu.

**Kök neden:** Gönderim anında yazma kutusu `readOnly: busy` ile kilitleniyordu. Odaktaki alanın `readOnly`'si değişince Flutter web motorunda bir debug assertion'ı patlıyor:

```
text_editing.dart:1253  "The DOM element of this text editing strategy is not currently active."
```

`flutter run`'ın bağladığı debugger bu hatada sayfayı duraklatıyor. Release build'de bu assertion yok; o yüzden tünel sürümü etkilenmiyordu.

**Teşhis yöntemi:** Görünmez Chrome + DevTools Protocol ile otomatik giriş, alan seçimi, soru yazma ve Enter. Dört ortamda denendi: API tek başına, release, debug web-server, `flutter run -d chrome`. Hata sadece sonuncusunda çıktı.

**Düzeltme:** `readOnly` kaldırıldı. Meşgulken gönderim `_send` içinde engelleniyor; yazılan metin korunuyor. Aynı ortamda tekrar denendi: assertion 0, sayfa sürekli cevap verdi.

### 3.3 Testler

71 Flutter testinin hepsi geçiyor, analyzer temiz. Yeni testlerin kapsadıkları:
- `openWai` / `waiChatStream` istek gövdeleri.
- Alan seçicinin üç boyu.
- Alan sohbetinin açılışı ve "Yes please" turunda gönderilen geçmiş.
- Latest kartından ve haberden WAI açılışı.
- Latest kartı ve Daily Brief.
- Tavily'li digest'in ana sayfada artık çağrılmadığı.

---

## 4. Ölçümler

| Konu | Önce | Sonra | Nasıl ölçüldü |
|---|---|---|---|
| Kredi başına haber | ~3,4 | ~6,3 | toplayıcı logları |
| Kredi başına işe yarar haber | 2,9 | 5,9 | aynı |
| Fiyat/borsa sayfası oranı | %7 | %0,7 | aynı |
| Etiket kalitesi (kör hakem gpt-oss-120b, 29 haber) | 6 kazanç | 23 kazanç | A/B |
| Özet kalitesi | 3 kazanç | 24 kazanç | A/B |
| Ana kategori doğru | 21/29 | 28/29 | hakem |
| Alt konu kalitesi (1-5) | 2,31 | 3,59 | hakem |
| Haber işleme | ~17 sn, sırayla | ~7 sn, 4 paralel | worker logları |
| Alt konu sorgusu → haber (AUC / ilk 5) | 0,903 / %56 | 0,940 / %64 | 219 etiketli haber |
| Türkçe sorgu (AUC / ilk 5) | 0,598 / %18 | 0,935 / %59 | aynı |
| Arama süresi | 25-65 ms | ~0,5 sn (önbellekte ~0,15 sn) | uçtan uca |
| Süreç belleği | worker 1,8 GB + API ~0,5 GB | her biri ~50-100 MB | işletim sistemi |
| Ana sayfa Tavily harcaması | ~13 kredi/açılış | 0 | — |

**Maliyet (Nebius, ölçülen):**
- Haber başına ~$0,0005 (1000 haber ≈ $0,5).
- Latest kartı ~$0,0002.
- WAI mesajı ~$0,0003-0,0006.
- Toplam ölçüm ve deneme harcaması birkaç sent.

**Tavily:** 1000/ay planından 710 kredi kalmış. Şu an sadece haber toplama harcıyor.

---

## 5. Çalıştırma ve taşıma (senin makinende)

```bash
git fetch && git checkout feature/demand-driven-ingestion     # paylaşıldığında
# .env: AI_BASE_URL Nebius, AI_API_KEY; isteğe bağlı TAVILY_API_KEYS
python migrate_v1_tables.py                   # yeni tablolar/kolonlar (idempotent)
python migrate_embeddings.py --rebuild        # vektörleri 1024d Qwen'e taşır (~1 sent)
python worker.py                              # ENRICHMENT_ENGINE=nano (varsayılan)
python ingest_tavily.py --loop                # talebe dayalı toplama
uvicorn main:app --host 0.0.0.0 --port 8000
```

- **Eski haberlerin etiketleri:** Mevcut haberler Laya etiketleriyle kalır. Yeniden etiketlemek için `UPDATE articles SET is_processed = FALSE` ve çalışan worker yeterli. Bu sırada akış boş görünür. Ben bunu repo dışındaki bir betikle, haberleri akışta tutarak yaptım; istersen repoya ekleyebilirim.
- **Eski kuruluma dönüş:** `.env` içinde `ENRICHMENT_ENGINE=hybrid` ve `EMBEDDING_BACKEND=local` ayarlayıp `python migrate_embeddings.py --rebuild` çalıştırmak yeterli.

Benim yerel kurulumum (Docker'sız) şöyle:
- Postgres `pgserver` pip paketiyle venv içinde çalışıyor; `uuid-ossp` yerine `gen_random_uuid` shim'i var.
- Başlatma ve durdurma `local_dev/start_backend.ps1` ve `stop_backend.ps1` ile yapılıyor (repo dışı).
- Dış paylaşım `local_dev/share_api_tunnel.ps1` (API) ve `rss_ui/share_tunnel.ps1` (arayüz) ile localtunnel üzerinden.

---

## 6. Bilinen sınırlar ve riskler

1. **Nebius bağımlılığı:** Etiket, özet, vektör, kart ve WAI'nin hepsi Nebius'ta. Nebius çökerse yeni haber işlenmez ve arama durur; mevcut akış çalışmaya devam eder. Yerel yedekler var ama geçiş bir taşıma gerektiriyor.
2. **Konu kapısı tolerans tercihi:** 348 haberden 26'sı konu dışı. Kapı "gerçek haberi kaybetme" yönünde ayarlı; birkaç sınırda haber (ör. Fransa borç krizi) eleniyor, bazı eski çöp sayfalar tutuluyor.
3. **Eski çöp kayıtlar:** URL filtresinden önce toplanmış birkaç kayıt (Instagram, Yahoo IPO takvimi, kripto fiyat sayfası) hâlâ veritabanında ve bazı kullanıcıların ilk 8 haberine giriyor. Temizlik bekliyor.
4. **localtunnel kırılgan:** Şifre ekranı çıkıyor ve bağlantı zaman zaman kopuyor. Betikler doğru adresi yeniden deniyor, ama jüri için kalıcı bir adres lazım.
5. **WAI tek çağrılık:** "Geçen ayla karşılaştır" gibi çok adımlı sorular için ajan döngüsü yok.

---

## 7. Sana sorular ve öneriler

1. **`.env.example` model adları eski.** `FAST_MODEL` ve `REASONING_MODEL` örnekleri Nebius'ta artık yok. Ayrıca Nemotron-Super, `max_tokens=30` ile boş içerik döndürüyor. Bizde `FAST_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, `REASONING_MODEL=nvidia/nemotron-3-super-120b-a12b`. Güncelleyelim mi?
2. **Test verisi gibi duran alt konular:** `runtime`, `benchmarks`, `transistors`, `endurance_testing`, `electric_vehicles`, `oled`, `apu`, `variable_refresh_rate`, `settlement`, `interbank`, `k2_18b`. Gerçek mi, silinecek mi?
3. **Unlike yapınca öğrenilen konular geri alınmıyor.** Like etiket ekliyor, unlike çıkarmıyor.
4. **Story clustering eşiği:** MiniLM davranışı korunacak şekilde eşledim. Kanıt sistemin için daha sıkı bir "aynı hikâye" eşiği ister misin? (§2.6)
5. **Tavily ödülü için görünürlük:** Ana sayfa artık Tavily doğrulamasını çağırmıyor. Önerim, haber detayına bir **"Verify this story"** düğmesi ekleyip senin kanıt sistemini sadece istenince çalıştırmak. Kredi korunur, özellik de jüriye net görünür. Ne dersin?
6. **Branch'i nasıl paylaşalım?** Tek commit mi, konulara bölünmüş commit'ler mi (toplama / takip / bağlam / nano / embedding / latest / WAI)? PR mı, doğrudan branch mi?

---

## 8. Sıradaki işler

- Eski çöp kayıtların temizliği ve test kullanıcılarının silinmesi.
- "Verify this story" düğmesi (öneri, §7.5).
- Jüri öncesi `--seed` ile toplu haber çekimi (~70-80 kredi) ve kalıcı demo adresi.
- Onboarding sonunda "Open my Feed" düğmesinin ana sayfaya yönlendirilmesi (karar bekliyor).
- Arayüz çevirisi (EN/TR/DE/NL): sana bırakıldı.
