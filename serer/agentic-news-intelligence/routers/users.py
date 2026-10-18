import re
from typing import Dict, Any, List, Optional
import numpy as np
import logging
from fastapi import APIRouter, BackgroundTasks, HTTPException

from ai import ai_client, FAST_MODEL
from db import get_db
from embedder import get_embedder, similarity_thresholds
from schemas import UserLoginRequest, UserPreferencesUpdate, UserInteractionRequest
from taxonomy import MACRO_CATEGORIES, clean_micro_tags
from routers.deps import validate_uuid, parse_vector

router = APIRouter(tags=["Users & Personalization"])
logger = logging.getLogger("users_router")

# "+" follows: points for an article that is about something the user follows.
# A passing mention deep in the text does not count; the name must be in the
# title (strong) or the 2-sentence summary. A followed thing also counts like a
# chosen category, so a matching article outside the user's categories gets the
# category points too.
FOLLOW_TITLE_BOOST = 40
FOLLOW_SUMMARY_BOOST = 25
FOLLOW_CATEGORY_POINTS = 20

# Topic-like follows ("Quantum Physics") rarely appear verbatim, so an article
# whose vector is this similar to the follow name also matches (summary-level
# boost). The similarity cut-off belongs to the embedding model
# (embedder.SIMILARITY_THRESHOLDS["..."]["follow_min"]): MiniLM 0.45, Qwen 0.50.

# Optional onboarding "why" sentence ("What should your feed help you with?").
# The interest vector is built from its English version, translated with
# FAST_MODEL when saved: MiniLM only reads English; Qwen3-Embedding reads Turkish
# almost as well (AUC 0.935 vs 0.940) but English is still slightly better.
INTEREST_CONTEXT_MAX_CHARS = 200
CONTEXT_DDL = """
ALTER TABLE users ADD COLUMN IF NOT EXISTS interest_context TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS interest_context_en TEXT;
"""
SYSTEM_PROMPT_TRANSLATE_CONTEXT = (
    "The user wrote, in any language, what they want their news feed to help them with. "
    "Translate it into one natural English sentence and keep its meaning. "
    "If it is already English, return it unchanged. Reply with the sentence only."
)
_context_columns_ready = False

# Characters with special meaning in PostgreSQL regular expressions.
_PG_REGEX_SPECIAL = re.compile(r"([\\.^$*+?()\[\]{}|\-])")


def _follow_pattern(name: str) -> str:
    """Case-insensitive whole-word PostgreSQL regex for a followed name (\\m ... \\M)."""
    clean = " ".join(name.split())
    escaped = _PG_REGEX_SPECIAL.sub(r"\\\1", clean)
    # Word boundaries only next to word characters ("C++" cannot end on \M).
    start = r"\m" if clean[:1].isalnum() else ""
    end = r"\M" if clean[-1:].isalnum() else ""
    return start + escaped + end


def _user_follow_names(cur, user_id: str) -> List[str]:
    """
    Names the user follows (creates the follows table if needed). Follows saved
    before meaning vectors existed get their vector here, once.
    """
    from query_scheduler import FOLLOWS_DDL

    cur.execute("SELECT to_regclass('user_follows') IS NOT NULL;")
    if not cur.fetchone()[0]:
        cur.execute(FOLLOWS_DDL)
        return []
    cur.execute("""
        SELECT id, name, embedding IS NULL FROM user_follows
        WHERE user_id = %s ORDER BY created_at;
    """, (user_id,))
    rows = cur.fetchall()
    missing = [(fid, name) for fid, name, no_vec in rows if no_vec]
    if missing:
        embedder = get_embedder()
        for fid, name in missing:
            cur.execute("UPDATE user_follows SET embedding = %s::vector WHERE id = %s;",
                        (str(embedder.embed_query(name)), fid))
    return [r[1] for r in rows]


def _ensure_context_columns(cur) -> None:
    """Adds the interest-context columns once per process (databases created before them)."""
    global _context_columns_ready
    if not _context_columns_ready:
        cur.execute(CONTEXT_DDL)
        _context_columns_ready = True


