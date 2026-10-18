# Taksonomi: Finance, Technology, Politics (KARAR VERİLDİ 2026-10-10)

*Öneri: Claude. Karar: Bircan, 2026-10-10 (5 açık sorunun beşinde de önerilen seçenek). Etiket tanımları ve sınırlar etiketleme sırasında Bircan tarafından inceltilebilir.*

Kaynak: sampleNews'in temiz haberleri (Finance 12/33, Politics 13/20, Technology 27/35; geri kalanlar bot duvarı) ve Emir'in "Claude" sorgusundaki 82 temiz haber. Örnekler gerçek başlıklardan.

## İlke

Otomotivdeki iki eksen korunur: **tür** (haberin ne tür bir yazı olduğu) | **konu** (neyle ilgili olduğu).

- **Tür ekseni bütün kategorilerde ortak.** Arama ve filtre ("sadece incelemeler", "sponsorlu olmasın") kategoriden bağımsız çalışır, sözlük tohumları da bir kez yazılır.
- **Konu ekseni kategoriye özel.** Konu çoklu etiket olabilir; bu, Taycan kararının genellemesi (sektör + satış haberi o sektörün konusuna da girer).

## Tür ekseni (ortak, 9 etiket)

| Tür | Tanım (LLM açıklaması için taslak) | Örnek |
|---|---|---|
| lansman-duyuru | yeni ürün, özellik, program ya da şirket kararı duyurusu | "Claude Dashboards and Motion", "Deno Is Joining Cloudflare" |
| inceleme-rehber | ürün incelemesi, karşılaştırma, satın alma ya da nasıl-yapılır rehberi | "The Best Mac Desktop to Buy (2026)", "UniFi vs. eero" |
| pazar-finans | satış, gelir, fiyat, yatırım turu, borsa hareketi | "PC shipments tumble over 20%", "Our $445M Series D", "Shein outsells Asos" |
| duzenleme-hukuk | yasa, düzenleyici kurum, dava, kullanım politikası | "Blockchain.com seeks U.S. approval", "Starbucks lawsuit", "Anthropic bans abusive behavior" |
| olay-kriz | kaza, hata, güvenlik açığı, afet, skandal | "Claude AI Sent Police a Fake Murder Tip", "Hurricane Isaias" |
| gorus-analiz | yorum, köşe yazısı, röportaj, analiz | "A16z's Olivia Moore on consumer AI", "Trump's attempt to rename AI…" |
| sponsorlu | reklam ya da sponsorlu ürün tanıtımı | (otomotivdeki Clarke yazıları) |
| eglence-yasam | kişisel deneyim, eğlence, kültür, etkinlik | "I play my PS2 collection upscaled", "3 Netflix documentaries", "Disrupt side events" |
| gelisme-haber | duyuru, kriz, inceleme ya da görüş olmayan düz gelişme (seçim sonucu, istifa, atama) | "Labour sees off Green challenge to win Holborn by-election" |

Otomotivden geçiş: değerlendirme → inceleme-rehber, pazar-satış → pazar-finans, lansman → lansman-duyuru, eğlence-görüş → ikiye ayrılır (gorus-analiz / eglence-yasam). **16 otomotiv etiketinin 2'si** (Question of the Day → gorus-analiz, Clarkson → eglence-yasam) elle yeniden bakılmalı.

## Konu ekseni (kategoriye özel)

**Technology**

| Konu | Örnek |
|---|---|
| yapay-zeka | Emir verisinin tamamı, "The AI is in the computer", "Let your AI agents paint…" |
| donanim-cip | "Gigabyte BIOS … Raptor Lake Next", "PC shipments … chip shortages" |
| tuketici-cihaz | "Dell XPS 13", "Mac Desktop", "iPod", "PS5 Pro equivalent PC" |
| yazilim-gelistirici | "Deno Is Joining Cloudflare", "productivity apps", "self-host on Raspberry Pi" |
| bulut-altyapi | "Microsoft 365 slashes storage", "Amazon Bedrock expands Claude" |
| guvenlik-gizlilik | "check these 3 privacy risks", "Cyber Verification Program" |
| platform-sosyal | "YouTube, Meta, Twitch … livestream", "Orkut", "Dating App Profiles" |
| other | "Scientists who put faith in technology…" |

**Finance**

| Konu | Örnek |
|---|---|
| kripto-blokzincir | "Blockchain.com …", "Tokenization …", "Toncoin Price Prediction" |
| borsa-piyasa | "Stocks making the biggest moves premarket" |
| sirket-sonuc | "OpenAI projected to bring in $20bn less", "Shein outsells Asos" |
| makro-ticaret | "China agrees to 'halve' hybrid car exports to EU", (tahvil faizleri) |
| tuketici-perakende | "Starbucks 'Sugar-Free' lawsuit", "Chick-fil-A" |
| girisimcilik | "Founders Are Told to Chase Easy Markets" |

**Politics**

