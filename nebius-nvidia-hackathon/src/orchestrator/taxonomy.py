"""Taksonominin tek kaynağı: etiket tanımları ve sınır kuralları (docs/taksonomi.md, Bircan kararları 2026-10-10).

Sınıflandırıcı (Nemotron-Nano), ikinci etiketleyici (LLM) ve arayüz aynı tanımları buradan okur.
Tanımlar İngilizce, çünkü modellere gidiyor; etiket adları Bircan'ın.
"""

# Tür = yazının biçimi/amacı, anlattığı olay DEĞİL (v1 tanımları olay cümlesiydi; iki etiketleyici "7 şey" rehberini
# lansman, eleştirel yorumu düzenleme saydı — 2026-10-10 anlaşmazlık analizi). Tanımlar "the article ..." diye başlar.
TUR = {  # ortak tür ekseni, tekli
    "lansman-duyuru": "the article's main purpose is to report an announcement or launch (new product, feature, program, "
                      "plan/quota change, research result)",
    "inceleme-rehber": "the article reviews or compares products, or tells readers how to use or choose something "
                       "(buying guide, how-to, 'N things to try', tips) — even if the product is new",
    "pazar-finans": "the article is mainly about money: sales figures, revenue, prices, funding, market share, stock moves",
    "duzenleme-hukuk": "the article reports a law, regulator action, lawsuit or a rule restricting user behavior "
                       "(usage policy) as news",
    "olay-kriz": "the article reports an incident, failure, security breach, accident, disaster or scandal",
    "gorus-analiz": "the article is opinion, column, commentary, interview, reaction roundup or analysis — even if it "
                    "discusses a launch or a policy",
    "sponsorlu": "the article is an advertorial: promotion paid to appear in another publication",
    "eglence-yasam": "the article is a personal experience, entertainment, culture or event piece",
    "gelisme-haber": "the article reports a plain news development that fits none of the above (election result, "
                     "resignation, appointment, a statement)",
}

KONU = {  # kategoriye özel konu ekseni, çoklu
    "Automotive": {
        "ev": "battery electric vehicles and charging",
        "hibrit": "hybrid powertrains",
        "konvansiyonel": "conventional gasoline or diesel everyday cars",
        "performans-ozel": "supercars, sports cars, luxury and performance brands",
        "bakim-aksesuar": "car care, maintenance products and accessories",
        "otonom-asistan": "self-driving and driver-assistance systems",
        "other": "none of the above",
    },
    "Technology": {
        "yapay-zeka/model-urun": "AI models, AI features and AI products (new models, assistants, integrations, tools built on AI)",
        "yapay-zeka/politika-guvenlik": "AI usage policies, AI safety and alignment, AI misbehavior or misuse",
        "yapay-zeka/is-ticaret": "AI business: programs, pricing, credits, partnerships, revenue of AI companies",
        "yapay-zeka/arastirma": "scientific or research results produced with or about AI",
        "donanim-cip": "chips, processors, memory, semiconductor supply",
        "tuketici-cihaz": "consumer devices: computers, laptops, phones, consoles, gadgets",
        "yazilim-gelistirici": "software, apps, developer tools, open source",
        "bulut-altyapi": "cloud platforms, servers, storage and infrastructure services",
        "guvenlik-gizlilik": "cybersecurity, vulnerabilities, attacks, privacy",
        "platform-sosyal": "social media and online platforms",
        "other": "none of the above",
    },
    "Finance": {
        "kripto-blokzincir": "cryptocurrency, tokens, blockchain, digital assets",
        "borsa-piyasa": "stock market moves, indices, trading",
        "sirket-sonuc": "a company's revenue, earnings or business results",
        "makro-ticaret": "macroeconomics, trade deals, tariffs, interest rates",
        "tuketici-perakende": "consumer brands, retail, restaurants",
        "girisimcilik": "entrepreneurship and founders",
        "other": "none of the above",
    },
    "Politics": {
        "secim-parti": "elections, parties, party leadership",
        "yasama-hukumet": "legislation, government and public agencies",
        "ekonomi-vergi": "taxes, budget, economic policy",
        "dis-politika-catisma": "foreign policy, conflicts, diplomacy",
        "other": "none of the above",
    },
}

FLAGS = {
    "kategori-disi": "the article does not belong to its category at all (e.g. a storm or football story filed under "
                     "Politics); then use konu 'other'",
    "dusuk-kalite": "SEO or speculative filler (e.g. 'Price Prediction 2025-2030'); keep its real tur",
    "birinci-taraf": "the publisher is the subject itself: company blog, press release, a maker presenting their own "
                     "product ('Show HN')",
}

RULES = (  # sınır kuralları 6–11 (docs/taksonomi.md)
    "Rules: tur describes the ARTICLE (its form and purpose), not the event it covers: a guide about a new launch is "
    "inceleme-rehber, a critical commentary on a new policy is gorus-analiz; use the title's framing ('here are 7 "
    "things to try', 'why...', 'what smart people are saying') as strong evidence. "
    "tur is exactly one (the primary nature); konu can be several only if genuinely about each. "
    "gelisme-haber only when no other tur fits; a scandal is olay-kriz. Research results are lansman-duyuru. "
    "First-person pieces: mainly how-to or comparison -> inceleme-rehber; defending a claim -> gorus-analiz; "
    "only an experience or memory -> eglence-yasam. duzenleme-hukuk only for laws, lawsuits, regulators and rules "
    "restricting user behavior; plan, quota or program changes are lansman-duyuru, price or revenue is pazar-finans. "
    "sponsorlu only for paid placement in another publication; a company's own announcement is lansman-duyuru with "
    "flag birinci-taraf."
)


def konu_for(category: str) -> dict[str, str]:
    """Emir verisi teknoloji haberidir."""
    return KONU["Technology" if category == "Emir" else category]


def prompt_for(category: str) -> tuple[str, dict]:
    """Etiketleme sistem prompt'u ve JSON şeması (kategoriye göre konu listesi)."""
    konu = konu_for(category)
    lines = ["You label news articles with a fixed taxonomy. Answer only with JSON matching the schema.", "",
             "tur (exactly one):"] + [f"- {k}: {v}" for k, v in TUR.items()]
    lines += ["", "konu (one or more, from this category's list):"] + [f"- {k}: {v}" for k, v in konu.items()]
    lines += ["", "flags (zero or more):"] + [f"- {k}: {v}" for k, v in FLAGS.items()] + ["", RULES]
    schema = {"type": "object", "additionalProperties": False, "required": ["tur", "konu", "flags"], "properties": {
        "tur": {"type": "string", "enum": list(TUR)},
        "konu": {"type": "array", "items": {"type": "string", "enum": list(konu)}, "minItems": 1},
        "flags": {"type": "array", "items": {"type": "string", "enum": list(FLAGS)}}}}
    return "\n".join(lines), schema
