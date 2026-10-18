# W.O.F × FeedProof — Geliştirme Raporu (Flutter + Sunucu)

**Tarih:** 18 Ekim 2026
**Kime:** Talha
**Durum:** Sunucu değişiklikleri `feature/demand-driven-ingestion` branch'inde. Henüz **commit edilmedi, push edilmedi**. Senin son commit'inin (`2543508 fix(evidence): prioritize Tier-1 wire/science…`) üstüne kuruldu. Kanıt algoritmana dokunulmadı.

> Bu belgede hiçbir API anahtarı ya da gizli değer yok. `.env` dosyası repoya girmiyor.

---

## 1. Kısa özet

| Alan | Ne yapıldı |
|---|---|
| **Haber toplama** | Sabit sorgu listesinin yerine **talebe dayalı (demand-driven)** toplayıcı geldi. Şablonlar `query_templates.json` dosyasında. Bir sorgu yalnızca o konuyu takip eden en az bir kullanıcı varsa çalışıyor. |
| **Tavily kredisi** | Birden fazla anahtar desteği eklendi: biri bitince otomatik olarak diğerine geçiyor. Kalan kredi her anahtar için ayrı tahmin ediliyor. Kredi rezervin altına inince toplayıcı duruyor. |
| **"+" takip** | Kullanıcı kendi konusunu takip edebiliyor (ör. "Revolut", "Steam Deck"); kullanıcı başına en fazla 3. Akışta başlık/özet eşleşmesi ve anlamsal (vektör) eşleşmeyle öne çıkıyor. |
| **Laya ikinci görüş** | Laya'nın "konu dışı" dediği haberler hızlı bir LLM'e bir kez daha soruluyor. Böylece Anthropic halka arzı, Klarna/Affirm gibi haberler kurtarılıyor. |
| **Flutter** | Bütün API uçları bağlandı. 3 adımlı onboarding var (seçim, beğeni testi, sonuç). Kişisel akış, beğeni/beğenmeme, eşleşme rozeti, "Because you follow …" gerekçeleri ve profil düzenleme eklendi. |
| **Ölçüm** | Kredi başına haber sayısı **~3,4'ten ~6,3'e** çıktı. Kredi başına işe yarar haber **2,9'dan 5,9'a** çıktı. Fiyat/borsa sayfalarının oranı **%7'den %0,7'ye** indi. |

---

## 2. Sunucu değişiklikleri

### 2.1 Dosya listesi

**Yeni dosyalar**

| Dosya | Görevi |
|---|---|
| `query_templates.json` | Sorgu şablonları: 7 kategori ve 66 alt konu. Çalışma sıklıkları, backoff ve seed ayarları da burada. |
| `query_scheduler.py` | Talep hesabı, sıradaki sorgular, zamanlama durumu, kredi hesabı. Tablo DDL'leri de bu dosyada. |
| `routers/follows.py` | `GET/POST/DELETE /api/users/{id}/follows` |
| `routers/ingestion.py` | `GET /api/ingestion/status`: anahtar başına kredi ve aktif zamanlama |
| `tests/test_query_scheduler.py` | 10 test |
| `tests/test_tavily_keys.py` | 4 test: anahtar rotasyonu ve kredi tahmini |

**Değişen dosyalar**

| Dosya | Değişiklik |
|---|---|
| `ingest_tavily.py` | Baştan düzenlendi. Yeni modlar: `--once`, `--loop`, `--seed`, `--legacy`. Eski kod duruyor ama varsayılan olarak çalışmıyor. |
| `tavily_service.py` | Çoklu anahtar rotasyonu, `filter_by_published_date` parametresi ve `tavily_calls` kayıtlarına `key_id` eklendi. |
| `routers/users.py` | Kişisel akış SQL'ine takip eşleşmesi ve `matched_follows` eklendi. Tercihler kaydedilince ilgili konular hemen çekiliyor. |
| `worker.py` | Laya konu dışı dediğinde LLM'e ikinci kez soruluyor (`confirm_on_topic`). |
| `schema.sql`, `migrate_v1_tables.py` | Yeni tablolar: `ingest_query_state`, `user_follows`, `tavily_usage_seen`. Ayrıca `tavily_calls` tablosuna `key_id` kolonu eklendi. |
| `schemas.py` | `FollowCreate` modeli |
| `main.py`, `routers/__init__.py` | Yeni router'lar kaydedildi. |
| `.env.example` | `TAVILY_API_KEYS` ve `TAVILY_CREDIT_RESERVE` eklendi. |
| `README.md`, `AGENTS.md` | Toplayıcı dokümantasyonu |

