"""add Source.language and hide_non_fr_sources user prefs

Suite directe de `lg01_add_language_to_contents` (qui a peuplé
`Content.language`). Cette migration ajoute :

1. `sources.language` (String(8), nullable, indexé) — backfill par langue
   majoritaire des `Content.language` connus de la source (seuil ≥ 60%
   des articles à langue connue, sinon NULL → traité comme FR par défaut
   côté client, rétro-compat).
2. `user_personalization.hide_non_fr_sources` (Boolean, default true) —
   masque les cartes des sources non-FR dans Essentiel/feed/digest, sauf
   les sources que l'utilisateur suit explicitement.
3. `user_personalization.language_filter_user_set` (Boolean, default
   false) — flag "mode auto" : tant qu'il est false, le toggle est
   recalculé automatiquement à chaque follow/unfollow d'une source. Une
   modification manuelle via l'API le passe à true (gel du choix user).

Backfill du toggle : true uniquement pour les users qui ne suivent
aucune source étrangère (`language NOT IN ('fr', NULL)`), false sinon
— ainsi un user qui suit déjà des sources EN ne voit pas son feed
amputé sans son consentement explicite.
"""

from collections import Counter

import sqlalchemy as sa

from alembic import op

revision: str = "lg02_source_language_user_pref"
down_revision: str | None = "lg01_add_language_to_contents"
branch_labels: str | None = None
depends_on: str | None = None

# Seuil au-delà duquel on considère une source comme "majoritairement X"
# (sur l'échantillon des contents à langue connue). Sous le seuil →
# language=NULL, traité comme FR par défaut (rétro-compat).
_MAJORITY_THRESHOLD = 0.60


def upgrade() -> None:
    # --- 1. sources.language --------------------------------------------------
    op.add_column(
        "sources",
        sa.Column("language", sa.String(length=8), nullable=True),
    )
    op.create_index("ix_sources_language", "sources", ["language"])

    # --- 2. user_personalization.{hide_non_fr_sources, language_filter_user_set}
    op.add_column(
        "user_personalization",
        sa.Column(
            "hide_non_fr_sources",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )
    op.add_column(
        "user_personalization",
        sa.Column(
            "language_filter_user_set",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )

    # Offline mode (`alembic upgrade --sql`) : DDL seul, pas de backfill.
    if op.get_context().as_sql:
        return

    bind = op.get_bind()

    # --- 3. Backfill sources.language ----------------------------------------
    # Pour chaque source : compter les Content.language non-NULL, prendre
    # la langue majoritaire si elle dépasse 60% — sinon laisser NULL.
    rows = bind.execute(
        sa.text(
            "SELECT source_id, language, COUNT(*) AS n "
            "FROM contents "
            "WHERE language IS NOT NULL "
            "GROUP BY source_id, language"
        )
    ).fetchall()

    by_source: dict[str, Counter[str]] = {}
    for row in rows:
        by_source.setdefault(str(row.source_id), Counter())[row.language] = row.n

    update_stmt = sa.text("UPDATE sources SET language = :language WHERE id = :id")
    updates: list[dict[str, str]] = []
    for source_id, counter in by_source.items():
        total = sum(counter.values())
        if total == 0:
            continue
        lang, n = counter.most_common(1)[0]
        if n / total >= _MAJORITY_THRESHOLD:
            updates.append({"id": source_id, "language": lang})

    if updates:
        bind.execute(update_stmt, updates)

    # --- 4. Backfill user_personalization.hide_non_fr_sources -----------------
    # Règle dynamique au moment de la migration : si le user suit déjà
    # ≥1 source étrangère (language ∉ ('fr', NULL)), on désactive le
    # toggle pour respecter son choix implicite. Sinon on l'active.
    # `language_filter_user_set` reste à false (mode auto) — il ne passera
    # à true que lors d'une interaction manuelle via l'API.
    bind.execute(
        sa.text(
            "UPDATE user_personalization up "
            "SET hide_non_fr_sources = false "
            "WHERE EXISTS ("
            "  SELECT 1 FROM user_sources us "
            "  JOIN sources s ON s.id = us.source_id "
            "  WHERE us.user_id = up.user_id "
            "    AND s.language IS NOT NULL "
            "    AND s.language <> 'fr'"
            ")"
        )
    )


def downgrade() -> None:
    op.drop_column("user_personalization", "language_filter_user_set")
    op.drop_column("user_personalization", "hide_non_fr_sources")
    op.drop_index("ix_sources_language", table_name="sources")
    op.drop_column("sources", "language")
