# W.O.F — Yapılanlar Listesi

**Tarih:** 18 Ekim 2026
**Okuyucu:** Ekip, proje yöneticisi. Teknik bilgi gerektirmez.
Bu liste, bugüne kadar W.O.F uygulamasında ve FeedProof sunucusunda yapılan her şeyi kullanıcının gözünden anlatır.

---

## Bir bakışta

| Alan | Ne değişti | En önemli sonuç |
|---|---|---|
| Haber toplama | Sadece kullanıcıların takip ettiği konular aranıyor | Aynı krediyle ~2 kat haber |
| Onboarding | 3 adımlı, ~60 saniyelik kişiselleştirme | Kullanıcı ilk dakikada kendi akışını görüyor |
| Kişiselleştirme | "+" takip, "neden okuyorum" cümlesi, beğeni öğrenmesi | Akış kişinin amacına göre sıralanıyor |
| Yapay zeka modelleri | Daha iyi modellere geçildi | Etiketler ve özetler belirgin şekilde daha iyi, sistem 2-3 kat hızlı |
| Türkçe | Arama ve cümleler Türkçe anlaşılıyor | Türkçe arama isabeti %18'den %59'a çıktı |
| Ana sayfa | "Latest Developments" kartı ve yeni Daily Brief | Kişiye özel son gelişmeler, sıfır Tavily kredisi |
| WAI asistanı | Üç yerden açılıyor, sohbeti WAI başlatıyor | Bir saniyede cevap veren, kaynak gösteren asistan |
| Hata düzeltme | WAI'de yazınca donma sorunu | Çözüldü |

---

## 1. Haber toplama

- ✅ **Sadece ilgilenilen konular aranıyor.** Kimsenin takip etmediği konu için Tavily kredisi harcanmıyor.
- ✅ **Herkes aynı aramayı paylaşıyor.** Bir konuyu 1 kişi de takip etse 1000 kişi de takip etse arama bir kez yapılıyor; maliyet kullanıcı sayısıyla artmıyor.
- ✅ **Her konunun kendi sıklığı var.** Geniş kategoriler 6 saatte bir, temel alt konular günde bir, çok özel konular iki günde bir aranıyor.
- ✅ **Az haber getiren aramalar seyrekleşiyor.** Bir konu sürekli boş dönerse daha az aranıyor; haber gelmeye başlayınca normale dönüyor.
- ✅ **Kredi koruması.** Kalan kredi 150'nin altına inecekse otomatik toplama duruyor, demo için kredi kalıyor.
- ✅ **Birden fazla Tavily hesabı.** Bir hesabın kredisi bitince sistem kendiliğinden sıradakine geçiyor. İkinci anahtar geldiğinde eklemek yeterli.
- ✅ **Gerçek kredi takibi.** Tavily'nin kendi sayacı saatlerce takılabildiği için sistem harcamayı kendisi de sayıyor.
- ✅ **Çöp sayfa filtresi.** Borsa fiyat sayfaları, iş ilanları, ana sayfalar ve etiket sayfaları daha veritabanına girmeden eleniyor.
- ✅ **Arama ifadeleri test edildi.** Sade ifadelerin ("fintech", "new AI models"), süslü ifadelerden ("latest news and developments in…") daha iyi sonuç verdiği küçük deneylerle ölçüldü.
- ✅ **Anında haber.** Kullanıcı ilgi alanlarını kaydedince, o konularda haber azsa hemen arama yapılıyor.

**Sonuç:** Bir Tavily kredisiyle gelen haber ~3,4'ten ~6,3'e çıktı. Gereksiz fiyat sayfaları %7'den %0,7'ye indi.

---

## 2. Onboarding ("ilk 60 saniye")

- ✅ **1. adım: Seçim.**
  - Kategori seçmek zorunlu, alt konu seçmek isteğe bağlı (en fazla 12).
  - "+" ile kendi takip ettiği şeyler eklenebiliyor (bkz. 3).
  - "Neden haber okuyorsun?" cümlesi isteğe bağlı (bkz. 4).
