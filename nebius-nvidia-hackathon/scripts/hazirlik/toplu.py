"""Toplu model çağrısı (hazırlık betikleri ortak kullanır): haber başına hata yakalama, ara kayıt, kaldığı yerden devam.

Önceden tek bir haberin zaman aşımı bütün koşuyu düşürüyor, ödenmiş sonuçlar kaydedilmeden kayboluyordu.
"""
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def load_done(path: Path) -> dict:
    """Önceki koşunun sonuçları (yoksa boş): bunlar yeniden istenmez."""
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save(path: Path, data: dict) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")  # yarıda kesilen yazım eski dosyayı bozmasın
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def run_batch(items: dict[str, dict], fn, done: dict, path: Path, workers: int = 8, every: int = 25,
              retries: int = 1) -> tuple[list[dict], list[str]]:
    """fn(item) -> (sonuç, usage). Sonuçlar done[id]'ye yazılır, her `every` haberde bir ve sonda path'e kaydedilir.

    Dönüş: (usage listesi, hata veren id'ler). Hatalı haberler bir sonraki koşuda yeniden denenir.
    """
    def one(aid):
        for attempt in range(retries + 1):
            try:
                return aid, *fn(items[aid])
            except Exception as e:  # zaman aşımı, bozuk JSON, HTTP 5xx…
                if attempt == retries:
                    raise RuntimeError(f"{aid}: {type(e).__name__}: {str(e)[:150]}") from e
                time.sleep(2)

    usages, failed, t0 = [], [], time.perf_counter()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(one, aid): aid for aid in items}
        for i, fut in enumerate(as_completed(futures), 1):
            try:
                aid, result, usage = fut.result()
                done[aid] = result
                usages.append(usage)
            except Exception as e:
                failed.append(futures[fut])
                print(f"  hata: {e}")
            if i % every == 0 or i == len(items):
                save(path, done)
                print(f"  [{i}/{len(items)}] {time.perf_counter() - t0:.0f} s", flush=True)
    return usages, failed
