# FeedProof · Sohbet aktarım özeti

> Bu dosya, önceki sohbette konuşulan, değerlendirilen ve üretilen her şeyin özetidir. Yeni sohbete bu dosyayı ve `FeedProof_Lansman_Kiti.docx` dosyasını birlikte ekleyin. İlk mesaj olarak şunu yazabilirsiniz: "Bu projeye bu bağlamla devam ediyoruz."

---

## 1. Proje bağlamı

- **Etkinlik:** Nebius × NVIDIA hackathonu
- **Hedeflenen ödül:** "En iyi Tavily kullanımı"
- **Proje:** Tavily API ile geliştirilen, kişiselleştirilmiş bir RSS / haber akışı
- **Temel fikir:** Geleneksel RSS'ten farklı olarak blog feed'lerine bağımlı değil. Arama motoru desteğiyle web'den kullanıcıya özel akış üretiyor.
- **Ek özellik (takımda zaten var):** Karşılaştırma / sentez modülü. Haberin doğruluğunu ölçüyor.
- **Mevcut Tavily kullanımı:** Search ve Extract zaten kullanılıyor.
- **Açık kaynak olacak.** Takım adı da tanıtılmak isteniyor.
- **Çalışma adı:** FeedProof. Slogan: "Your news feed, with receipts." Alternatifler: Receipts, Provena. İsim henüz kesinleşmedi.

---

## 2. İlk fikir değerlendirmesi (özet)

- Fikir güçlü. "RSS'e bağımlı değiliz, ilgi alanını tanımla, web'den akış üretelim" iyi bir hikâye.
- **Ana risk:** "Google Alerts + LLM özeti" gibi algılanmak. Farkı derinlikte göstermek gerekiyor.
- Ödül için Tavily'yi sadece arama motoru gibi kullanmak yetmez. Farklı uç noktaları akıllıca birleştirmek gerekir.
- Önerilen fark yaratan özellikler: geri bildirim döngüsü (beğeni/atlama ile sorgular güncellenir), embedding ile tekrar ayıklama ve kümeleme, "Neden görüyorum?" açıklaması, özetleme/sıralama/embedding için Nebius üzerinde açık modeller.
- Dikkat: API maliyeti ve kota (önbellek, zamanlanmış toplu çalıştırma), sonuç kalitesi/gürültü, demo gecikmesi (önceden ısınmış profil).

---

## 3. Tavily uç noktaları ve projedeki rolleri

| Uç nokta | Ne yapar | Projedeki rolü |
|---|---|---|
| **Search** (`topic: news`, `time_range`) | Web/haber araması | Profilden üretilen çok açılı sorgularla taze haber keşfi |
| **Map** | Bir sitenin tüm sayfa adreslerini listeler | RSS'i olmayan siteleri dünkü listeyle karşılaştırıp yeni yazıyı yakalar ("RSS'siz RSS") |
| **Crawl** | Siteyi gezip içerikleri toplu çeker (ör. sadece `/blog`) | Takip edilen bölümlerden yeni sayfaları toplar |
| **Extract** | Sayfanın tam metnini çeker | Özet, kümeleme, iddia çıkarma için tam metin |
| **Search + `include_domains`** | Belirli alan adlarında arama | Resmi / birincil kaynaklarla doğrulama |
| **Research** | Kendisi çoklu arama yapıp kaynaklı rapor döner | Tartışmalı haberlerde derin doğrulama. Maliyet nedeniyle **sadece kullanıcı "detaylı incele" dediğinde** |

### Doğruluk (karşılaştırma) modülüne eklenecekler
1. Haberden ana iddiayı çıkar, iddiayı farklı sorgularla tekrar Search'e ver ("X doğru mu", "X yalanlandı"). Destekleyen ve çelişen kaynakları ayrı topla.
2. `include_domains` ile resmi kaynaklara (kurum siteleri, ajanslar) ayrı arama.
3. Haberde adı geçen kurumun kendi sitesini Map/Crawl ile kontrol et ("açıklama gerçekten yayınlanmış mı?").
4. Önemli/tartışmalı haberde isteğe bağlı Research.
5. **Puan gösterimi:** "Doğruluk %72" yerine "4 bağımsız kaynak doğruluyor, 1 kaynak çelişiyor, resmi açıklama bulundu" gibi kanıt kartı.

---

## 4. Uçtan uca akış (pipeline)