- ✅ **2. adım: Beğeni testi.** Farklı kategorilerden 8 haber kartı sağa ya da sola kaydırılıyor. Sistem bu beğenilerden hemen öğreniyor.
- ✅ **3. adım: Sonuç.** "Your Feed is ready" ekranı, kişiye göre sıralanmış haberleri ve her haberin neden seçildiğini ("Because you follow …") gösteriyor.
- ✅ **"Aha anı" hazırlığı.** Kullanıcı onboarding'i bitirirken ana sayfadaki "Latest Developments" kartı arka planda yazılıyor; ana sayfaya geldiğinde hazır bekliyor.
- ✅ **Gereksiz harcama kaldırıldı.** Onboarding'deki canlı web araması, kredi harcayıp sonucu kaydetmediği için çıkarıldı.

---

## 3. "+" ile takip

- ✅ Kullanıcı bir şirket, ürün, kişi ya da konu yazıp takip edebiliyor (ör. Revolut, Steam Deck, Kuantum fiziği); en fazla 3 tane.
- ✅ Takip edilen şey hakkındaki haberler akışta öne çıkıyor.
- ✅ Kelime haberde birebir geçmese bile anlamca ilgiliyse yakalanıyor. Örneğin "Quantum Physics" takip edene kuantum deneyleri haberleri geliyor.
- ✅ Haberin altında "Because you follow Revolut" gibi bir gerekçe görünüyor.
- ✅ Yeni bir şey takip edilince sistem onunla ilgili haberleri hemen aramaya başlıyor.

---

## 4. "Neden haber okuyorsun?" cümlesi

- ✅ Onboarding'de isteğe bağlı bir soru: *"What should your feed help you with?"*
- ✅ Hazır örnekler: *I invest*, *I build products*, *I study this*, *I just follow the news*.
- ✅ Cümle Türkçe de yazılabiliyor.
- ✅ Akışın sıralamasını değiştiriyor. Örneğin "yatırım yapıyorum, yapay zeka şirketlerinin halka arzlarını takip ediyorum" diyen kullanıcının akışının başına halka arz ve fonlama haberleri geliyor.
- ✅ Ana sayfa kartının ve WAI'nin cevaplarının tonunu da etkiliyor.
- ✅ Profilde görünüyor ve değiştirilebiliyor.

---

## 5. Kişiselleştirme ve akış

- ✅ **Kişisel akış.** Haberler kullanıcının kategorilerine, alt konularına, takiplerine, cümlesine ve beğenilerine göre puanlanıyor.
- ✅ **Eşleşme rozeti.** Her haberde "%90 match" gibi bir rozet var.
- ✅ **Beğeni ve beğenmeme.** Sağa kaydırma beğeni, sola kaydırma "bana göre değil" ("NOPE"). İkisi de sistemin öğrenmesini etkiliyor; beğenilmeyen haber akıştan çıkıyor.
- ✅ **Öğrenilen ilgiler profile yansıyor.** Beğenilen haberlerin konuları profile ekleniyor.
- ✅ **Profil düzenleme.** İlgi alanları, takipler ve cümle profilden değiştirilebiliyor. Değişiklikten önce öğrenilmiş ilginin sıfırlanacağı uyarısı çıkıyor.

---

## 6. Yapay zeka modelleri yenilendi

Takımın yapay zeka sorumlusunun demo projesindeki modeller kendi sistemimizde ölçüldü ve daha iyi olanlar alındı. Haber doğrulama (Tavily ile) bizim sistemimizde kaldı.

- ✅ **Haberleri etiketleme ve özetleme.** Eskiden bilgisayarda çalışan küçük bir model vardı (Laya). Yerine NVIDIA'nın Nemotron-Nano modeli geldi.
  - Bağımsız bir yapay zeka hakemi iki sistemi kör olarak karşılaştırdı ve 29 haberin etiketlerinde 23'ünde, özetlerinde 24'ünde yeni sistemi seçti.
  - Doğru kategori 21/29'dan 28/29'a çıktı.
  - Özetler 2 kısa cümleye (~45 kelime) sığdırılıyor.
