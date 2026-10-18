# Model değerlendirmesi — 2026-10-10

Tüm ölçümler Automotive altın setinde (16 haber, temiz metin). sampleNews'in geri kalanı kullanılmadı: 104 haberin 36'sında metin alanı bot duvarı veya çıkarım hatası.
Sayılar küçük örneklemden (16 haber, senaryo başına 1–2 koşu); eğilim gösterir, kesin hüküm değildir.

## 1. Sınıflandırma (iki eksen: tür | konu)

Kategori açıklamaları altın etiketlere bakılarak yazıldı (taslak) → skorlar iyimser.

| Model | Düşünme | tür /16 | konu /16 | Medyan | 1000 haber ≈ |
|---|---|---|---|---|---|
| gpt-oss-120b | açık | 14 | 15 | 0,8 s | 0,19 $ |
| DeepSeek-V4-Flash | açık | 14 | 14 | 1,9 s | 0,14 $ |
| **Nemotron-3-Nano** | açık | 13 | 15 | 2,8 s | **0,10 $** |
| GLM-5.3-Flash | açık | 14 | 13 | 4,4 s | 0,24 $ |
| Nemotron-3.5-Lightning | açık | 12 | 15 | 9,5 s | 0,43 $ |
| Laya (yerel; denendi, projeden çıkarıldı) | — | 10 | 11 | 0,15 s | 0 |

Düşünme açık modeller 27–29/32, düşünmesiz 20–24/32. Seçim: Nemotron-3-Nano (düşünme açık), ikinci görüş gpt-oss-120b.

## 2. Baş model (ajan, tool çağırma)

Düzenek: `scripts/olcum/eval_head.py`, senaryolar `eval/head_scenarios.json`, tool'lar `src/orchestrator/tools.py`.
Korpus ≈16K token → uzun bağlam değil, çok adımlı uzun görev ölçüldü.

Pilot (EV haberlerini özetle): K3 ve K2.6 tek `konu` filtreli aramayla 4 çağrıda çözdü; DeepSeek-V4-Flash/Pro, MiniMax-M3, GLM-5.3-Flash geçti; Nemotron-3-Super ve Qwen3.5-397B kaldı (Türkçe aramada vazgeçti / sayfalamadı).

Uç durumlar (elle FP incelemesinden sonra):

| | iğne | karşılaştırma | uydurmama | tool hatası | injection | tüm korpus | maliyet |
|---|---|---|---|---|---|---|---|
| Kimi-K3 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (küçük eksik) | ~31 sent |
| DeepSeek-V4-Flash | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (en eksiksiz) | ~1 sent |
| Kimi-K2.6 | ⚠ cevap `reasoning` alanında | ✓ | ✓ | ⚠ 2 hatadan sonra bıraktı | ✓ | ✓ (eksik) | ~9 sent |

## Tasarım çıkarımları

