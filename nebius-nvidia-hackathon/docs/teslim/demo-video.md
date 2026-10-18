<!-- TASLAK (Claude, 2026-10-10). 3 dakikanın altında demo videosu senaryosu. Ludi'nin arayüzü hazır olunca çekilir;
hazır değilse aynı akış terminalden (scripts/olcum/e2e_assistant.py olayları) gösterilebilir. Sorular, test edilmiş
senaryolardan (eval/chat_scenarios.json, eval/emir_scenarios.json) — demoda canlı davranış küçük farklılık gösterebilir;
çekimden önce bir kez prova edin. -->

# Demo video script (target 2:45)

| Time | Screen | Voice-over (EN) |
|---|---|---|
| 0:00–0:15 | Title card + a messy news feed (duplicates, cookie walls) | "Twenty outlets, one story, half of it noise. And chatbots that sound sure even when they're wrong." |
| 0:15–0:35 | UI: pick interest chip **"electric vehicles"**, type in Turkish: *"Bu hafta elektrikli araçlarla ilgili haberleri kısaca listele."* | "Ask in your language. Our agent searches English news and streams the answer." |
| 0:35–0:55 | Status line "Searching: electric vehicle" → answer streams with citations `[a00] [a13] [a15]`, source list underneath | "Every sentence points to its source. It read short summaries first and opened full articles only when needed." |
| 0:55–1:20 | Badge appears: **⚠** → click → claim: *"the new Seagull starts at about $10,000"* | "Then NVIDIA Nemotron-3-Super checks each claim against the full article. Here it caught a real mistake: $10,000 is the old model's price." |
| 1:20–1:40 | Follow-up: *"BYD olanı biraz daha aç; Çin'deki fiyatı ne?"* → answer with 69,900 yuan, ✓ badge | "Follow-ups keep context — and this time everything checks out." |
| 1:40–1:55 | *"Yanlış hatırlamıyorsam Taycan 18.699 sattı, değil mi?"* → "No, 8,699 [a09]" | "It won't just agree with you." |
| 1:55–2:10 | *"Ferrari bu yıl kaç araç sattı?"* → one-sentence "not in the news" | "And when the answer isn't in the news, it says so — no invention." |
| 2:10–2:30 | Architecture slide (table from devpost.md) | "Nemotron-3-Nano labels, summarizes and extracts entities for every article; DeepSeek answers; Nemotron-3-Super verifies — all on Nebius Token Factory, for a fraction of a cent per question." |
| 2:30–2:45 | Numbers slide: 79% / 88% classification, 6/6 contradictions caught, 2–3 s first text | "Measured, not guessed. Try it at [demo URL]." |

Prova notları:
- Demo korpusu: otomotiv (16) + Emir teknoloji haberleri (82). Bu sorular otomotiv korpusunda test edildi.
- ⚠ rozeti her koşuda aynı iddiayı yakalamayabilir; çekimde yakalayan bir koşu seçin ya da kayıtlı bir koşuyu gösterin.
- Süre sınırı 3 dakika; 2:45 hedefi pay bırakır.