def _clean_context(text: str) -> Optional[str]:
    """Trims the user's sentence; None when empty. Too long is a 400."""
    clean = " ".join(text.split())
    if len(clean) > INTEREST_CONTEXT_MAX_CHARS:
        raise HTTPException(
            status_code=400,
            detail=f"interest_context must be at most {INTEREST_CONTEXT_MAX_CHARS} characters"
        )
    return clean or None


def _context_to_english(text: str) -> Optional[str]:
    """English version of the user's sentence for the embedder. None on failure (never raises)."""
    try:
        resp = ai_client.chat.completions.create(
            model=FAST_MODEL,
            temperature=0.0,
            max_tokens=120,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT_TRANSLATE_CONTEXT},
                {"role": "user", "content": text}
            ],
            timeout=20.0
        )
        english = " ".join((resp.choices[0].message.content or "").split()).strip("\"'")
        return english or None
    except Exception as e:
        logger.warning("[Interests] Context translation failed (%s); using the standard sentence.", e)
        return None


def _standard_interest_text(macros: List[str], micros: List[str]) -> str:
    """Sentence built from the chosen topics, used when the user gave no context sentence."""
    text = f"Technical news and updates in {', '.join(macros)}"
    if micros:
        text += f", specifically focused on {', '.join(t.replace('_', ' ').title() for t in micros)}"
    return text + "."


def ema_update(user_vec: Optional[np.ndarray], art_vec: Optional[np.ndarray], itype: str) -> Optional[np.ndarray]:
    """
    Interest vector after one interaction (None = unchanged). Like: EMA attraction
    (+0.15 toward the article); dislike/skip: repulsion (-0.12 away from it).
    Also used by migrate_embeddings.py to replay interactions after a model change.
    """
    if art_vec is None:
        return None
    if itype == "like":
        if user_vec is None:
            return art_vec
        blended = 0.85 * user_vec + 0.15 * art_vec
        norm = float(np.linalg.norm(blended))
        return blended / norm if norm > 0 else blended
    if itype in ("dislike", "skip") and user_vec is not None:
        repelled = user_vec - 0.12 * art_vec
        norm = float(np.linalg.norm(repelled))
        return repelled / norm if norm > 0 else user_vec
    return None