- Yeniden deneme tool katmanında kodla yapılır, modele bırakılmaz.
- Boş `content` + dolu `reasoning` dönen cevap yakalanıp yeniden denenir.
- Modeller Türkçe soruda önce Türkçe arıyor; korpus İngilizce → çok dilli arama ya da korpus dili bildirimi (deneyle karar verilecek).
- Otomatik kontroller kaba: "geçti" sütunu elle okunmadan kullanılmaz (s5 ve s6'da yanlış "geçti" çıktı).

## 3. Arama, sohbet ve okuma maliyeti (aynı gün, devam)

- **Arama:** "korpus İngilizce" ipucu + Qwen3-Embedding anlamsal arama, eşik 0,46 (13 sorguluk kalibrasyon) ve anahtar kelime eşleşmesiyle birleşim. Eşiksiz anlamsal arama "sonuç yok" demediği için modeli gereksiz aramaya itiyordu.
- **Sohbet testi** (3 konuşma, 10 tur, doğrulayıcı her turda): V4-Flash ana 10/10, cevap akışta ort. 2,8 s; V4.1-Flash ana 10/10, 4,0 s, ~2 kat maliyet. Yedeğe geçiş iki yönde çalıştı. Karar: ana V4-Flash, yedek V4.1-Flash, doğrulama akış + rozet.
- **Doğrulayıcı rozeti:** bozulmuş sayıların hepsi `contradicted`, yanlış alarmların hepsi `unsupported` çıktı → ✗ çelişki (sert) / ⚠ kaynakta yok (yumuşak).
- **Taksonomi kararı (Bircan):** sektör + satış haberi o sektörün konusuna da girer → konu çoklu etiket olabilir (Taycan satış haberi: `performans-ozel, ev`).
- **"Merak":** okunup kullanılmayan haber 104 okumada 0. Asıl maliyet kapsamı genişletme ve tam metin okumaydı.

| p1 "bu hafta EV haberleri" (V4-Flash) | arama | tam metin | token | kapsam |
|---|---|---|---|---|
| temel (ipucu + eşikli anlamsal) | 4 | 5 | 25,8K | a06, a14 fazla; a09 eksik |
| + a: haber özetleri (Nano) + b: etiket-önce/özet-önce kuralı | 3 | 0 | 6,7K | a06 fazla |
| + d: kullanıcı ilgi alanı (sözlük anahtarı `konu:ev`) | 1 | 0 | 2,2K | tam doğru |

c1 konuşmasında ilk tur 9 tool çağrısı / 11,8 s → 1–3 çağrı / ~5 s. Tur başına en fazla 1 tam metin okundu, bu yüzden okuma bütçesi (c) gereksiz bulundu.
Sözlük (v2): konu/tür anahtarları taksonomiden TR/EN tohumla, özel isimler Nano'dan; kurallar `src/orchestrator/dictionary.py`.

## 4. Emir verisi, sözlük v3, zaman aşımı (aynı gün, akşam)

**Emir verisi** ("Claude" sorgusu, 119 kayıt): 37'si kullanılamaz (scraper hata mesajı metin alanında, bot/çerez sayfaları), 87'sinin tarihi boş, yoğun yakın tekrar. 82 temiz haberle test edildi (`load_corpus("emir")`). Ayrıntı ve teslim şartları: Drive'da "Veri sorunları (v2)". Ek bulgu: Jina çıktısında site menüsü metnin başında kalıyor (Forbes), bu hem özeti hem embedding benzerliğini bozuyor.

| Emir senaryosu (V4-Flash, son ayar) | sonuç |
|---|---|
| e1 haftanın gelişmeleri | doğru, ayrı hikâyeler; özetlerden cevap (0 tam metin) |
| e2 neden yasaklandı | doğru |
| e3 startup programı zaman sırası | eksik: "ücretsiz avantajlar durduruldu" haberi bulunamadı (Forbes metni yalnız site menüsü) |
| e4 Opus 6 (korpusta yok) | uydurmadı |

Hikâye kümeleme (embedding, eşik 0,85; 0,75 farklı hikâyeleri birleştiriyor): bu ölçekte net kazanç yok (e3'te token yarıya indi, e1/e4'te arttı); tek koşu.
Nebius'ta iki paralel çağrı aynı anda ~3 dk takıldı → çağrı başına zaman aşımı (45 s) + yedeğe geçiş eklendi.

**Sözlük v3** (alt ajanın çökme raporu üzerine): katlamalı normalize (I/İ→i, Türkçe harf→ASCII), kök + Türkçe ek zinciri doğrulaması ve ünsüz yumuşaması, kısa adlar yalnız büyük harfle ("EV", "VW"), zincirleme birleştirme kaldırıldı, ilgi alanları haber eklemez yalnız sıralar, arama sıralaması RRF, anahtar kelime kanalı kelime sınırlı ("ev" artık "every" ile eşleşmiyor), ön ek indeksi.
Alt ajan test seti: 10/35 → 33/35; geniş testte çöken durum 40 → 16; 50K haberde eşleşme 13,7 s → 10,5 ms/sorgu. Kalan bilinen hatalar: "pazartesi", "samsonite" (kalan kısım tesadüfen ek zinciri), olumsuzluk ("Tesla dışındaki"), finans tickerları.

**Emir verisi, v3 kodla tekrar (4,1 sent):** sözlüksüz 4/4 doğru (e3 artık geçiyor: kelime sınırlı anahtar kelime kanalı "durduruldu" haberini buldu). Sözlüklü koşu token'ı artırdı (e3 13K → 68K): Nano'nun takma adları gürültülü ("claude" 11 anahtara bağlıydı, her "Claude" sorgusu 24 haberi eşiksiz getiriyordu). K4b/K4c kuralları eklendi (belirsiz ve yaygın takma adlar düşer): aynı sorgu artık 2 doğru haber getiriyor. Sözlüklü varyant bu kurallarla henüz yeniden koşulmadı.
