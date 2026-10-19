# W.O.F — Yapılacaklar Raporu: Bitenler, Kalanlar ve Analiz

**Tarih:** 18 Ekim 2026
**Kapsam:** W.O.F uygulaması (Flutter) ve FeedProof sunucusu
**Okuyucu:** Ekip, proje yöneticisi. Teknik bilgi gerektirmez.

---

## Kısa özet

Bugün planladığımız işlerin büyük kısmı bitti.

- **Haber toplama** artık kendi kendine çalışıyor ve kredi başına neredeyse iki kat haber getiriyor.
- **Kişiselleştirme** için kullanıcılar üç yeni şey yapabiliyor: belirli bir şeyi takip etmek, "neden haber okuyorum" cümlesi yazmak ve Türkçe arama yapmak.
- **Yapay zeka modelleri**, takımın demo projesindeki daha iyi modellerle değiştirildi. Etiketler ve özetler belirgin şekilde iyileşti, sistem hızlandı ve bilgisayarda çok daha az yer kaplıyor.
- **Ana sayfa** yeniden tasarlandı. Kullanıcı girer girmez kendisi için yazılmış bir "son gelişmeler" özeti görüyor; bu, onboarding sonrasındaki "aha anı" olarak tasarlandı.

En önemli açık konular üç tane:
1. Yapılan işlerin hiçbiri henüz kayıt altına alınmadı. Her şey tek bir bilgisayarda duruyor.
2. Tavily ödülü için Tavily'nin jüriye daha görünür olması gerekiyor.
3. Veritabanındaki az ve kısmen "çöp" içerik ilk izlenimi zayıflatabilir.

---

## Rakamlarla bugün

| Konu | Önce | Şimdi |
|---|---|---|
| Bir Tavily kredisiyle gelen haber | ~3,4 | **~6,3** |
| Gelen içerikteki borsa/fiyat sayfası oranı | %7 | **%0,7** |
| Bir haberin işlenme süresi | ~17 sn | **~7 sn** (aynı anda 4 haber) |
| Yapay zekanın haberi doğru kategoriye koyması (29 haberlik test) | 21 doğru | **28 doğru** |
| Türkçe aramada ilk 5 sonucun isabeti | %18 | **%59** |
| Ana sayfa her açıldığında harcanan Tavily kredisi | ~13 | **0** |
| Sunucunun bilgisayarda kapladığı bellek | ~2,5 GB | **~250 MB** |
| Kalan Tavily kredisi (aylık 1000) | — | **730** |

---

## BİTENLER

### 1. Haber toplama baştan düzenlendi

**Önceki durum:** Sistem kimsenin ilgilenmediği konularda bile sabit bir listeyle haber arıyordu. Sorgular kötü yazıldığı için iş ilanları ve borsa fiyat sayfaları da geliyordu, krediler boşa harcanıyordu.

**Şimdi:**
- **Talebe göre arama:** Sadece en az bir kullanıcının takip ettiği konular aranıyor. Maliyet kullanıcı sayısına değil, takip edilen konu sayısına bağlı. İki kişi aynı konuyu takip ediyorsa arama bir kez yapılıyor ve herkes paylaşıyor.
- **Konuya göre sıklık:** Ana kategoriler 6 saatte bir, temel alt konular günde bir, çok spesifik konular iki günde bir aranıyor.
- **Verimsiz sorguların seyrekleşmesi:** Az haber getiren sorgular kendiliğinden daha seyrek çalışıyor.
- **Kredi koruması:** Kalan kredi 150'nin altına inecekse otomatik toplama duruyor. Böylece demo için kredi kalıyor.
- **Çoklu Tavily anahtarı:** Bir hesabın kredisi bitince sistem kendiliğinden sıradaki hesaba geçiyor. İkinci anahtar geldiğinde eklemek yeterli.
- **Anında haber:** Kullanıcı ilgi alanlarını kaydedince, o konularda haber azsa hemen arama yapılıyor. Kullanıcı bunun için beklemiyor.
- **Sorgu dili test edildi:** Sorguların nasıl yazılacağı küçük deneylerle ölçüldü. Sade ifadeler, "son gelişmeler" gibi süslü ifadelerden daha iyi sonuç verdi.