def get_personalized_feed_data(user_id: str, page: int = 1, page_size: int = 20) -> Dict[str, Any]:
    valid_user_id = validate_uuid(user_id, "user_id")
    offset = (page - 1) * page_size

    with get_db() as cur:
        cur.execute("""
            SELECT onboarding_completed, preferred_macro_tags, preferred_micro_tags, interest_embedding
            FROM users WHERE id = %s;
        """, (valid_user_id,))
        user_row = cur.fetchone()
        if not user_row:
            raise HTTPException(status_code=404, detail="User not found")

        onboarding_done, preferred_macros, preferred_micros, user_interest_emb = user_row
        preferred_macros = preferred_macros or []
        preferred_micros = preferred_micros or []

        # Cold-start guardrail: If onboarding incomplete or preferred_macro_tags empty, return chronological fallback
        if not onboarding_done or not preferred_macros:
            cur.execute("""
                SELECT id, source_feed, title, original_url, author, published_at, macro_tag, macro_tags, micro_tags, tldr, image_url, image_status
                FROM articles a
                WHERE a.is_processed = TRUE 
                  AND a.macro_tag IS NOT NULL 
                  AND a.macro_tag != 'Off-Topic'
                  AND (a.on_topic_score IS NULL OR a.on_topic_score >= 0.40)
                  AND NOT EXISTS (
                      SELECT 1 FROM user_article_interactions uai_d
                      WHERE uai_d.user_id = %s
                        AND uai_d.article_id = a.id
                        AND uai_d.interaction_type IN ('dislike', 'skip')
                  )
                ORDER BY a.published_at DESC LIMIT %s OFFSET %s;
            """, (valid_user_id, page_size, offset))
            fallback_rows = cur.fetchall()
            items = [
                {
                    "id": str(r[0]), "source": r[1], "title": r[2], "url": r[3],
                    "author": r[4], "published_at": r[5], "macro_tag": r[6],
                    "macro_tags": r[7] if r[7] else ([r[6]] if r[6] else []),
                    "micro_tags": r[8] or [], "tldr": r[9],
                    "image_url": r[10],
                    "image_status": r[11] or ("resolved" if r[10] else "gradient_fallback"),
                    "personal_score": 50,
                    "is_liked": False,
                    "is_disliked": False
                }
                for r in fallback_rows
            ]
            return {
                "user_id": valid_user_id,
                "is_fallback": True,
                "fallback_reason": "Onboarding not completed or preferences empty",
                "preferred_macro_tags": preferred_macros,
                "preferred_micro_tags": preferred_micros,
                "total": len(items),
                "page": page,
                "page_size": page_size,
                "articles": items
            }

        # Multi-factor zero-leakage personalized ranking (excluding disliked/skipped articles)
        interest_vec_str = None
        user_vec = parse_vector(user_interest_emb)
        if user_vec is not None:
            interest_vec_str = str(user_vec.tolist())

        # "+" follows (routers/follows.py): an article whose title or summary
        # names a followed thing (whole-word match) enters the feed even outside
        # the user's categories and is boosted (see FOLLOW_* points above).
        follow_names = _user_follow_names(cur, valid_user_id)
        follow_patterns = [_follow_pattern(n) for n in follow_names]

        SQL_PERSONALIZED = """
        SELECT
            s.id, s.source_feed, s.title, s.original_url, s.author, s.published_at,
            s.macro_tag, s.macro_tags, s.micro_tags, s.tldr,
            LEAST(100, s.base_score
                + (CASE WHEN cardinality(s.title_follows) > 0 THEN %(follow_title_boost)s
                        WHEN cardinality(s.matched_follows) > 0 THEN %(follow_summary_boost)s
                        ELSE 0 END)
                + (CASE WHEN cardinality(s.matched_follows) > 0
                         AND NOT (s.macro_tag = ANY(%(preferred_macros)s))
                        THEN %(follow_category_points)s ELSE 0 END)
            )::integer AS personal_score,
            s.is_liked,
            s.matched_follows,
            s.image_url,
            s.image_status
        FROM (
            SELECT
                a.id, a.source_feed, a.title, a.original_url, a.author, a.published_at,
                a.macro_tag, a.macro_tags, a.micro_tags, a.tldr,
                a.image_url, a.image_status,
                (
                    LEAST(40, 15 * cardinality(ARRAY(
                        SELECT unnest(a.micro_tags)
                        INTERSECT
                        SELECT unnest(%(preferred_micros)s::text[])
                    ))) +
                    (CASE WHEN a.macro_tag = ANY(%(preferred_macros)s) THEN 20 ELSE 0 END) +
                    (CASE
                        WHEN %(interest_vec)s::text IS NOT NULL AND a.embedding IS NOT NULL
                        THEN ROUND(25.0 * GREATEST(0.0,
                            (1.0 - (a.embedding <=> %(interest_vec)s::vector) - %(feed_floor)s) / (1.0 - %(feed_floor)s)))
                        ELSE 0
                     END) +
                    ROUND(15.0 * EXP(-EXTRACT(EPOCH FROM (NOW() - a.published_at)) / 259200.0))
                ) AS base_score,
                EXISTS (
                    SELECT 1 FROM user_article_interactions uai
                    WHERE uai.user_id = %(user_id)s
                      AND uai.article_id = a.id
                      AND uai.interaction_type = 'like'
                ) AS is_liked,
                ARRAY(
                    SELECT f.name
                    FROM unnest(%(follow_names)s::text[], %(follow_patterns)s::text[]) AS f(name, pattern)
                    WHERE a.title ~* f.pattern
                ) AS title_follows,
                ARRAY(
                    SELECT f.name
                    FROM unnest(%(follow_names)s::text[], %(follow_patterns)s::text[]) AS f(name, pattern)
                    WHERE a.title ~* f.pattern
                       OR COALESCE(a.tldr, '') ~* f.pattern
                    UNION
                    SELECT uf.name
                    FROM user_follows uf
                    WHERE uf.user_id = %(user_id)s
                      AND uf.embedding IS NOT NULL
                      AND a.embedding IS NOT NULL
                      AND (a.embedding <=> uf.embedding) <= %(follow_semantic_max_dist)s
                ) AS matched_follows
            FROM articles a
            WHERE a.is_processed = TRUE
              AND a.macro_tag IS NOT NULL
              AND a.macro_tag != 'Off-Topic'
              AND (a.on_topic_score IS NULL OR a.on_topic_score >= 0.40)
              AND NOT EXISTS (
                  SELECT 1 FROM user_article_interactions uai_d
                  WHERE uai_d.user_id = %(user_id)s
                    AND uai_d.article_id = a.id
                    AND uai_d.interaction_type IN ('dislike', 'skip')
              )
        ) s
        WHERE s.macro_tag = ANY(%(preferred_macros)s)
           OR s.macro_tags && %(preferred_macros)s::text[]
           OR cardinality(s.matched_follows) > 0
        ORDER BY personal_score DESC, s.published_at DESC
        LIMIT %(limit)s OFFSET %(offset)s;
        """

        cur.execute(SQL_PERSONALIZED, {
            "preferred_macros": preferred_macros,
            "preferred_micros": preferred_micros,
            "interest_vec": interest_vec_str,
            "user_id": valid_user_id,
            "follow_names": follow_names,
            "follow_patterns": follow_patterns,
            "follow_title_boost": FOLLOW_TITLE_BOOST,
            "follow_summary_boost": FOLLOW_SUMMARY_BOOST,
            "follow_category_points": FOLLOW_CATEGORY_POINTS,
            "follow_semantic_max_dist": 1.0 - similarity_thresholds()["follow_min"],
            "feed_floor": similarity_thresholds()["feed_floor"],
            "limit": page_size,
            "offset": offset
        })
        ranked_rows = cur.fetchall()

        items = [
            {
                "id": str(r[0]), "source": r[1], "title": r[2], "url": r[3],
                "author": r[4], "published_at": r[5], "macro_tag": r[6],
                "macro_tags": r[7] if r[7] else ([r[6]] if r[6] else []),
                "micro_tags": r[8] or [], "tldr": r[9],
                "personal_score": r[10],
                "is_liked": bool(r[11]),
                "is_disliked": False,
                "matched_follows": list(r[12] or []),
                "image_url": r[13],
                "image_status": r[14] or ("resolved" if r[13] else "gradient_fallback")
            }
            for r in ranked_rows
        ]

        return {
            "user_id": valid_user_id,
            "is_fallback": False,
            "preferred_macro_tags": preferred_macros,
            "preferred_micro_tags": preferred_micros,
            "total": len(items),
            "page": page,
            "page_size": page_size,
            "articles": items
        }