```
Kullanıcı profili (ilgi alanları, tek cümle)
  → Sorgu üretici (Nebius LLM, çok açılı sorgular)
  → Keşif:  [Tavily Search: news, time_range]  +  [Tavily Map + Crawl: RSS'i olmayan siteler]
  → Tavily Extract (tam metin)
  → Kümele ve sırala (Nebius embedding, tekrar ayıklama, profile göre sıralama)
  → Doğrulama: [Çapraz Search: destek/çelişki] + [Resmi kaynak: include_domains + Map] + [Research: isteğe bağlı]
  → Kişisel akış (özet + kanıt kartı)
  ↻ Beğeni / atlama verisi profili günceller
```

- Doğrulama **haber başına değil, haber kümesi başına bir kez** çalışır. Sonuçlar önbelleğe alınır ve kullanıcılar arasında paylaşılır.
- Demonun en etkileyici anı: "Bu sitenin RSS'i yok ama yeni yazısını yakaladık." (Map + Crawl)

---

## 5. Jüri değerlendirmesi

**Not: 7/10. Kazanabilir ama henüz kazanmış değil.**
Asıl risk: jürinin projeyi "LLM'li haber özetleyici" diye tek cümlede kategorize etmesi. Tek ve keskin bir hikâye gerekiyor.

### Güçlü yanlar
- Tavily'nin 5 uç noktasının hepsine gerçek iş yükleniyor. Ödül kriterine doğrudan oynuyor.
- Doğrulama katmanı, sıradan RSS okuyucularından ayıran en somut özellik.
- Nebius + Tavily birlikte; iki sponsorun da hikâyesi var.

### Kör noktalar
1. **Kaynak bağımsızlığı:** 5 site aynı ajans haberini kopyalamışsa bu 5 bağımsız kaynak değildir. Ölçülmezse yanlış habere yüksek puan verilir. Jürinin ilk zor sorusu bu olur.
2. **Taze haber:** 10 dakikalık haberi doğrulayan kaynak henüz yoktur. "Doğrulanamadı" ile "yanlış" ayrılmalı.
3. **Maliyet patlaması:** Haber başına Search + Extract + 3 doğrulama çağrısı ölçekte kotayı bitirir. Çözüm: önbellek, küme başına tek doğrulama, popüler kümeleri paylaşma.
4. **Soğuk başlangıç:** Yeni kullanıcının ilk akışı vasat olabilir; demo ilk ekranda kaybedilebilir.
5. **Gecikme:** Zincir canlı çalışırsa dakikalar sürer. Demoda önceden hesaplanmış akış şart.
6. **Hukuki/etik:** Crawl ile tam metin çekip özetlemek telif açısından sorgulanabilir. İlke: "özet + kaynağa link".

### Patlayabileceği noktalar (demo riskleri)
- Canlı sorguda alakasız veya boş sonuç.
- Map'te eski sayfanın "yeni yazı" görünmesi (URL slug/sayfalama değişimi yanlış alarm üretir).
- LLM'in iddia çıkarmada uydurma yapıp sahte "çelişki" bulması.

### Fark yaratacak noktalar
- **"Vay" anı:** Gündemdeki gerçek, tartışmalı bir haberde kanıt kartı: "3 bağımsız kaynak doğruluyor, resmi açıklama şu sayfada, 1 kaynak çelişiyor."
- **"RSS'i yok ama takip ediyoruz" anı.**
- **Kaynak bağımsızlığı skoru:** Kopya haberleri aynı kökene bağlayan analiz. ("7 articles ≠ 7 sources.")
- **Tavily kullanım paneli:** Demoda hangi uç noktanın neden çağrıldığını canlı gösteren log.

### Konumlandırma önerisi
"Kişisel RSS" yerine **"kendi haberini doğrulayan kişisel akış"**.

---

## 6. Ana mesajlar (her kanalda aynı)

- **One-liner:** FeedProof is an open-source news feed that works without RSS and shows the receipts for every story.
- **Hook:** RSS died because the web stopped publishing feeds. We rebuilt the feed reader on search, and made every story prove itself.
- **Slogan:** Your news feed, with receipts.
- **İçgörü:** 7 articles ≠ 7 sources.
- **Kural:** Taze haber "unverified yet" olarak etiketlenir, asla "false" değil. Puan değil, kanıt gösterilir.

---

## 7. Üretilen lansman kiti (FeedProof_Lansman_Kiti.docx, 25 sayfa)

Strateji Türkçe, yayınlanacak tüm metinler İngilizce ve kopyala-yapıştır hazır.