**Sonuç:** Aynı krediyle neredeyse iki kat kullanılabilir haber geliyor ve gereksiz sayfalar neredeyse tamamen kayboldu.

### 2. "+" ile takip

Kullanıcı onboarding'de ya da profilinde kendi istediği bir şeyi yazıp takip edebiliyor; en fazla 3 tane. Bir şirket (Revolut), bir ürün (Steam Deck) ya da bir konu (Kuantum fiziği) olabilir.

- Takip edilen şey haberin başlığında ya da özetinde geçiyorsa haber akışta öne çıkıyor.
- Kelimenin kendisi geçmese bile anlamca ilgiliyse yine öne çıkıyor. Örneğin "Quantum Physics" takip edene kuantum deneyleri haberleri geliyor.
- Haberin altında "Because you follow Revolut" gibi bir gerekçe görünüyor.

### 3. "Neden haber okuyorsun?" cümlesi

Onboarding'e isteğe bağlı bir soru eklendi: *"What should your feed help you with?"* Yanında hazır örnekler var: *I invest*, *I build products*, *I study this*, *I just follow the news*.

- Cümle Türkçe de yazılabiliyor.
- Cümle akışın sıralamasını değiştiriyor. Örneğin "yatırım yapıyorum, yapay zeka şirketlerinin halka arzlarını takip ediyorum" diyen kullanıcının akışının başına halka arz ve fonlama haberleri geliyor.
- Cümle profilde görünüyor ve değiştirilebiliyor.

### 4. Yapay zeka modelleri değiştirildi (demo projesinden)

Takımın yapay zeka sorumlusunun demo projesindeki modelleri kendi sistemimizde ölçtük ve daha iyi olanları aldık. Haber doğrulama bizde kalıyor, çünkü bizim Tavily'li doğrulamamız daha güçlü.

**a) Haberleri etiketleme ve özetleme**
- **Önce:** Bilgisayarda çalışan küçük bir model (Laya) kullanılıyordu. Haberlerin %78'inde emin olamayıp işi zaten başka bir modele devrediyordu.
- **Şimdi:** NVIDIA'nın Nemotron-Nano modeli kullanılıyor, bulutta çalışıyor.
- **Ölçüm:** Bağımsız bir yapay zeka hakemi iki sistemi kör olarak karşılaştırdı. Hakem etiketlerde 29 haberin 23'ünde, özetlerde 24'ünde yeni sistemi seçti.
- **Kısa özet:** Özetler artık 2 kısa cümleye (~45 kelime) sığdırılıyor.
- **Konu dışı eleme:** İş ilanları, fiyat sayfaları ve yerel etkinlikler gibi konu dışı sayfalar ayrıca eleniyor. Bunu yaparken gerçek haberi kaçırmamaya öncelik verildi.
- **Yeniden işleme:** Veritabanındaki tüm haberler yeni sistemle baştan işlendi.

**b) Anlam haritası (aramanın ve kişiselleştirmenin temeli)**
- **Önce:** Sadece İngilizce anlayan bir model kullanılıyordu. Türkçe arama neredeyse hiç çalışmıyordu.
- **Şimdi:** Çok dilli Qwen modeli kullanılıyor. "Kuantum fiziği", "elektrikli araç şarjı" ya da "yapay zeka şirketlerinin halka arzı" yazınca doğru haberler geliyor.
- **Öğrenilenler korundu:** Kullanıcıların beğeni geçmişi yeni modele taşındı, hiçbir kullanıcının öğrenilmiş ilgisi kaybolmadı.

