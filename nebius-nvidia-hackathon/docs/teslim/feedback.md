<!-- TASLAK (Claude, 2026-10-10). Devpost'taki zorunlu "Nebius / NVIDIA geri bildirimi" alanı için. Her madde bu projede
ölçülen ya da yaşanan bir duruma dayanıyor (kanıt: docs/model-eval-2026-10-10.md). Göndermeden önce takım okusun. -->

# Feedback: Nebius Token Factory and NVIDIA open models

We built a news assistant on Nebius Token Factory: NVIDIA Nemotron-3-Nano labels, summarizes and extracts entities from
incoming articles; DeepSeek-V4-Flash answers user questions with tool calls; NVIDIA Nemotron-3-Super verifies every
answer against the source articles. Over one day we made well over a thousand calls to 15 Token Factory models
(14 chat + 1 embedding) for about $1 in total.

## What worked well

- **OpenAI-compatible API.** Our client is ~115 lines of standard-library Python (no SDK). Streaming, tool calling and
  `json_schema` structured outputs worked across Nemotron, DeepSeek and gpt-oss models.
- **`/v1/models?verbose=true` with prices.** Having per-token prices in the model list let us print a cost estimate
  before every experiment. We would love to see this in every API.
- **Price/performance of Nemotron-3-Nano.** For two-axis news classification it matched the agreement level between two
  independent annotators (79% overall, 88% on items where the annotators agreed) at about $0.10 per 1,000 articles.
- **Nemotron-3-Super as a verifier.** In a test with deliberately corrupted numbers it flagged 6/6 as `contradicted`,
  pointing at exactly the corrupted claim, at ~$0.002 per check.
- **Qwen3-Embedding-8B.** Embedding 82 full articles cost $0.001; good cross-lingual retrieval (Turkish queries, English news).

## Issues we hit (with suggestions)

1. **Occasional long stalls.** Two parallel streaming requests to DeepSeek-V4-Flash both waited ~172 s before the first
   byte (other calls that day: 1–10 s). We added a 45 s client timeout and a backup model. *Suggestion:* a public status
   page or a queue/latency hint header so clients can fail over earlier.
2. **Reasoning on/off is not uniform.** `chat_template_kwargs: {"enable_thinking": false}` turned reasoning off for
   Nemotron and DeepSeek models but not for gpt-oss-120b and GLM-5.3-Flash: they spent the whole `max_tokens` budget on
   reasoning and returned empty content. *Suggestion:* document per model which switch works (`enable_thinking`,
   `reasoning_effort`, …) or expose it in `/v1/models`.
3. **Answer in the reasoning field.** Kimi-K2.6 twice returned an empty `content` with the full final answer inside
   `reasoning` (same request, reproducible). Field names also differ between models (`reasoning` vs
   `reasoning_content`). *Suggestion:* consistent separation and field naming.
4. **Capabilities missing in the model list.** `supported_features` was `null` for some models (e.g. DeepSeek-V4.1-Flash),
   so we could not tell from the API whether tool calling is supported. *Suggestion:* always fill it.
5. **Very long reasoning on small models.** Nemotron-3.5-Lightning with reasoning on produced ~1,600 output tokens per
   short classification (9.5 s per item) — more expensive than larger models in practice. *Suggestion:* a documented
   reasoning budget parameter for Nemotron models.
6. **Cost per response.** We computed cost from `usage` and the price list ourselves. *Suggestion:* return the billed
   amount in the response (or a header) — it makes cost-aware agents much easier.

## NVIDIA models: notes

- Nemotron-3-Nano's hybrid Mamba-Transformer design made it our default for every high-volume step (summaries, entity
  extraction, classification). With reasoning on it was clearly more accurate than with reasoning off (28/32 vs 22/32 on
  our test set), at ~2.8 s per article.
- Nemotron-3-Super as a judge: excellent at catching contradicted numbers; it sometimes marks the assistant's own
  process sentences ("the search only returned…") as unsupported. Clearer guidance on claim extraction would help.