1. **Strateji:** konumlandırma, anlatı mimarisi (düşman / içgörü / gösterilebilir an), isim alternatifleri, kitle-mesaj-kanal tablosu, katmanlı hedefler, değişmez kurallar.
2. **Lansman takvimi:** T-3 teaser'lar → T teslim + pitch → T+1 16:30 (İstanbul) ana lansman X + LinkedIn → T+2 Show HN + Reddit → T+3 takım postu → T+4 teknik derin dalış → T+7 sonuç postu → T+30 yol haritası.
3. **GitHub README:** global standart tam Markdown (hero, rozetler, demo GIF, Why, mermaid diyagram, Tavily tablosu, kanıt kartı örneği, Quickstart, yapılandırma, mimari, maliyet, yol haritası, katkı, takım, lisans). Ayrıca About/topics, social preview görseli, LICENSE, CONTRIBUTING, good first issue önerileri.
4. **X:** 9 tweet'lik lansman thread'i, 3 teaser, tekil postlar (teknik, görüş, takım, sonuç), takım üyeleri için 3 farklı açılı alıntı tweet. Kurallar: native video ilk tweet'te, link ilk tweet'te değil, sponsor etiketleri ilk tweet'te.
5. **LinkedIn:** lansman postu + ilk yorum, takım tanıtımı, "3 şey öğrendik" teknik/carousel postu, kişisel paylaşım şablonu, sonuç postu (ödül kazanıldı / kazanılmadı iki versiyon). Link ilk yorumda.
6. **Devpost:** ad, tagline, Inspiration, What it does, How we built it (Tavily uç noktaları tek tek), Challenges, Accomplishments, What we learned, What's next, Built with.
7. **Pitch (3 dk):** zaman kodlu kurgu ve konuşma metni (Hook → Problem → Canlı demo → How → Why it matters → Close), 7 soruluk jüri soru-cevap (Google News/Perplexity farkı, truth score riski, taze haber, halüsinasyon, maliyet, telif, iş modeli), demo güvenliği.
8. **Videolar:** A) 75 sn tanıtım storyboard (16:9 + 9:16), B) 2:30 demo kurgusu (Devpost, ≤3 dk kuralını kontrol edin), C) 15 sn dikey teaser. İlk 2 saniyede hook, altyazı zorunlu.
9. **Takım markası:** GitHub org, tutarlı isim/logo, bio satırı, sabit içerik, takım tanıtım paragrafı, üye biyografi şablonu.
10. **Dağıtım:** Show HN başlığı + yazarın ilk yorumu, Reddit tablosu (r/rss, r/selfhosted, r/opensource, r/LocalLLaMA, r/SideProject), sponsor DM şablonu, uzun kuyruk (awesome listeler, bültenler, Product Hunt, blog), "patlama anında ne yapılır".
11. **Son kontrol listesi.**

### Hedef katmanları (gerçekçi)
| Katman | Görüntülenme | GitHub yıldız | Tetikleyici |
|---|---|---|---|
| Taban | 50–100 bin | 200–500 | Takım + ağ, sponsor etiketleri |
| İyi | 250–500 bin | 1.000–3.000 | Bir sponsor repost, Show HN ön sayfa |
| Patlama | 1 milyon + | 5.000 + | Büyük AI hesabı alıntısı, HN + Reddit birlikte |

Milyon görüntülenme garanti değil. Sahte etkileşim (bot, satın alınmış yıldız) kullanılmayacak.

---

## 8. Açık kalanlar / doldurulacaklar

- Proje adı kesinleşmedi (FeedProof / Receipts / Provena). GitHub org, X handle, domain müsaitliği kontrol edilecek.
- Placeholder'lar: [TAKIM ADI], [GITHUB_URL], [DEMO_URL], [VIDEO_URL], [DEVPOST_URL], [MODEL], teknoloji yığını, üye adları/rolleri.
- Gerçek ölçümler: haber başına Tavily çağrı sayısı, gecikme, kaynak sayıları. Uydurulmayacak.
- Map diff'teki yanlış "yeni sayfa" sorununun çözüm yöntemi ([YÖNTEM]).
- Sponsor hesap adları (@tavilyai, @nebiusai, @nvidia vb.) doğrulanacak.
- Hackathon video süre kuralı kontrol edilecek.

## 9. Önerilen sonraki adımlar

1. Pitch slaytlarını konuşma metnine göre hazırlamak.
2. Kaynak bağımsızlığı (origin tracing) algoritmasını tasarlamak.
3. Kanıt kartı arayüzünü tasarlamak.
4. Profilden Tavily sorgusu üreten prompt'u yazmak.
5. Map diff mantığını (URL filtreleme) netleştirmek.