Toplam: 12 dosya değişti (+867 / −233 satır), 6 dosya yeni.

### 2.2 Talebe dayalı haber toplama

**Eski durum:** `TAXONOMY_QUERIES` içinde sabit, dönerek çalışan sorgular vardı ve kullanıcıya özel şablon sorgular ekleniyordu. Kimse takip etmese de kredi harcanıyordu. "latest news and developments in …" kalıbı da iş ilanı ve fiyat sayfası getiriyordu.

**Yeni durum:**

1. Taksonomiden **sade, odaklı sorgular** üretildi. Her kategori ve alt konu için bir tane var. Örnekler:
   - fintech → `"fintech"`
   - llm_agents → `"AI agents and large language models"`
   - models_research → `"new AI models"`
2. `compute_demand()` her döngüde kullanıcıların seçtiği kategori ve alt konuları ve takiplerini topluyor. **Kimsenin takip etmediği şeyin sorgusu çalışmıyor.** Maliyet kullanıcı sayısına değil, takip edilen benzersiz konu sayısına bağlı. Herkes aynı sorgunun sonucunu paylaşıyor.
3. Çalışma sıklıkları:

   | Tür | Sıklık | Tavily `time_range` |
   |---|---|---|
   | Kategori | 6 saatte bir | day |
   | Temel (core) alt konu | 24 saatte bir | day |
   | Spesifik alt konu | 48 saatte bir | week |
   | "+" takip | 48 saatte bir | week |

4. **Düşük verim backoff'u:** Bir sorgu üst üste 2 kez 2'den az yeni haber getirirse aralığı 2'ye katlanıyor. Üst sınır 168 saat. Haber gelince aralık normale dönüyor.
5. **Arama ayarları:** `topic=news`, `max_results=20`, `search_depth=basic`, `filter_by_published_date=True`.
6. **URL filtresi** (`_looks_like_article_url`): ana sayfa, bölüm sayfası, borsa fiyatı, iş ilanı ve etiket sayfalarını eliyor. `?id=` gibi haber kimliği taşıyan URL'leri tutuyor.
7. **Aynı anda tek toplayıcı:** `pg_advisory_lock(hashtext('wof_ingest_schedule'))` kullanılıyor. Loop ile "hemen çek" aynı anda çalışırsa ikisi aynı sorguyu çalıştırmıyor.

**CLI:**

```bash
python ingest_tavily.py --once            # vadesi gelen sorguları bir kez çalıştır (varsayılan)
python ingest_tavily.py --loop --tick 600 # 10 dakikada bir kontrol et; kontrolün kendisi kredi harcamaz
python ingest_tavily.py --seed            # tek seferlik doldurma: TÜM şablonlar (time_range week)
python ingest_tavily.py --legacy          # eski davranış, tek sefer
```

> Not: "10 dakikada bir" yalnızca kontrol aralığı. Bir sorgu sadece vadesi geldiyse çalışıyor (yukarıdaki tablo).

### 2.3 Tavily anahtar rotasyonu ve kredi hesabı

- `.env` içinde `TAVILY_API_KEYS=key1,key2,...` tanımlanabiliyor. Tanımlı değilse eskisi gibi `TAVILY_API_KEY` okunuyor.
- Tavily `UsageLimitExceededError` döndürürse o anahtar o ay için "bitti" sayılıyor ve bir sonrakine geçiliyor. Hepsi bitmişse `get_tavily_client()` `None` döndürüyor ve `search_news` boş liste veriyor; sistem çökmüyor.
- `tavily_calls.key_id` alanında anahtarın kendisi değil, SHA1 özetinin ilk 10 karakteri tutuluyor.
- **Tavily `/usage` sayacı saatlerce donabiliyor** (ölçtük). O yüzden harcanan kredi şöyle tahmin ediliyor:
  `max(Tavily'nin söylediği + o andan beri bizim logladığımız, önceki tahmin + o andan beri loglanan)`.
  Tahmin ay içinde hiç geri düşmüyor ve `tavily_usage_seen.estimated_used` alanında saklanıyor.