@router.get("/api/feed/personalized")
def personalized_feed(user_id: str, page: int = 1, page_size: int = 20):
    """Zero-leakage personalized feed ranked by user preferences, GIN micro tags, and semantic vectors."""
    return get_personalized_feed_data(user_id=user_id, page=page, page_size=page_size)


@router.post("/api/articles/{article_id}/interactions")
def toggle_interaction(article_id: str, req: UserInteractionRequest):
    """
    Toggles like, dislike, skip, bookmark, or read state for an article.
    Feeds user interaction context directly into both the 384d interest_embedding
    (EMA attraction on 'like', negative EMA repulsion on 'dislike'/'skip') and
    the user's preferred_micro_tags / preferred_macro_tags profile.
    """
    valid_art_id = validate_uuid(article_id, "article_id")
    valid_user_id = validate_uuid(req.user_id, "user_id")
    itype = req.interaction_type.strip().lower()
    valid_types = ("like", "dislike", "skip", "bookmark", "read")
    if itype not in valid_types:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid interaction_type. Must be one of: {', '.join(valid_types)}."
        )

    with get_db() as cur:
        cur.execute("""
            SELECT id FROM user_article_interactions
            WHERE user_id = %s AND article_id = %s AND interaction_type = %s;
        """, (valid_user_id, valid_art_id, itype))
        existing = cur.fetchone()

        if existing:
            cur.execute("""
                DELETE FROM user_article_interactions
                WHERE user_id = %s AND article_id = %s AND interaction_type = %s;
            """, (valid_user_id, valid_art_id, itype))
            return {
                "status": "removed",
                "active": False,
                "interaction_type": itype,
                "article_id": valid_art_id,
                "user_id": valid_user_id
            }

        # Remove mutually exclusive opposite signals (like vs dislike/skip)
        if itype == "like":
            cur.execute("""
                DELETE FROM user_article_interactions
                WHERE user_id = %s AND article_id = %s AND interaction_type IN ('dislike', 'skip');
            """, (valid_user_id, valid_art_id))
        elif itype in ("dislike", "skip"):
            cur.execute("""
                DELETE FROM user_article_interactions
                WHERE user_id = %s AND article_id = %s AND interaction_type = 'like';
            """, (valid_user_id, valid_art_id))

        cur.execute("""
            INSERT INTO user_article_interactions (user_id, article_id, interaction_type)
            VALUES (%s, %s, %s);
        """, (valid_user_id, valid_art_id, itype))

        updated_micros = None
        updated_macros = None
        new_vec_str = None

        # Dynamic EMA Vector & Tag Context Learning on 'like' and 'dislike'/'skip'
        if itype in ("like", "dislike", "skip"):
            cur.execute("""
                SELECT embedding, macro_tag, micro_tags
                FROM articles WHERE id = %s;
            """, (valid_art_id,))
            art_row = cur.fetchone()
            art_emb = art_row[0] if art_row else None
            art_macro = art_row[1] if art_row else None
            art_micros = (art_row[2] or []) if art_row else []

            cur.execute("""
                SELECT interest_embedding, preferred_macro_tags, preferred_micro_tags
                FROM users WHERE id = %s;
            """, (valid_user_id,))
            user_row = cur.fetchone()
            user_emb = user_row[0] if user_row else None
            curr_macros = list(user_row[1] or []) if user_row else []
            curr_micros = list(user_row[2] or []) if user_row else []

            art_vec = parse_vector(art_emb)
            user_vec = parse_vector(user_emb)

            new_vec = ema_update(user_vec, art_vec, itype)
            new_vec_str = str(new_vec.tolist()) if new_vec is not None else None

            if itype == "like":
                if art_macro and art_macro != "Off-Topic" and art_macro not in curr_macros:
                    curr_macros.append(art_macro)
                for mt in art_micros[:2]:
                    if mt and mt != "off_topic" and mt not in curr_micros:
                        curr_micros.insert(0, mt)
                curr_micros = curr_micros[:15]
            else:
                # On dislike/skip, prune disliked article's micro-tags if user has other tags
                disliked_set = set(art_micros[:2])
                remaining = [t for t in curr_micros if t not in disliked_set]
                if remaining:
                    curr_micros = remaining

            updated_macros = curr_macros
            updated_micros = curr_micros

            if new_vec_str is not None:
                cur.execute("""
                    UPDATE users 
                    SET interest_embedding = %s::vector,
                        preferred_macro_tags = %s,
                        preferred_micro_tags = %s,
                        onboarding_completed = TRUE
                    WHERE id = %s;
                """, (new_vec_str, updated_macros, updated_micros, valid_user_id))
            else:
                cur.execute("""
                    UPDATE users 
                    SET preferred_macro_tags = %s,
                        preferred_micro_tags = %s
                    WHERE id = %s;
                """, (updated_macros, updated_micros, valid_user_id))

        return {
            "status": "recorded",
            "active": True,
            "interaction_type": itype,
            "article_id": valid_art_id,
            "user_id": valid_user_id,
            "ema_updated": bool(itype in ("like", "dislike", "skip") and new_vec_str is not None),
            "updated_preferred_macro_tags": updated_macros,
            "updated_preferred_micro_tags": updated_micros
        }


