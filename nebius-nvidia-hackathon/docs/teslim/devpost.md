<!-- TASLAK (Claude, 2026-10-10). Devpost proje sayfası metni. [Köşeli parantezli] yerler takımın dolduracağı ya da
henüz yapılmamış parçalar (arayüz, demo bağlantısı). Track: Best Apps and Agents (Bircan kararı, 2026-10-10). Rakamlar docs/ altındaki
ölçümlerden; ölçeği küçük olduğu (16–134 haber) metinde açıkça yazıyor. -->

# [Project name] — a news assistant that shows its sources and checks its own answers

## Inspiration

News feeds are noisy: the same story appears in twenty outlets, half the scraped pages are cookie walls, and chat
assistants answer confidently even when the source says something else. We wanted an assistant that reads the news for
you in your language, tells you where every sentence comes from, and warns you when a sentence is not backed by the source.

## What it does

- Ask in Turkish (or English) about the week's news — e.g. *"What happened with electric cars this week?"*
- The assistant searches a curated news corpus, reads only what it needs, and streams an answer with citations like `[a13]`.
- A second model checks every claim against the full source text and shows a badge: **✓ verified**, **⚠ not found in the
  source**, **✗ contradicts the source**.
- Users pick interests (e.g. *electric vehicles*); search favors them without hiding other news.
- Every article is labeled on arrival with a two-axis taxonomy — *type* (launch, review/guide, market & finance,
  regulation, incident, opinion, sponsored, lifestyle, plain development) and *topic* — plus flags such as
  *first-party source* (a company writing about itself) and *low quality* (SEO filler).

[Screenshot / GIF of the UI — Ludi]

## How we built it

All models run on **Nebius Token Factory**.

| Step | Model | Why |
|---|---|---|
| Classification, summaries, entity extraction (once per article) | **NVIDIA Nemotron-3-Nano** (reasoning on) | best price/quality in our tests: ~$0.10 per 1,000 articles |
| Answering with tools (search, read article) | DeepSeek-V4-Flash, backup DeepSeek-V4.1-Flash | 6/6 on our edge cases at ~1/30 the cost of the strongest model we tried |
| Claim verification | **NVIDIA Nemotron-3-Super** | caught 6/6 deliberately corrupted numbers |
| Retrieval | Qwen3-Embedding-8B + keyword + a Turkish-aware entity dictionary | Turkish questions over English news |

Design choices that came from measurements, not guesses:
- **Summaries first, full text on demand:** tokens for a typical question dropped from 25.8K to 2.2K.
- **Thresholded semantic search fused with keywords (RRF):** pure embedding search never says "no results", which made
  the agent search endlessly.
- **Streaming answer + verification badge afterwards:** the answer starts appearing in ~1–5 s (longer when the agent
  searches a lot); the badge follows, typically 3–15 s later.
- **Fallback on any error or a 45 s stall** to a backup model.
- **Prompt-injection resistance:** articles are treated as data; in tests all models ignored an instruction planted
  inside an article and even warned the user about it.

Code: [public repo link] · Apache-2.0. Architecture and contracts: `docs/entegrasyon.md`.

## Challenges we ran into

- **Data quality.** A third of scraped articles were bot walls or error messages stored as "content"; one site's first
  13,900 characters were navigation menus, so the summarizer *invented* a summary. We added validation and boilerplate
  stripping before any model sees the text.
- **Evaluation without a large human gold set.** We labeled 134 articles with three independent model families (agreement
  κ = 0.75), resolved disagreements by 2/3 vote, and report results as *agreement with consensus*, not as ground truth.
- **Definitions matter more than models.** Two annotators systematically labeled "7 things to try with Claude in Google
  Docs" as a *launch* instead of a *guide* — because our type definitions described events, not article forms. Rewriting
  definitions as "the article…" fixed it.
- **A verifier needs calibration too.** Its false alarms were all "not found in the source", never "contradicts" — so we
  split the badge into a soft ⚠ and a hard ✗.

## Accomplishments that we're proud of

- 11/11 end-to-end conversation turns passed (multi-turn follow-ups, refusing a user's wrong number, not inventing missing
  facts), and the verifier caught a real error in an answer (a price that belonged to the previous model generation).
- Nemotron-3-Nano reaches the inter-annotator agreement ceiling on our taxonomy (79% overall, 88% on clear cases).
- The whole pipeline costs fractions of a cent per question.

## What we learned

Small, cheap models plus good retrieval and verification beat one large model doing everything; and most failures came
from data and definitions, not from model choice.

## What's next

[Real-time ingestion from RSS + query-based discovery at scale — Talha/Ludi/Emir], Finance and Politics taxonomies with
human-reviewed labels, and story clustering so the same news from 20 outlets reads as one story with 20 sources.

## Built with

Nebius Token Factory · NVIDIA Nemotron-3-Nano · NVIDIA Nemotron-3-Super · DeepSeek-V4-Flash · Qwen3-Embedding-8B ·
Python · [server/UI stack]
