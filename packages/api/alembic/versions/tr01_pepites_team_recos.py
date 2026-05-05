"""pepites team recos: recommended_by + recommendation_reason

Revision ID: tr01
Revises: gn01, vl01
Create Date: 2026-05-02

- Remplace `sources.editorial_note` par `recommended_by` (str) +
  `recommendation_reason` (text).
- Réinitialise les pépites (`is_pepite_recommendation = false`) et active
  uniquement les 15 sources recommandées par l'équipe Facteur (Laurin,
  Anh-Dao, Django, Lucas).
- Crée les 5 sources qui n'existaient pas encore en DB (PsykoCouac,
  Les Lueurs, Limit, Chaleur Humaine, Le Code a changé).

Aussi : merge des deux heads `gn01` + `vl01`.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "tr01"
down_revision: str | tuple[str, ...] = ("gn01", "vl01")
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


# (name, type, url, feed_url, theme, recommended_by, recommendation_reason)
NEW_SOURCES: list[tuple[str, str, str, str, str, str, str]] = [
    (
        "PsykoCouac",
        "youtube",
        "https://www.youtube.com/@PsykoCouac",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCsE6tdKFV2oSHFyDll72rWg",
        "society",
        "Anh-Dao",
        "Vulgarisation de la psychologie par un praticien. Une bonne porte "
        "d'entrée pour développer ouverture, compréhension et bienveillance "
        "pour soi et autrui.",
    ),
    (
        "Les Lueurs",
        "podcast",
        "https://leslueurs.fr/",
        "https://feeds.podcastics.com/podcastics/podcasts/rss/5697_a59f1749b640068f2d54338141e262a0.rss",
        "society",
        "Anh-Dao",
        "Podcasts avec des intervenant·e·s qui apportent un peu de "
        "philosophie et d'espoir. Une invitation à l'introspection pour "
        "cultiver sa réflexivité.",
    ),
    (
        "Limit",
        "youtube",
        "https://www.youtube.com/@LIMITMEDIA",
        "https://www.youtube.com/feeds/videos.xml?channel_id=UCAbFIrKZCYdKucQYnhxWnrA",
        "environment",
        "Anh-Dao",
        "Média qui aborde les limites planétaires en intégrant planchers "
        "sociaux et plafonds de ressources. La théorie du donut au cœur "
        "d'une vision pour une société plus robuste.",
    ),
    (
        "Chaleur Humaine",
        "podcast",
        "https://podcasts.lemonde.fr/chaleur-humaine",
        "https://feeds.acast.com/public/shows/68db9a016d92c33f9c2eff83",
        "environment",
        "Django",
        "Le podcast climat de Nabil Wakim (Le Monde) : beaucoup d'humain, "
        "de la légèreté, et des invité·e·s pertinent·e·s. Plein "
        "d'apprentissages.",
    ),
    (
        "Le Code a changé",
        "podcast",
        "https://www.radiofrance.fr/franceinter/podcasts/le-code-a-change",
        "https://radiofrance-podcast.net/podcast09/rss_20856.xml",
        "tech",
        "Django",
        "Xavier de la Porte explore le numérique comme miroir de notre "
        "époque. Narration, introspection et entretiens permettent de "
        "prendre de la hauteur sur notre rapport à la tech.",
    ),
]


# (name LIKE pattern, recommended_by, recommendation_reason)
EXISTING_RECOS: list[tuple[str, str, str]] = [
    (
        "The Conversation",
        "Laurin",
        "Choix de sujets très intéressants. Traitement rigoureux. Articles "
        "longs et étayés, on en ressort avec l'impression d'avoir très bien "
        "compris le sujet.",
    ),
    (
        "Le Grand Continent",
        "Laurin",
        "Traitement super rigoureux et expert. Articles longs et étayés, on "
        "en ressort avec l'impression d'avoir très bien compris le sujet.",
    ),
    (
        "Cerveau & Psycho",
        "Laurin",
        "Choix de sujets très pertinents. Peu d'articles mais tous très "
        "intéressants quand on s'intéresse à la psychologie et à la société.",
    ),
    (
        "Next.ink",
        "Laurin",
        "Angles intéressants sur la Tech. Rédaction experte et indépendante, "
        "un autre angle que les discours uniquement optimistes ou "
        "pessimistes sur le numérique.",
    ),
    (
        "Blast",
        "Anh-Dao",
        "Les formats de Salomé Saqué : sujets éco/sociologiques constructifs, "
        "intervenants experts. Format long qui apporte réflexion et idées "
        "applicables.",
    ),
    (
        "Vert",
        "Django",
        "Média indépendant focus écologie, toujours avec une pointe d'humour, "
        "et qui debunk les fausses infos. Actualités d'utilité publique.",
    ),
    (
        "Novethic",
        "Django",
        "Média engagé spécialisé finance durable et économie responsable. "
        "Propose des thèmes et angles qu'on ne trouve pas ailleurs.",
    ),
    (
        "StreetPress",
        "Django",
        "Média indépendant qui enquête sur l'extrême droite et ses dérives "
        "depuis des années.",
    ),
    (
        "Le Réveilleur",
        "Django",
        "LA chaîne pour comprendre les mécaniques d'énergie et de carbone. "
        "Exigeante, dense — exactement ce qu'on cherche sur Facteur.",
    ),
    (
        "Underscore_",
        "Lucas",
        "Vulgarisation tech ambitieuse et indépendante. Format long et "
        "exigeant qui prend le temps de creuser les vrais enjeux du "
        "numérique au-delà du buzz.",
    ),
]


def upgrade() -> None:
    # 1. Schema changes
    op.add_column(
        "sources",
        sa.Column("recommended_by", sa.String(length=50), nullable=True),
    )
    op.add_column(
        "sources",
        sa.Column("recommendation_reason", sa.Text(), nullable=True),
    )
    op.drop_column("sources", "editorial_note")

    # 2. Reset pépites + clear old recommendation fields
    op.execute(
        "UPDATE sources SET is_pepite_recommendation = false, "
        "recommended_by = NULL, recommendation_reason = NULL"
    )

    bind = op.get_bind()

    # 3. Update existing sources (match by exact name where possible).
    # The Conversation has 2 entries — only flag the FR one.
    bind.execute(
        sa.text(
            "UPDATE sources SET is_pepite_recommendation = true, "
            "is_active = true, recommended_by = :rb, "
            "recommendation_reason = :rr "
            "WHERE name = 'The Conversation' "
            "AND feed_url = 'https://theconversation.com/fr/articles.atom'"
        ),
        {
            "rb": "Laurin",
            "rr": (
                "Choix de sujets très intéressants. Traitement rigoureux. "
                "Articles longs et étayés, on en ressort avec l'impression "
                "d'avoir très bien compris le sujet."
            ),
        },
    )

    for name, rb, rr in EXISTING_RECOS:
        if name == "The Conversation":
            continue
        where = "name ILIKE 'StreetPress%'" if name == "StreetPress" else "name = :name"
        bind.execute(
            sa.text(
                "UPDATE sources SET is_pepite_recommendation = true, "
                "is_active = true, recommended_by = :rb, "
                f"recommendation_reason = :rr WHERE {where}"
            ),
            {"name": name, "rb": rb, "rr": rr},
        )

    # 4. Insert new sources (skip if already exist by feed_url).
    for name, type_, url, feed_url, theme, rb, rr in NEW_SOURCES:
        bind.execute(
            sa.text(
                "INSERT INTO sources (id, name, url, feed_url, type, theme, "
                "is_active, is_curated, is_pepite_recommendation, "
                "recommended_by, recommendation_reason) "
                "VALUES (gen_random_uuid(), :name, :url, :feed_url, :type, "
                ":theme, true, true, true, :rb, :rr) "
                "ON CONFLICT (feed_url) DO UPDATE SET "
                "is_active = true, is_pepite_recommendation = true, "
                "recommended_by = EXCLUDED.recommended_by, "
                "recommendation_reason = EXCLUDED.recommendation_reason"
            ),
            {
                "name": name,
                "url": url,
                "feed_url": feed_url,
                "type": type_,
                "theme": theme,
                "rb": rb,
                "rr": rr,
            },
        )


def downgrade() -> None:
    bind = op.get_bind()
    # Remove inserted sources
    for _, _, _, feed_url, *_ in NEW_SOURCES:
        bind.execute(
            sa.text("DELETE FROM sources WHERE feed_url = :feed_url"),
            {"feed_url": feed_url},
        )
    op.execute(
        "UPDATE sources SET is_pepite_recommendation = false, "
        "recommended_by = NULL, recommendation_reason = NULL"
    )
    op.add_column(
        "sources",
        sa.Column("editorial_note", sa.Text(), nullable=True),
    )
    op.drop_column("sources", "recommendation_reason")
    op.drop_column("sources", "recommended_by")