USER_COLUMNS = "id, username, avatar_url, onboarding_completed, preferred_macro_tags, preferred_micro_tags, interest_context"


def _user_out(row) -> Dict[str, Any]:
    """API shape of a users row selected with USER_COLUMNS."""
    return {
        "id": str(row[0]),
        "username": row[1],
        "avatar_url": row[2],
        "onboarding_completed": bool(row[3]) if row[3] is not None else False,
        "preferred_macro_tags": row[4] or [],
        "preferred_micro_tags": row[5] or [],
        "interest_context": row[6]
    }


@router.post("/api/users/login")
def user_quick_login(req: UserLoginRequest):
    raw_name = req.username or req.name or ""
    username = raw_name.strip()
    if not username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")
    with get_db() as cur:
        _ensure_context_columns(cur)
        cur.execute(f"SELECT {USER_COLUMNS} FROM users WHERE username = %s;", (username,))
        row = cur.fetchone()
        if row:
            return _user_out(row)
        avatar = f"https://avatar.iran.liara.run/public/boy?username={username}"
        cur.execute(f"""
            INSERT INTO users (username, avatar_url, onboarding_completed)
            VALUES (%s, %s, FALSE)
            RETURNING {USER_COLUMNS};
        """, (username, avatar))
        return _user_out(cur.fetchone())


