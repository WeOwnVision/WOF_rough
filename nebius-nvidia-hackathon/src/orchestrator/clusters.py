"""Hikâye kümeleme: aynı haberin farklı kaynaklardaki kopyalarını embedding benzerliğiyle birleştirir."""
from .tools import cosine


def cluster(vecs: dict[str, list[float]], threshold: float) -> dict[str, int]:
    """Kosinüs benzerliği eşiği aşan çiftleri birleştirir (union-find). Dönüş: haber -> küme no."""
    ids = sorted(vecs)
    parent = {i: i for i in ids}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if cosine(vecs[a], vecs[b]) >= threshold:
                parent[find(a)] = find(b)
    roots = {r: n for n, r in enumerate(sorted({find(i) for i in ids}))}
    return {i: roots[find(i)] for i in ids}
