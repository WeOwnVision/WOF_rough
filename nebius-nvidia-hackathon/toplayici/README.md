# Toplayıcı: mecmua_scraper (Emir)

Bir sorgu için haber arar (Hacker News, DuckDuckGo haber/web, Yahoo, Reddit, Qwant), makalelerin tam metnini indirir,
temizler ve ortak çıktı biçiminde (`docs/entegrasyon.md` §3) JSON yazar. Çıktı `data/raw/<ad>/` altına konunca
asistan doğrudan okur (`Assistant("<ad>")`).

```
python -m venv .venv-toplayici && .venv-toplayici\Scripts\pip install -r toplayici/requirements.txt
.venv-toplayici\Scripts\python.exe toplayici/mecmua_scraper.py toyota -o data/raw/emir3/toyota.json
    --gun 7      # yalnız son 7 gün (varsayılan 30)
    --adet 50    # en fazla 50 makale indir (varsayılan 80)
    --tam        # 365 KB örnek sınırını kapat (veritabanına yazarken)
```

## 12 Ekim değişiklikleri (Veri sorunları v3)

İlk commit Emir'in Drive'daki dosyasıdır (değişmemiş); sonraki commit'in diff'i değişiklikleri gösterir.

| | Önce | Şimdi |
|---|---|---|
| Süre (sorgu başına) | 3–4 dk | 10–31 s (toyota, goldman sachs, openai) |
| Tazelik | eleme yok; toyota'da 77 haberin 73'ü 30 günden eski | aramada `timelimit`, indirmeden önce ve sonra tarih süzgeci (`--gun`) |
| Sonuç / indirme | kaynak başına 300, hepsi indiriliyordu | kaynak başına 100, en iyi 80 indirilir (`--adet`) |
| Repo sayfaları | github.com +12 puan bonusu alıyordu | github/gitlab/huggingface elenir, bonus kaldırıldı |
| Paywall/bot aşma (E5) | tarayıcı taklidi + Jina + Google cache + archive.org | yalnız normal istek; alınamayan haber atlanır |
| Google News linkleri | Jina ile açılıyordu | aday listesine alınmaz (JavaScript yönlendirmesi, Jina olmadan açılmıyor) |
| Qwant | `std_requests` tanımsız olduğu için hiç çalışmıyordu | düzeltildi |
| Başarısız makale | bütün zincir ikinci kez deneniyordu | tekrar yok |

Bedeli: Jina ve Google News olmadan bazı sorgularda daha az haber geliyor (openai: son 30 günden 65 → 27).
Son 30 gündeki haber sayısı toyota'da 4 → 7, goldman sachs'ta 7 → 16 arttı. Sorguya özel filtreler (japan, nobel,
stocks, spark…) olduğu gibi duruyor.