**Bunun bir bedeli var:** Bilgisayardaki yük çok azaldı, ama artık her şey Nebius'un bulut hizmetine bağlı (aşağıda "Analiz" bölümünde).

### 5. Ana sayfa: "Latest Developments" ve "Daily Brief"

**Önce:** Ana sayfanın üstünde tek bir haber ("Top Story") vardı. Yanındaki "Daily Brief" aslında tek bir haberi internette doğrulayan bir rapordu; her açılışta ~13 Tavily kredisi harcıyor ve bir dakika sürüyordu.

**Şimdi:**
- **Sol kart, "Latest Developments":** Yapay zeka (DeepSeek), kullanıcının akışındaki en önemli 8 haberden kısa bir başlık ve 3-4 cümlelik bir "son gelişmeler" paragrafı yazıyor.
  - Başlık en fazla 70 karakter; kartta 3 satıra sığıyor.
  - Yazarken kullanıcının konularını ve "neden okuyorum" cümlesini dikkate alıyor.
  - Sadece haberlerde yazan bilgileri kullanıyor, kendinden bilgi eklemiyor.
- **Sağ kart, "Daily Brief":** O 8 haberin her birinin kısa özeti. Habere tıklayınca haber açılıyor.
- **Hız ve maliyet:**
  - İlk yazım ~2 saniye sürüyor.
  - Sonraki girişlerde kart anında açılıyor; haberler değiştikçe arka planda yenileniyor.
  - Kart başına maliyet ~0,02 cent. Tavily kredisi harcanmıyor.
- **İlk giriş:** Kart onboarding biterken hazırlanıyor. Kullanıcı ana sayfaya geldiğinde hazır bekliyor.

### 6. Diğer bitenler
- **Talha'ya rapor:** O ana kadarki geliştirmelerin raporu yazıldı. Ancak model değişiklikleri ve ana sayfa öncesinde yazıldığı için güncellenmesi gerekiyor.
- **Uygulama paylaşımı:** Talha'nın denemesi için uygulama ve sunucu internetten erişilebilir hale getirildi.
- **Gereksiz kalan iş:** "Laya'yı ekran kartında çalıştır" maddesi artık gerekmiyor, çünkü Laya'nın yerine yeni model geldi.
- **Çözülen iş:** "Daily Brief'in adı ve yeri yanıltıcı" maddesi çözüldü.

---

## KALANLAR

### A. Bizim yapacaklarımız

| # | İş | Neden önemli | Büyüklük |
|---|---|---|---|
| 1 | **WAI sohbetini yenilemek** | Sohbet şu an sadece tek bir haber hakkında konuşabiliyor. Demodaki yöntemle bütün haberlerde arayıp, kaynak gösterip, cevabını kontrol eden bir asistana dönüşecek. | Büyük (en büyük kalan iş) |
| 2 | **Veritabanındaki "çöp" kayıtları temizlemek** | Yeni filtreler gelmeden önce toplanmış birkaç gereksiz sayfa (Instagram sayfası, halka arz takvimi, kripto fiyat sayfası) bazı kullanıcıların Daily Brief'inde görünüyor. Test için açtığımız kullanıcılar da silinecek. | Küçük (dakikalar) |
| 3 | **Talha raporunu güncellemek** | Model değişiklikleri ve yeni ana sayfa raporda yok. | Küçük |
| 4 | **"Verify this story" düğmesi** (öneri) | Tavily ödülü için doğrulamanın görünür olması lazım (Analiz, madde 2). | Orta |
| 14 | **Haber resimleri** | Kartlarda kategoriye göre seçilen 10 sabit stok fotoğraf haberle alakasız (Nvidia haberine rastgele teknoloji fotoğrafı gibi). Haberin kendi kapak resmi, Tavily'den gelen Markdown metnin içinde zaten var; logo, ikon ve küçük resimleri eleyen bir filtreyle 20 haberin 13'ünde doğru kapak bulundu. Ek Tavily kredisi harcanmıyor. Resmi olmayan haberlere kategori rengi ve kaynak logosuyla tipografik kapak. Resim indirilmeyecek, yayıncının adresinden "Photo: kaynak.com" yazısıyla gösterilecek; tek bir ayarla tamamen tipografik kapağa geçilebilecek (karar 15). Kartlar için her haberin detayı ayrıca çekiliyor; Talha ileride liste yanıtına `image_url` eklerse bu ek istekler kalkar. Aynı işte detay penceresindeki Markdown metin de düzgün gösterilecek (linkler tıklanabilir yazıya dönecek, logolar ve menü artıkları silinecek). | Orta (sadece Flutter) |