| Konu | Örnek |
|---|---|
| secim-parti | "Labour sees off Green challenge", "Lib Dem MP quits", "Sinema decision" |
| yasama-hukumet | "Biden's bipartisan winning streak", "coastguard agency chief" |
| ekonomi-vergi | "Tory tax break for banks has cost £6bn" |
| dis-politika-catisma | "Israeli settler attacks … West Bank" |

## Kararlar (Bircan, 2026-10-10)

1. **Tür ekseni ortak**, 8 etiket (sonra 9: kural 6) (yukarıdaki tablo). Otomotivdeki etiketler yeni adlara taşındı; "Question of the Day" → gorus-analiz ve Clarkson bölümü → eglence-yasam önerisi Bircan'ın onayını bekliyor.
2. **Kategori dışı haber yerinde kalır**, `kategori-disi` bayrağı alır; arama bu haberleri o kategoride göstermez.
3. **SEO/spekülatif içerik** türünü korur (ör. pazar-finans), `dusuk-kalite` bayrağı alır ve varsayılan aramada geri plana düşer.
4. **Yapay zekâ alt konulara ayrılır:** `yapay-zeka/model-urun` (yeni model, özellik, ürün), `yapay-zeka/politika-guvenlik` (kullanım politikası, güvenlik, hizalama, olaylar), `yapay-zeka/is-ticaret` (programlar, fiyat, ortaklık, gelir), `yapay-zeka/arastirma` (bilimsel kullanım, araştırma sonuçları).
5. **Tür tekli** (birincil nitelik), **konu çoklu.** Bayraklar (`kategori-disi`, `dusuk-kalite`) üçüncü alan.

**Etiket biçimi:** `[tür | konu1, konu2 | bayrak1, bayrak2]`; bayrak yoksa üçüncü alan boş kalabilir: `[tür | konu]`.

### Sınır kuralları (Bircan, 2026-10-10 akşam — gümüş set etiketlemesindeki 42 belirsizlikten sonra)

6. **9. tür `gelisme-haber`:** duyuru, kriz, inceleme ya da görüş olmayan düz gelişme haberi (seçim sonucu, istifa, parti içi açıklama, atama). Tanım dar: başka tür uyuyorsa o kullanılır; skandal niteliği varsa olay-kriz.
7. **Araştırma/bilim sonucu** → `lansman-duyuru` (konu ekseni `yapay-zeka/arastirma` gibi bilgiyi taşır).
8. **Birinci tekil şahıs yazılar:** nasıl-yapılır/karşılaştırma ağırlıklı → `inceleme-rehber`; bir iddiayı savunuyor → `gorus-analiz`; yalnız deneyim/anı → `eglence-yasam`.
9. **`duzenleme-hukuk` dar:** yasa, dava, düzenleyici kurum ve kullanıcı davranışını kısıtlayan kurallar. Kota/plan/program değişikliği → `lansman-duyuru`; fiyat/gelir → `pazar-finans`.

10. **`birinci-taraf` bayrağı** (Bircan'ın denetimde yakaladığı ayrım): kaynak, haberin öznesi olan kuruluş ya da kişinin kendisi (şirket blogu, basın bülteni, kendi ürününü tanıtan "Show HN"). Tür değişmez (çoğu lansman-duyuru); arayüz "şirketin kendi açıklaması" diye gösterebilir. `sponsorlu` yalnız başka bir yayına ücretle yayımlatılan tanıtımdır.

11. **Tür yazının biçimidir, anlattığı olay değil** (2026-10-10, anlaşmazlık analizi): yeni bir lansmanı anlatan rehber `inceleme-rehber`, yeni bir politikayı eleştiren yazı `gorus-analiz`. Başlıktaki çerçeve ("denenecek 7 şey", "neden…", "uzmanlar ne diyor") güçlü kanıttır.

Sıradaki: altın set etiketlemesi (Bircan; önce ~15 haber ipucusuz, sonra LLM ön etiketi + onay), kategori açıklamaları, `TOPIC_SEEDS` ve sınıflandırıcı ölçümü (Claude).

## Etiket seti v2 (`data/processed/gold_v2.json`, 134 haber; git dışında)

İnsan altın seti değildir; üç bağımsız model etiketinin birleşimidir (Bircan denetimi 2/15'te bırakıldı):

| Durum | Haber | Nasıl |
|---|---|---|
| uzlasi | 103 | Claude alt ajanı (gümüş) ile gpt-oss-120b aynı tür + ortak konu (tür kappa 0,75) |
| cogunluk | 27 | Anlaşmazlıkta Claude / gpt-oss-120b / DeepSeek-V4-Flash, 2/3 çoğunluk (biçim tabanlı tanımlarla, kural 11) |
| cozulemedi | 4 | Üçü farklı (e000, e033, p08, p17); Claude hakemliği, düşük güven |

Ölçümler bu sete karşı "üç model uzlaşısıyla uyum" olarak raporlanır. İnsan onayı için en değerli 10 dakika: `cogunluk` + `cozulemedi` (31 haber).
