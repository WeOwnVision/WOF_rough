# Nebius × NVIDIA Hackathon — haber asistanı (model ve orkestrasyon tarafı)

Toplanan haberleri etiketleyen, özetleyen ve kullanıcının sorularını kaynak göstererek, doğrulayarak cevaplayan model katmanı.
Haber toplayıcı (Emir/Ludi), sunucu/veritabanı (Talha) ve arayüz (Ludi) bu repoda değil; bağlantı noktası **`docs/entegrasyon.md`**.

## Buradan başla

1. Python 3.12. Ek paket gerekmez, yalnız standart kütüphane.
2. `.env.example` dosyasını `.env` olarak kopyala, `NEBIUS_API_KEY=` satırına Nebius Token Factory anahtarını yaz.
3. Veriyi takım Drive'ından `data/raw/` altına koy (git'e girmez): `data/raw/emir/emir_sample.json`, `data/raw/emir2/*.json`,
   `data/raw/sampleNews/`. Varsa hazır özet/vektör/sözlük dosyaları `data/processed/` altına (yoksa asistan anahtar kelime aramasıyla çalışır).
4. Bağlantıyı dene (ücretsiz, model listesini çeker):
   ```
   python scripts/hazirlik/list_nebius_models.py
   ```
5. **Asistanla konuş:**
   ```
   python sohbet.py                                   # emir korpusu, soru-cevap
   python sohbet.py -q "Anthropic bu hafta ne duyurdu?"   # tek soru
   python sohbet.py --corpus emir2                    # Emir'in 11 Ekim verisi (1026 haber)
   python sohbet.py --profil profiller/ai-finans.json   # kişiye özel cevap; sohbette /ozet = kişiye özel haber özeti
   ```
   Her soru gerçek modelleri çağırır, soru başına ~1 sent. Örnek çıktı: `docs/ornek-sohbet.md`.

Windows'ta `python` yerine `.venv\Scripts\python.exe` de kullanılabilir. Komutlar proje kökünden çalıştırılır.

**Sunucuya bağlayacaksan (Talha):** `sohbet.py` ile aynı çağrıyı kullan. `Assistant` sunucu başlarken **bir kez** oluşturulur
(korpusu, özetleri, vektörleri belleğe yükler), her istekte `ask` çağrılır:

```python
from src.orchestrator.assistant import Assistant

asst = Assistant("emir")                                   # bir kez
asst.ask("oturum-1", "Anthropic bu hafta ne duyurdu?", on_event=print)   # her soruda
```

Olaylar ve veritabanı alanları: `docs/entegrasyon.md`.

## Nasıl çalışıyor

İki ayrı akış var: haber **gelince** bir kez çalışan hazırlık, soru **sorulunca** çalışan tur.

```
haber gelince   ingest()                                        src/orchestrator/ingest.py
                  metin temizliği → özet → özel isimler → tür/konu/bayrak   (Nemotron-3-Nano)
                  → vektör                                                  (Qwen3-Embedding-8B)
                  → sonuç veritabanına (Talha), özel isimler sözlüğe

soru gelince    Assistant.ask()                                 src/orchestrator/assistant.py
                  1. baş model (DeepSeek-V4-Flash, hata/45 s takılmada yedek V4.1-Flash) tool çağırır:
                       search_news  → anahtar kelime + eşikli anlamsal arama + sözlük, 5'lik sayfa, önce özetler
                       get_article  → tam metni yalnız özette olmayan ayrıntı için açar
                  2. cevap akışla yazılır, [e009] gibi atıflarla
                  3. doğrulayıcı (Nemotron-3-Super) her iddiayı tam kaynak metne karşı kontrol eder
                       → ✓ doğrulandı  ⚠ kaynakta yok  ✗ kaynakla çelişiyor
```

Her adım `on_event` ile olay olarak bildirilir (`status`, `delta`, `reset`, `sources`, `answer`, `badge`, `error`);
sunucu bunları SSE/WebSocket ile arayüze iletir.

## Klasör yapısı

```
sohbet.py              BURADAN BAŞLA: terminalde asistanla konuş
profiller/              örnek kullanıcı profilleri (kişiye özel bağlam, docs/entegrasyon.md)
toplayici/              haber toplayıcı (Emir'in mecmua_scraper): sorgu → ortak biçimde JSON; kendi README'si var
src/orchestrator/      ürün kodu (sunucu bunu çağırır)
  assistant.py           giriş noktası: Assistant.ask() ve olaylar
  ingest.py              haber gelince: metin temizliği, özet, sınıflandırma; ingest()
  agent.py               baş model döngüsü, yedek modele geçiş, sistem prompt'u
  tools.py               search_news / get_article, arama, korpus yükleme
  verifier.py            doğrulayıcı: iddiaları kaynaklarla karşılaştırır, rozeti üretir
  dictionary.py          Türkçe/İngilizce terimden habere köprü kuran anahtar kelime sözlüğü
  taxonomy.py            etiketlerin (tür / konu / alt konu / bayrak) tek kaynağı
  automotive_gold.py     Automotive altın etiketlerini okur (automotive korpusu)
  clusters.py            aynı haberin farklı kaynaklardaki kopyalarını birleştirme
  nebius.py              Nebius istemcisi: .env, chat (akışlı), embedding, maliyet
scripts/
  hazirlik/            korpus hazırlığı: bağlantı testi, özet, sözlük
  olcum/               ölçüm ve testler: baş model, sohbet, uçtan uca, doğrulayıcı, arama eşiği
  subtag/              alt etiketleme (tür/konu): etiketleme dosyası, ikinci etiketleyici, denetim, sınıflandırıcı ölçümü
eval/                  test senaryoları (head_, chat_, emir_, profile_scenarios.json)
docs/                  entegrasyon sözleşmesi, taksonomi, model ölçümleri, teslim taslakları (docs/teslim/)
data/                  raw/ (toplayıcı çıktısı) ve processed/ (ara ürünler, ölçüm sonuçları); git dışında
```

