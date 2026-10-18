"""Nebius Token Factory istemcisi: .env yükleme, chat çağrısı, maliyet hesabı."""
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE_URL = "https://api.tokenfactory.nebius.com/v1"
MODELS_FILE = ROOT / "data" / "processed" / "nebius_models.json"  # scripts/hazirlik/list_nebius_models.py üretir


def load_env(path: Path = ROOT / ".env") -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def prices() -> dict[str, tuple[float, float]]:
    """model -> (girdi $/token, çıktı $/token)."""
    models = json.loads(MODELS_FILE.read_text(encoding="utf-8"))
    return {m["id"]: (float(m["pricing"]["prompt"]), float(m["pricing"]["completion"])) for m in models}


def cost(model: str, prompt_tokens: int, completion_tokens: int, table: dict | None = None) -> float:
    p_in, p_out = (table or prices())[model]
    return prompt_tokens * p_in + completion_tokens * p_out


class APIError(RuntimeError):
    pass


def chat(model: str, messages: list[dict], tools: list[dict] | None = None, max_tokens: int = 8000,
         timeout: int = 300, stream: bool = False, on_delta=None, **extra) -> tuple[dict, dict, float]:
    """Tek chat çağrısı. Dönüş: (choice, usage, ms).

    stream=True: cevap parça parça okunur; choice["ttft_ms"] = kullanıcıya ilk metnin göründüğü an (yoksa None).
    on_delta(text): akışta her metin parçasında çağrılır (arayüze anında aktarmak için).
    """
    payload = {"model": model, "messages": messages, "max_tokens": max_tokens, "temperature": 0, **extra}
    if tools:
        payload["tools"] = tools
    if stream:
        payload |= {"stream": True, "stream_options": {"include_usage": True}}
    req = urllib.request.Request(f"{BASE_URL}/chat/completions", data=json.dumps(payload).encode(),
                                 headers={"Authorization": f"Bearer {os.environ['NEBIUS_API_KEY']}",
                                          "Content-Type": "application/json"})
    t = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if not stream:
                r = json.load(resp)
                return r["choices"][0], r.get("usage") or {}, (time.perf_counter() - t) * 1000
            choice, usage = _read_stream(resp, t, on_delta)
    except urllib.error.HTTPError as e:
        raise APIError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}") from e
    except (urllib.error.URLError, TimeoutError) as e:  # yanıt gelmezse yedek modele geçilebilsin (run_turn)
        raise APIError(f"timeout/network after {time.perf_counter() - t:.0f}s: {e}") from e
    return choice, usage, (time.perf_counter() - t) * 1000


def _read_stream(resp, t0: float, on_delta=None) -> tuple[dict, dict]:
    """SSE akışını tek bir choice'a topla (içerik, reasoning, tool çağrıları parça parça gelir)."""
    content, reasoning, calls, finish, usage, ttft = [], [], {}, None, {}, None
    for raw in resp:
        line = raw.decode("utf-8").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        chunk = json.loads(data)
        usage = chunk.get("usage") or usage
        for ch in chunk.get("choices") or []:
            delta = ch.get("delta") or {}
            if delta.get("content"):
                if ttft is None:
                    ttft = (time.perf_counter() - t0) * 1000
                content.append(delta["content"])
                if on_delta:
                    on_delta(delta["content"])
            if delta.get("reasoning") or delta.get("reasoning_content"):
                reasoning.append(delta.get("reasoning") or delta.get("reasoning_content"))
            for tc in delta.get("tool_calls") or []:
                slot = calls.setdefault(tc.get("index", 0), {"id": None, "type": "function",
                                                            "function": {"name": "", "arguments": ""}})
                slot["id"] = tc.get("id") or slot["id"]
                fn = tc.get("function") or {}
                slot["function"]["name"] += fn.get("name") or ""
                slot["function"]["arguments"] += fn.get("arguments") or ""
            finish = ch.get("finish_reason") or finish
    message = {"role": "assistant", "content": "".join(content) or None,
               "tool_calls": [calls[i] for i in sorted(calls)] or None, "reasoning": "".join(reasoning) or None}
    return {"message": message, "finish_reason": finish, "ttft_ms": ttft}, usage


def embed(texts: list[str], model: str = "Qwen/Qwen3-Embedding-8B", timeout: int = 120) -> tuple[list[list[float]], int]:
    """Metinleri embedding'e çevir. Dönüş: (vektörler, girdi token sayısı)."""
    req = urllib.request.Request(f"{BASE_URL}/embeddings", data=json.dumps({"model": model, "input": texts}).encode(),
                                 headers={"Authorization": f"Bearer {os.environ['NEBIUS_API_KEY']}",
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            r = json.load(resp)
    except urllib.error.HTTPError as e:
        raise APIError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}") from e
    vecs = [d["embedding"] for d in sorted(r["data"], key=lambda d: d["index"])]
    return vecs, (r.get("usage") or {}).get("prompt_tokens", 0)