- `TAVILY_CREDIT_RESERVE` (varsayılan 150): toplam kalan kredi bu sayının altına inecekse otomatik toplama duruyor. Böylece doğrulama ve jüri demosu için kredi kalıyor.
- `GET /api/ingestion/status`: anahtar başına kullanılan ve kalan krediyi ve sıradaki sorguları gösteriyor.

### 2.4 "+" takip (custom follows)

**Tablo:** `user_follows(user_id, name, macro, embedding vector(384), …)`

**API:**

| Uç | İşlev |
|---|---|
| `GET /api/users/{id}/follows` | Liste |
| `POST /api/users/{id}/follows` | `{name, macro}`. Kurallar: 2–40 karakter, link olamaz, `macro` bilinen bir kategori olmalı, kullanıcı başına en fazla 3. |
| `DELETE /api/users/{id}/follows/{follow_id}` | Sil |

**Ekleme anında:**
- Takip adının MiniLM embedding'i kaydediliyor.
- Arka planda (BackgroundTask) ilk çekim yapılıyor; kullanıcı beklemiyor.
- Paylaşılan sorgu `"{name} {category_term}"` oluyor (ör. `"Revolut finance"`) ve 48 saatte bir çalışıyor. İki kullanıcı aynı şeyi takip ederse sorgu tek kez çalışıyor.

**Akış puanına etkisi** (`routers/users.py`):

| Eşleşme | Puan |
|---|---|
| Takip adı haber başlığında geçiyor (tam kelime, PostgreSQL `\m…\M`) | +40 |
| Takip adı TL;DR'de geçiyor | +25 |
| Anlamsal eşleşme: haber ve takip embedding'i arasında cos ≥ 0.45 | +25 |
| Eşleşen haber, kullanıcının seçtiği bir kategoriden sayılıyor | +20 |

- Toplam puan `LEAST(100, …)` ile sınırlanıyor.
- Haber kullanıcının kategorileri dışında olsa bile, takiple eşleşiyorsa akışa giriyor.
- Yanıtta her haber için `matched_follows` listesi dönüyor. Flutter bunu "Because you follow X" olarak gösteriyor.
- "C++" gibi sembolle biten adlarda kelime sınırı yalnızca harf ve rakam tarafına konuyor.
- Yalnızca gövdede geçen zayıf eşleşmeler artık sayılmıyor. Önceki denemede bunlar gerçek haberlerin önüne geçiyordu.
- 0.45 eşiği kalibre edildi:
  - "Quantum Physics" takibinde eşleşen haber sayısı 0'dan 8'e çıktı.
  - Revolut ve Steam Deck takiplerinde yanlış eşleşme çıkmadı.

### 2.5 Tercih kaydedilince "hemen çek"

`PUT /api/users/{id}/preferences` artık bir BackgroundTask başlatıyor. Kullanıcının yeni seçtiği konulardan vadesi gelmiş olanlar hemen çekiliyor; yakın zamanda çekilmiş olanlar atlanıyor.

Ölçüm: PUT 36 ms'de döndü. Arka planda 2 sorgu çalıştı ve 10 yeni haber geldi.

### 2.6 Laya "konu dışı" için ikinci görüş (`worker.py`)

**Sorun:** Laya'nın "on-topic" sorusu farklı alanları kesen haberleri reddediyordu. Örnekler: Anthropic gelirleri/IPO (hem AI hem Finance), Klarna/Affirm.

**Çözüm:**
- Laya bir haberi konu dışı sayarsa `confirm_on_topic()` aynı soruyu FAST_MODEL'e evet/hayır olarak soruyor.
- LLM "evet" derse haber kurtarılıyor: `on_topic = RESCUED_ON_TOPIC_SCORE (0.5)` atanıyor ve haber tam LLM sınıflandırması (escalation) yolundan geçiyor.