### B. Senin kararını bekleyenler

| # | Karar | Seçenekler |
|---|---|---|
| 5 | Onboarding'in sonundaki "Open my Feed" düğmesi nereye gitsin? | Şu an akış sekmesine gidiyor. "Aha anı" artık ana sayfadaki kart olduğu için ana sayfaya yönlendirmek daha etkili olabilir. |
| 6 | Onboarding son ekranındaki "60 saniyelik özet" ne olsun? | Haber özetlerini yan yana dizen bugünkü hali kalabilir ya da yerine yeni "Latest Developments" kartı gelebilir. |
| 7 | "Neden okuyorum" cümlesi İngilizceye çevrilmeye devam etsin mi? | Yeni model Türkçeyi doğrudan anlıyor, yani çeviri zorunlu değil. İngilizce hali yine de biraz daha iyi sonuç veriyor. |
| 8 | Bugünkü işler kayıt altına alınsın mı? | GitHub'a göndermeden, sadece bu bilgisayarda bir "kayıt noktası" oluşturmak (Analiz, madde 1). |
| 15 | Haber resimleri gösterilsin mi, yoksa tamamen tipografik kapak mı? | Telif açısından resmi indirmeden göstermek düşük risk ama sıfır değil (özellikle Getty gibi ajans fotoğrafları). Tipografik kapak sıfır risk. İkisi de hazırlanıp demo öncesi yan yana görülerek seçilebilir. Ayrıca detay penceresinde tam metin yerine "özet + kanıt + Read original" gösterilmesi (FeedProof belgesindeki "özet + kaynağa link" ilkesi). |

### C. Başkalarından beklenenler

| # | İş | Kimden |
|---|---|---|
| 9 | İkinci (ve varsa üçüncü) Tavily hesabının anahtarı | Sen / Talha |
| 10 | Veritabanını jüri için doldurmak: tüm konularda tek seferlik haber toplama (~70-80 kredi) | Sen (manuel çalıştıracaktın) |
| 11 | Talha'ya sorular: test verisi gibi duran bazı alt konular, beğeni geri alınınca öğrenilen konuların silinmemesi, ayar dosyasındaki eski model adları | Talha |
| 12 | Arayüzün Türkçe, Almanca ve Hollandaca çevirisi | Talha'ya bırakıldı |
| 13 | Beğenilerden öğrenmenin iyileştirilmesi (eski "Faz C") | Büyük kısmı yeni anlam haritası modeliyle karşılandı; kalan kısım sonraya |

---

## ANALİZ

### 1. En büyük risk: yapılanlar henüz kayıt altında değil
Sunucuda 28 dosya değişti ya da eklendi. Hepsi sadece bu bilgisayarda duruyor; ne yerel bir kayıt noktası var ne de GitHub'da bir kopya. Bilgisayarda bir sorun çıkarsa bütün günün işi kaybolabilir.
**Öneri:** GitHub'a göndermeden, sadece bu bilgisayarda bir kayıt noktası oluşturmak. Talha'ya ne zaman gönderileceği kararı yine sende kalır.