## Veri ve yeni korpus

Toplayıcı çıktısı ortak biçimdeyse (`docs/entegrasyon.md` §3: `id`, `title`, `source`, `url`, `published_at`,
`content`, `content_status`…) dosyaları `data/raw/<ad>/` klasörüne koymak yeter; `Assistant("<ad>")` hepsini okur,
aynı url'yi bir kez alır. Örnek: `data/raw/emir2/` (Emir'in 11 Ekim örneği). Eski biçimdeki `emir` korpusu da okunur.

Yeni korpusu tam hazırlamak için (`--corpus <ad>`; önce `--estimate` ile maliyete bak):

```
python scripts/hazirlik/build_summaries.py  --corpus emir2    # özetler  → data/processed/article_summaries_emir2.json
python scripts/hazirlik/build_dictionary.py --corpus emir2    # sözlük   → data/processed/keyword_dict_emir2.json
python scripts/hazirlik/build_vectors.py   --corpus emir2    # vektörler → data/processed/article_vecs_emir2.json
```

Üçü de yarıda kesilirse kaldığı yerden devam eder (`scripts/hazirlik/toplu.py`). Bunlar yoksa asistan yine çalışır: özet yerine metnin başını gösterir, anlamsal arama yerine anahtar kelimeyle arar.

## Betikler

Kredi harcayan betiklerde `--estimate` (yalnız maliyet tahmini) ve çoğunda `--dry-run` (sahte modelle tesisat
testi) ücretsizdir; bayraksız çalıştırma gerçek çağrı yapar. Her betiğin başındaki açıklamada kullanım ve çıktı yolu yazar.

| Betik | Ne yapar | Kredi |
|---|---|---|
| **`scripts/hazirlik/`** | | |
| `list_nebius_models.py` | bağlantıyı doğrular, model listesini çeker | — |
| `build_summaries.py` | her haber için kısa özet | ✓ |
| `build_dictionary.py` | korpustan anahtar kelime sözlüğü | ✓ |
| `build_vectors.py` | arama vektörleri (anlamsal arama için) | çok az |
| **`scripts/olcum/`** | | |
| `eval_head.py` | baş model adaylarını senaryolarla dener (iğne, karşılaştırma, uydurmama, tool hatası, injection) | ✓ |
| `eval_chat.py` | çok turlu sohbet: baş model + yedek + doğrulayıcı, akış ve gecikme | ✓ |
| `e2e_assistant.py` | uçtan uca son test, doğrudan `Assistant.ask` üzerinden (~5 sent); `--profil`: kişiye özel bağlam senaryoları | ✓ |
| `eval_verifier.py` | doğrulayıcı, sayısı bozulmuş cevapları yakalıyor mu | ✓ |
| `calibrate_threshold.py` | anlamsal arama eşiğini kalibre eder (yalnız sorgu embedding'i) | çok az |
| **`scripts/subtag/`** | | |
| `etiketle.py` | haberleri alt etiketlere ayırır (tür / konu / bayrak), ürünün sınıflandırıcısıyla; `--estimate` ve `--report` ücretsiz | ✓ |
| `make_labeling_sheet.py` | altın set etiketleme dosyasını hazırlar | — |
| `second_annotator.py` | ikinci LLM etiketleyici; `compare` uyumu ve uzlaşı setini çıkarır | `label` ✓ |
| `silver_audit.py` | gümüş setten 15 haberlik kör denetim | — |
| `eval_classifier.py` | sınıflandırıcıyı etiket seti v2'ye karşı ölçer (`--report` ücretsiz) | ✓ |

Etiket tanımları `src/orchestrator/taxonomy.py`'de, kurallar `docs/taksonomi.md`'de. Haber gelince etiketi
`ingest()` içindeki sınıflandırıcı üretir; bir korpusu topluca etiketlemek için `scripts/subtag/etiketle.py`
(ör. `--corpus emir --limit 20`, 20 haber ≈ 0,4 sent). Diğer `subtag/` betikleri etiketlerin doğruluğunu kurmak ve ölçmek içindir.

## Dokümanlar

- `docs/entegrasyon.md` — sunucu ve arayüz için sözleşme (fonksiyonlar, olaylar, veritabanı alanları)
- `docs/taksonomi.md` — etiketler (tür/konu/bayrak), sınır kuralları, etiket seti v2
- `docs/model-eval-2026-10-10.md` — model seçimi ve ölçümler
- `docs/ornek-sohbet.md` — gerçek modellerle bir soru-cevap örneği (12 Ekim)
- `docs/teslim/` — Devpost metni, demo videosu senaryosu, geri bildirim, teslim takvimi (taslak)

## Lisans

Apache License 2.0 — bkz. `LICENSE`.