**Sonuç:** 13 haberin 11'i kurtarıldı. Dışarıda kalan 2'si gerçekten konu dışıydı: bir üniversite duyurusu ve bir liste sayfası.

### 2.7 Senin değişikliklerinle birleşme

Branch, senin kanıt algoritması commit'lerinin üstünde. Senin eklediklerin aynen duruyor:
- dislike EMA (−0.12)
- beğenilen haberin macro/micro etiketlerini tercihlere ekleme
- evidence tier önceliği

`routers/users.py` içinde kişisel akış SQL'i alt sorguya (`s`) sarıldı. Puan hesabının temeli (micro ≤40, macro 20, 25·cos, 15·recency) değişmedi; takip puanları bunun üstüne ekleniyor.

### 2.8 Veritabanı değişiklikleri

`python migrate_v1_tables.py` hepsini idempotent olarak uyguluyor; `schema.sql` de güncel.

| Tablo/kolon | Amaç |
|---|---|
| `ingest_query_state` | Sorgu başına son çalışma zamanı, aralık, art arda düşük verim sayısı |
| `user_follows` | "+" takipler ve embedding |
| `tavily_usage_seen` | Anahtar başına son `/usage` görüntüsü ve `estimated_used` |
| `tavily_calls.key_id` | Hangi anahtarla çağrı yapıldığı (hash) |

### 2.9 Yeni ortam değişkenleri

```env
# Opsiyonel, virgülle ayrılmış. Tanımlıysa TAVILY_API_KEY yerine kullanılır.
# TAVILY_API_KEYS=tvly-...,tvly-...
TAVILY_CREDIT_RESERVE=150
```

### 2.10 Testler

```bash
python tests/test_query_scheduler.py   # 10 test
python tests/test_tavily_keys.py       # 4 test (ağ ve DB gerekmiyor)
```

Mevcut `test_ingestion_and_cleaner` ve `test_content_cleaner` testleri de geçiyor.

---

## 3. Flutter (`rss_ui`) değişiklikleri

### 3.1 API katmanı

**`lib/services/api_service.dart`**
- Varsayılan adres `http://127.0.0.1:8000` oldu. `localhost` Windows'ta önce IPv6'yı deniyor ve takılıyordu.
- Yeni metotlar: `getTaxonomy`, `getPreferences`, `updatePreferences`, `getPersonalizedFeed`, `toggleInteraction`/`setInteraction`, `getDailyDigest` (180 sn timeout), `getFollows`/`addFollow`/`removeFollow`.
- PUT ve DELETE desteği eklendi.
- Onboarding'deki canlı web araması (`searchLiveWeb`) kaldırıldı. Kredi harcıyor ama sonucu DB'ye kaydetmiyordu.

**`lib/models/api_models.dart`**
- `Article` modeline `personalScore`, `isLiked` ve `matchedFollows` eklendi.
- `AppUser` modeline `onboardingCompleted` ve tercih listeleri eklendi.
- Yeni modeller: `TaxonomyCategory`, `PersonalizedFeed`, `InteractionResult`, `DailyDigest`, `UserFollow` ve diğerleri.

### 3.2 Uygulama durumu (`lib/state/app_state.dart`)

- **Oturum:** Sunucu kullanıcısı ile yerel kullanıcı ayrıldı. Onboarding'i bitirmemiş kullanıcı onboarding'e yönleniyor.
- **Kişisel akış:** Hızlı kullanıcı değişikliklerinde eski yanıtlar `_feedGeneration` sayacıyla yok sayılıyor.
- **Beğeni ve beğenmeme:** Etkileşimler sıraya alınıp sunucuya gönderiliyor. Sunucunun öğrendiği yeni etiketler (`updated_preferred_*`) profile yansıyor.
- **Kütüphane:** Kayıtlar kullanıcıya özel saklanıyor.
- **"Neden bu haber" gerekçeleri:** Önce takip eşleşmesi gösteriliyor, sonra kategori ve alt konu.

### 3.3 Onboarding: 3 adım, 60 saniye hedefi

Ürün hedefimiz "aha anı"nın onboarding biter bitmez gelmesi.