- ✅ **Konu dışı eleme.** İş ilanları, fiyat sayfaları ve yerel etkinlikler ayrı bir kontrolle eleniyor. Bu kontrol "gerçek haberi kaçırmamaya" ayarlandı: elle hazırlanmış 49 gerçek haberden sadece 1'ini eledi.
- ✅ **Sayfa menüsü temizliği.** Bazı sitelerde metnin başı tamamen menüydü ve yapay zeka haberi göremiyordu. Artık metin haberin başlığından başlatılıyor.
- ✅ **Anlam haritası (arama ve kişiselleştirmenin temeli).** Sadece İngilizce anlayan eski modelin yerine çok dilli Qwen modeli geldi. Türkçe arama artık çalışıyor.
- ✅ **Öğrenilenler korundu.** Model değişirken kullanıcıların beğeni geçmişi yeni sisteme aktarıldı; kimsenin öğrenilmiş ilgisi kaybolmadı.
- ✅ **Bütün haberler yeniden işlendi.** Veritabanındaki haberler yeni modellerle baştan etiketlendi ve özetlendi.
- ✅ **Hız ve bellek.** Bir haberin işlenmesi ~17 saniyeden ~7 saniyeye indi ve artık 4 haber aynı anda işleniyor. Sunucu bilgisayarda ~2,5 GB yerine ~250 MB bellek kullanıyor.
- ✅ **Eski sisteme dönüş mümkün.** Talha isterse eski modelleri bir ayarla geri açabiliyor.

---

## 7. Ana sayfa: "Latest Developments" ve "Daily Brief"

**Önceki durum:** Üstte tek bir haber ("Top Story") vardı. Yanındaki "Daily Brief" tek bir haberin internet doğrulamasıydı; her açılışta ~13 Tavily kredisi harcıyor ve ~1 dakika sürüyordu.

**Şimdi:**
- ✅ **Sol kart, "LATEST DEVELOPMENTS":** Yapay zeka (DeepSeek), kullanıcının en önemli 8 haberinden kısa bir **başlık** ve 3-4 cümlelik bir **"son gelişmeler" paragrafı** yazıyor.
  - Başlık en fazla 70 karakter; kartta 3 satırı geçmiyor.
  - Kullanıcının konularına ve "neden okuyorum" cümlesine göre yazılıyor.
  - Sadece haberlerde yazanı kullanıyor, kendinden bilgi eklemiyor.
- ✅ **Sağ kart, "Daily Brief":** O 8 haberin her birinin kısa özeti. Habere tıklanınca haber açılıyor.
- ✅ **"Ask WAI about this" düğmesi:** Kartın üstüne WAI ile sohbet açılıyor (bkz. 8).
- ✅ **"Picked for you":** Bu 8 haberden sonraki haberlerle devam ediyor; aynı haber iki kez görünmüyor.
- ✅ **Hız ve maliyet:**
  - İlk yazım ~2 saniye sürüyor; sonraki girişlerde kart anında açılıyor.
  - Haberler değiştikçe kart arka planda yenileniyor; ilgi alanları değişince hemen yeniden yazılıyor.
  - Kart başına maliyet ~0,02 cent. **Tavily kredisi harcanmıyor.**

---

## 8. WAI asistanı yenilendi

- ✅ **Üç giriş noktası.** WAI artık üç yerden açılıyor ve **sohbetin ilk mesajını WAI kendisi yazıyor:**
  1. **Haber kartından** ("Ask WAI"): WAI haberin tam metnini okuyor.
     > *"Polygon CEO says the Coinme deal marks its entry into payments… Want me to break down what this means for Polygon's ecosystem and users?"*
  2. **Ana sayfadaki Latest Developments kartından:** WAI kartı ve 8 haberi okuyor.
     > *"I've gone through your latest developments. The most striking threads are… Want me to summarize the key aspects or dig deeper into one of these?"*
  3. **Menüdeki WAI sekmesinden:** Kullanıcı önce bir alan seçiyor. WAI o alanın son haberlerini okuyup sohbeti açıyor.
- ✅ **Alan seçimi üç boyda.**
  - Büyük: kullanıcının seçtiği ana alanlar.
  - Orta, hepsi aynı boyda: kullanıcının seçtiği alt konular.
  - Küçük: diğer bütün alanlar ve alt konular.
- ✅ **Kaynak gösterme.** Sağ panelde "What WAI read" listesi var; WAI'nin cevaplarındaki [1], [2] numaraları bu listedeki haberlere karşılık geliyor. Habere tıklanınca haber açılıyor.
- ✅ **Kısa cevaplar anlaşılıyor.** WAI açılışta "özetleyeyim mi?" diye sorduğu için kullanıcının "evet" demesi yetiyor.
- ✅ **Türkçe.** Açılış İngilizce; kullanıcı Türkçe sorarsa WAI Türkçe cevaplıyor.
- ✅ **Dürüstlük.** WAI sadece okuduğu haberlerden cevap veriyor, bilmediğini söylüyor.
- ✅ **Duruma göre öneriler.** Haber sohbetinde "Simplify this, Why does it matter?…", diğerlerinde "Summarize the most striking, What matters most for me?…".
- ✅ **Hız ve maliyet.** Sohbet ~1 saniyede açılıyor, cevabın ilk kelimesi ~0,7 saniyede geliyor. Mesaj başına maliyet ~0,03-0,06 cent; eski sohbetin yarısından az.
- ✅ **Okunur cevaplar.** Madde ve kalın yazı düzgün görünüyor.
- ✅ **Cevap gelirken yazmaya devam.** WAI cevap verirken bir sonraki soru yazılabiliyor.