def _fetch_interests_now(macros: List[str], micros: List[str]) -> None:
    """Background task: fetch and save news for the user's newly chosen topics (never raises)."""
    try:
        from ingest_tavily import fetch_user_interests_now
        fetch_user_interests_now(macros, micros)
    except Exception as e:
        logger.warning("[Interests] Fetch-now failed: %s", e)


@router.put("/api/users/{user_id}/preferences")
def update_user_preferences(user_id: str, prefs: UserPreferencesUpdate, background: BackgroundTasks):
    """
    Saves user-selected macro/micro preferences and the optional context sentence.
    The 384d interest vector is built from the context sentence (in English) when
    there is one, otherwise from a standard sentence naming the chosen topics.
    Then fetches and saves news for any chosen topic whose shared query is due
    (onboarding "fetch and save"; topics fetched recently for others are skipped).
    """
    valid_user_id = validate_uuid(user_id, "user_id")

    clean_macros = []
    for m in prefs.preferred_macro_tags:
        for canonical in MACRO_CATEGORIES:
            if canonical.lower() == m.strip().lower() and canonical not in clean_macros:
                clean_macros.append(canonical)
    if not clean_macros and prefs.preferred_macro_tags:
        clean_macros = [MACRO_CATEGORIES[0]]

    clean_micros = clean_micro_tags(prefs.preferred_micro_tags, max_tags=12)

    with get_db() as cur:
        _ensure_context_columns(cur)
        cur.execute("SELECT interest_context, interest_context_en FROM users WHERE id = %s;", (valid_user_id,))
        stored = cur.fetchone()
        if not stored:
            raise HTTPException(status_code=404, detail="User not found")

    # interest_context: absent = keep, empty = clear, text = set.
    if prefs.interest_context is None:
        context, context_en = stored
    else:
        context = _clean_context(prefs.interest_context)
        if not context:
            context_en = None
        elif context == stored[0] and stored[1]:
            context_en = stored[1]
        else:
            context_en = _context_to_english(context)

    interest_text = context_en or _standard_interest_text(clean_macros, clean_micros)

    embedder = get_embedder()
    interest_vector = embedder.embed_query(interest_text)

    with get_db() as cur:
        cur.execute(f"""
            UPDATE users
            SET preferred_macro_tags = %s,
                preferred_micro_tags = %s,
                onboarding_completed = TRUE,
                interest_embedding = %s::vector,
                interest_context = %s,
                interest_context_en = %s
            WHERE id = %s
            RETURNING {USER_COLUMNS};
        """, (clean_macros, clean_micros, str(interest_vector), context, context_en, valid_user_id))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        from routers.latest import forget_latest  # routers.latest imports this module
        forget_latest(cur, valid_user_id)
        background.add_task(_fetch_interests_now, list(row[4] or []), list(row[5] or []))
        return {**_user_out(row), "interest_summary": interest_text}


@router.get("/api/users/{user_id}/preferences")
def get_user_preferences(user_id: str):
    valid_user_id = validate_uuid(user_id, "user_id")
    with get_db() as cur:
        _ensure_context_columns(cur)
        cur.execute(f"SELECT {USER_COLUMNS} FROM users WHERE id = %s;", (valid_user_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        return _user_out(row)


@router.get("/api/users")
def get_all_users():
    with get_db() as cur:
        cur.execute("SELECT id, username, avatar_url, created_at FROM users ORDER BY created_at ASC;")
        rows = cur.fetchall()
        return [
            {"id": str(r[0]), "username": r[1], "avatar_url": r[2], "created_at": r[3]}
            for r in rows
        ]