### 2. Tavily ödülü için görünürlük azaldı
Ana sayfanın artık Tavily kredisi harcamaması bütçe açısından doğru oldu. Ama "Best use of Tavily" ödülü için jürinin Tavily'nin ne yaptığını görmesi gerekiyor. Şu an Tavily çoğunlukla arka planda, haber toplarken çalışıyor.
**Öneri:** Haber detayına bir **"Verify this story"** düğmesi eklemek. Kullanıcı bastığında Talha'nın kanıt sistemi haberi internetteki bağımsız kaynaklarla karşılaştırıp sonucu gösterir. Kredi sadece istenince harcanır, özellik de jüriye net biçimde görünür.

### 3. Artık tamamen buluta bağlıyız
Haberleri etiketleme, özetleme, arama ve ana sayfa kartının hepsi Nebius'un bulut hizmetinde çalışıyor.
- **Artısı:** Bilgisayar çok rahatladı (~2,5 GB'tan ~250 MB'a), sistem hızlandı.
- **Eksisi:** Nebius kısa süreliğine çökerse yeni haberler işlenmez ve arama durur. Mevcut haberler ve akış görünmeye devam eder.

Eski yerel sisteme dönüş yolu duruyor ama anında geçiş değil, kısa bir taşıma işlemi gerekiyor. Hackathon için kabul edilebilir bir risk.

### 4. Maliyet artık sorun değil
- **Haber işleme:** 1000 haberi işlemek ~0,5 dolar.
- **Ana sayfa kartı:** 1000 kullanıcı için günde ~1 doların altında.
- **Tavily:** Aylık 1000 kredinin 730'u duruyor. Sadece haber toplama harcıyor ve kredi başına ~6 haber geliyor.

Jüri dönemi rahat geçer. Asıl sınır yine Tavily kredisi, ama kontrol altında.

### 5. İlk izlenim için içerik az
Veritabanında şu an 236 haber var ve bunların 17'si konu dışı olarak elendi. Ana sayfa kartının "vay" dedirtmesi için akışın dolu ve temiz olması gerekiyor.
**Öneri:** Jüriden önce (2) çöp temizliği ve (10) tek seferlik toplu haber çekimi yapılmalı. Talha şimdi deneyeceği için çöp temizliğini hemen yapmak mantıklı olabilir; birkaç dakikalık bir iş.

### 6. Demo altyapısı kırılgan
Paylaşım için kullandığımız ücretsiz tünel hizmeti denemeler için yeterli. Ancak ilk girişte bir şifre ekranı çıkıyor, bağlantı ara sıra kopabiliyor ve bilgisayarın sürekli açık kalması gerekiyor.
**Öneri:** Jüri sunumundan önce kalıcı bir adres planlanmalı (Talha'nın sunucusu ya da daha sağlam bir tünel hizmeti).

### 7. Ürün açısından nerede duruyoruz
Ürün hedefimiz, onboarding'in hemen sonrasında kullanıcının "bu benim için yapılmış" demesiydi. Bugün bunun parçaları tamamlandı:
- **Seçimler:** Kullanıcı kategori, alt konu ve "+" takip seçiyor.
- **Neden:** "Neden okuyorum" cümlesini yazıyor.
- **Hızlı ayar:** Beğeni testiyle akışını hemen ayarlıyor.
- **Sonuç:** Ana sayfada kendisi için yazılmış son gelişmeleri görüyor.

Eksik kalanlar: onboarding'in kullanıcıyı ana sayfaya götürmesi (karar 5) ve sohbet asistanının "biraz daha anlat" diyen kullanıcıya bütün haberlerden cevap verebilmesi (iş 1).

---

## Önerilen sıra

1. **Hemen:** yapılanları kayıt altına almak ve çöp kayıtları temizlemek. İkisi de birkaç dakika sürer.
2. **Talha'nın geri bildirimi:** Denemesinden gelen sorunlar önce düzeltilir.
3. **"Verify this story" düğmesi:** Tavily ödülü için.
4. **Sohbet asistanını yenilemek:** Kalan en büyük iş.
5. **Jüri öncesi:** toplu haber çekimi, kalıcı demo adresi ve son kontrol.