1. **Seçim** (`interest_form.dart`): Kategori seçmek zorunlu. Alt konu seçmek isteğe bağlı (en fazla 12). "Follow something specific" bölümünden en fazla 3 "+" takip eklenebiliyor.
2. **Beğeni testi:** Çeşitlendirilmiş 8 kart sağa/sola kaydırılıyor. Sonuçlar like/dislike olarak sunucuya gidiyor ve ilgi vektörünü hemen besliyor.
3. **Sonuç:** Haberlerin TL;DR'lerinden 60 saniyelik bir özet, "Because you follow …" gerekçeleri ve eşleşme rozeti (MatchBadge) gösteriliyor. Haber azsa "toplanıyor" notu çıkıyor; arka planda "hemen çek" çalışıyor.

### 3.4 Diğer ekranlar

- **Akış** (`web_feed_page.dart`): Eşleşme rozeti, gerekçe satırı, kaynak paneli ve beğenmeme için "NOPE" damgası eklendi.
- **Ana sayfa** (`web_home_page.dart`): "Picked for you" bölümü ve Daily Brief kartı. Bu kart `/api/digest/daily`'ye bağlı; aşağıdaki nota bak.
- **Profil** (`web_profile_page.dart`): İlgi alanları ve takipler görünüyor. Düzenleme penceresi var; tercihler değişirse öğrenilmiş ilginin sıfırlanacağına dair uyarı çıkıyor.
- **Küçük uyum düzenlemeleri:** `web_gate.dart`, `web_shell.dart`, `web_ui.dart`, `home_cards.dart`, `seed_articles.dart`.
- **`share_tunnel.ps1`:** `-ApiUrl` parametresi eklendi.
- **Testler:** `test/api_service_test.dart` ve `test/widget_test.dart`. 65 testin hepsi geçiyor.

---

## 4. Ölçümler

### 4.1 Eski ve yeni toplayıcı

| Metrik | Eski | Yeni |
|---|---|---|
| Kredi başına haber | ~3,4 | **~6,3** |
| Kredi başına işe yarar haber | 2,9 | **5,9** |
| Fiyat/borsa sayfası oranı | %7 | **%0,7** |
| Konu dışı oranı | %9 | **%6** |
| Takip edilen sorgulardan haber gelen | — | Hepsi |

### 4.2 A/B testleri (toplam 18 kredi)

| Bulgu | Sonuç |
|---|---|
| Sade terim ve "latest news and developments in …" kalıbı | Sade terim daha iyi |
| `topic=finance` | Tarihsiz fiyat ve etkinlik sayfaları getiriyor; her yerde `topic=news` kullanıyoruz |
| "developments" kelimesi | İş ilanı getiriyor; kaldırıldı |
| "AI research" | "new AI models" ile değiştirildi |
| "artificial intelligence" | "generative AI" ile değiştirildi |
| `filter_by_published_date=True` | İşe yarıyor |

### 4.3 Maliyet (Nebius Token Factory)

| İş | Yaklaşık maliyet |
|---|---|
| Worker özeti | $0,00014 / haber |
| Chat | $0,0015 / mesaj |
| Digest / synthesize | $0,0027 / rapor |

Darboğaz Nebius değil, **Tavily kredisi**. 1.000 kredi/ay (Researcher plan) var ve kalan kredi tahmini yaklaşık 733.

**Worker hızı:** Haber başına ~17 sn, bunun ~9 sn'si CPU'daki Laya. İki worker RAM'e sığmıyor: worker başına 1,8 GB gerekiyor, boşta 2,1 GB var.

---

## 5. Yerelde çalıştırma (bende kurulu olan)

Docker kullanılmıyor. Postgres, `pgserver` pip paketiyle venv içinde çalışıyor.

- `uuid-ossp` uzantısı yok. Yerine şu shim eklendi:
  `CREATE FUNCTION uuid_generate_v4() … RETURN gen_random_uuid()`.
- pgvector ve HNSW çalışıyor.
- Başlatma ve durdurma için repo dışında, `WOV_WOF\local_dev\` klasöründe iki script var:
  - `start_backend.ps1`: Postgres, Ollama (Laya), API, worker ve `ingest_tavily.py --loop` başlatıyor. Sonra MiniLM'i bir ısınma isteğiyle hazırlıyor.
  - `stop_backend.ps1`
- Kullanılan modeller: `FAST_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, `REASONING_MODEL=nvidia/nemotron-3-super-120b-a12b`.
- Flutter, `127.0.0.1:8000` adresine bağlanıyor.