---

## 9. Düzeltilen hatalar

- ✅ **WAI'ye yazınca donma.** Geliştirme modunda (`flutter run`) WAI'ye soru gönderilince sayfa donuyordu; eski sohbet ekranında da aynı sorun vardı.
  - **Sebep:** Soru gönderilince yazma kutusu kilitleniyordu ve Flutter bunu hata olarak görüp sayfayı durduruyordu.
  - **Nasıl bulundu:** Uygulama görünmez bir tarayıcıda otomatik olarak dört farklı şekilde çalıştırılıp test edildi; sorun sadece geliştirme modunda çıktı.
  - Çözüldü ve aynı ortamda tekrar denendi.
- ✅ **"Neden okuyorum" boşken bozuk cümle.** Kullanıcı alt konu seçmediğinde sistemin kendi kurduğu cümle "…focused on ." diye yarım kalıyordu; düzeltildi.
- ✅ **Bağlantı sorunu.** Uygulama Windows'ta sunucuya bağlanırken önce IPv6'yı deniyordu; doğrudan adrese geçildi.
- ✅ **Paylaşım linkinin kopması.** Paylaşım tüneli kendini yeniden açarken bazen rastgele bir adres alıyordu ve link çalışmıyordu. Artık doğru adresi alana kadar tekrar deniyor.

---

## 10. Paylaşım, belgeler ve testler

- ✅ **Paylaşım.** Uygulama ve sunucu internetten erişilebilir: https://wof-rss-ui.loca.lt (ilk girişte tünel şifresi soruluyor).
- ✅ **Talha'ya teknik rapor:** `WOF_Teknik_Rapor_Talha.md`
- ✅ **Yapılacaklar raporu (teknik olmayan):** `WOF_Yapilacaklar_Raporu.md`
- ✅ **Otomatik testler.**
  - Sunucuya 35 yeni test eklendi.
  - Flutter'da 71 testin hepsi geçiyor.
- ✅ **Geri alınabilirlik.** Haberlerin eski etiketlerinin yedeği alındı. Eski modellere dönüş ayarla mümkün.

---

## Rakamlarla bugün

| | Önce | Şimdi |
|---|---|---|
| Bir Tavily kredisiyle gelen haber | ~3,4 | **~6,3** |
| Fiyat/borsa sayfası oranı | %7 | **%0,7** |
| Doğru kategori (29 haberlik test) | 21 | **28** |
| Haber işleme süresi | ~17 sn | **~7 sn** (4 paralel) |
| Türkçe aramada ilk 5 isabet | %18 | **%59** |
| Ana sayfa açılışında Tavily kredisi | ~13 | **0** |
| Sunucunun belleği | ~2,5 GB | **~250 MB** |
| WAI ilk cevap süresi | — | **~0,7 sn** |
| Veritabanındaki haber | — | **348** |
| Kalan Tavily kredisi (aylık 1000) | — | **710** |

---

## Sırada

1. **Yapılanları kayıt altına almak.** Bugünkü işler henüz sadece bu bilgisayarda; GitHub'a göndermeden yerel bir kayıt noktası oluşturulmalı.
2. **Eski çöp kayıtları temizlemek.** Yeni filtreden önce gelmiş birkaç gereksiz sayfa var; test kullanıcıları da silinecek.
3. **"Verify this story" düğmesi.** Tavily ödülü için doğrulamayı jüriye görünür kılmak.
4. **Jüri öncesi hazırlık.** Toplu haber çekimi ve kalıcı demo adresi.
5. **Karar bekleyen:** Onboarding sonunda kullanıcı ana sayfaya mı gitsin?
6. **Talha'da:** Arayüz çevirisi (TR/DE/NL) ve rapordaki sorular.