---

## 6. Senin için notlar ve açık konular

1. **`.env.example` model adları eski.** O adlar Nebius'ta artık yok. Ayrıca Nemotron `max_tokens=30` ile boş yanıt dönüyor; FAST_MODEL için Qwen3-30B Instruct kullanıyoruz. `.env.example` dosyasını güncelleyelim mi?
2. **Laya'nın on-topic sorusu** farklı alanları kesen haberleri reddediyor. Şimdilik ikinci görüşle çözdük; kalıcı çözüm Laya'nın promptunda olabilir.
3. **Test verisi gibi duran taksonomi etiketleri:** `runtime`, `benchmarks`, `transistors`, `endurance_testing`, `electric_vehicles`, `oled`, `apu`, `variable_refresh_rate`, `settlement`, `interbank`, `k2_18b`. `query_templates.json` içinde "review" notuyla işaretlendi. Gerçek mi, silinecek mi?
4. **Unlike yapınca öğrenilen kategoriler geri alınmıyor.** Like etiket ekliyor, unlike çıkarmıyor.
5. **"Daily Brief" aslında tek haberlik bir doğrulama (fact-check).** Her çağrı ~13 Tavily kredisi harcıyor ve ~47 sn sürüyor. UI'da adı yanıltıcı. Kartı "Story check" olarak yeniden adlandırıp isteğe bağlı çalıştırmayı planlıyoruz.
6. **Tavily `/usage` sayacı geç güncelleniyor.** Kredi hesabında bunu telafi ettik (bkz. 2.3).
7. **MiniLM yalnızca İngilizce.** Türkçe metin vektöre dökülünce anlamlı sonuç vermiyor. Bağlam cümlesi (aşağıda) için önce çeviri gerekiyor.
8. **Flutter'daki sesli bülten oynatıcısı şimdilik simülasyon.**

---

## 7. Sıradaki işler

1. **Bağlam cümlesi** (planlandı, başlamadı):
   - Onboarding'de isteğe bağlı bir soru: "What should your feed help you with?" Öneri çipleri: *I invest*, *I build products*, *I study this*, *I just follow the news*.
   - Sunucu tarafı:
     - `interest_context` alanı. Alan gönderilmezse eski değer korunuyor, boş gönderilirse siliniyor, metin gönderilirse kaydediliyor.
     - Orijinal cümle ve İngilizce çevirisi `users` tablosunda saklanıyor; çeviriyi FAST_MODEL yapıyor.
     - İlgi vektörü bu cümleden üretiliyor ve `routers/users.py` içindeki şablon cümlenin yerini alıyor. Cümle yoksa seçilen konulardan standart bir cümle kuruluyor. Bu standart cümledeki "focused on ." hatası da düzeltilecek.
   - Deneyde, şablonla karıştırılan cümle şablonun baskısında kayboldu. Bu yüzden cümle şablonla birleştirilmeyecek, **şablonun yerine** geçecek.
2. Kullanıcı başına "Neler oldu / son gelişmeler" satırı
3. Daily Brief kartının adını ve yerini değiştirmek
4. Laya'yı GPU'da çalıştırmak (CUDA torch)
5. İkinci ve üçüncü Tavily anahtarını `.env` dosyasında `TAVILY_API_KEYS` olarak eklemek
6. Arayüz çevirisi (EN/TR/DE/NL), ertelendi

---

### Branch'i almak için

Henüz push edilmedi. Hazır olunca branch `feature/demand-driven-ingestion` olarak paylaşılacak. Aldıktan sonra şunlar yeterli:

```bash
python migrate_v1_tables.py    # yeni tablolar, idempotent
python ingest_tavily.py --once # vadesi gelen sorgular (veya --loop)
```

`.env` dosyanda yeni bir şey zorunlu değil. `TAVILY_CREDIT_RESERVE` varsayılan olarak 150; `TAVILY_API_KEYS` isteğe bağlı.
