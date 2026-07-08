"""media eval — 7 tables du pipeline d'évaluation des médias C1–C11.

Data store collecte ≠ évaluation (cf. docs/media-eval/architecture-v1.2.md) :
référentiel médias, snapshots, corpus (vide en V0), signaux (pivot),
débunkages qualifiés, évaluations, fiches.

Additive pure (CREATE TABLE uniquement) → sûre en expand-contract sur la DB
partagée staging/prod : le backend prod (ancien code) ignore les tables
jusqu'au passage hebdo. Idempotente (no-op table par table si déjà créée —
la chaîne boote sur les DEUX services Railway).

RLS deny-all en fin d'upgrade (pattern sec02) : tables backend-only, aucune
policy — ENABLE ROW LEVEL SECURITY + REVOKE ALL FROM anon, authenticated.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from alembic import op

revision: str = "me01_media_eval_tables"
down_revision: str | None = "ue01_user_entity_affinity"
branch_labels: str | None = None
depends_on: str | None = None

_CRITERE_CHECK = "critere IN ({})".format(", ".join(f"'C{i}'" for i in range(1, 12)))

# Ordre de création (les FK imposent medias puis snapshots puis signaux…).
# downgrade() droppe en ordre inverse.
_TABLES = (
    "media_eval_medias",
    "media_eval_snapshots",
    "media_eval_corpus_articles",
    "media_eval_signaux",
    "media_eval_debunkages",
    "media_eval_evaluations",
    "media_eval_fiches",
)


def _uuid_pk() -> sa.Column:
    return sa.Column(
        "id",
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=sa.text("gen_random_uuid()"),
        nullable=False,
    )


def _media_fk() -> sa.Column:
    return sa.Column("media_id", PGUUID(as_uuid=True), nullable=False)


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if not inspector.has_table("media_eval_medias"):
        op.create_table(
            "media_eval_medias",
            _uuid_pk(),
            sa.Column("nom", sa.String(length=200), nullable=False),
            sa.Column("domaine", sa.String(length=255), nullable=False),
            sa.Column("type_media", sa.String(length=30), nullable=False),
            sa.Column("paywall", sa.Boolean(), nullable=False, server_default="false"),
            sa.Column("rubriques_opinion", ARRAY(sa.Text()), nullable=True),
            sa.Column("volume_articles_jour", sa.Integer(), nullable=True),
            sa.Column("source_ids", ARRAY(PGUUID(as_uuid=True)), nullable=True),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.UniqueConstraint("domaine", name="uq_media_eval_medias_domaine"),
        )

    if not inspector.has_table("media_eval_snapshots"):
        op.create_table(
            "media_eval_snapshots",
            _uuid_pk(),
            _media_fk(),
            sa.Column("url", sa.Text(), nullable=False),
            sa.Column("type_page", sa.String(length=30), nullable=False),
            sa.Column("contenu", sa.Text(), nullable=True),
            sa.Column("hash", sa.String(length=64), nullable=True),
            sa.Column("http_status", sa.Integer(), nullable=True),
            sa.Column(
                "mode_acces",
                sa.String(length=30),
                nullable=False,
                server_default="libre",
            ),
            sa.Column(
                "capture_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
        )
        op.create_index(
            "ix_media_eval_snapshots_media_id", "media_eval_snapshots", ["media_id"]
        )

    if not inspector.has_table("media_eval_corpus_articles"):
        op.create_table(
            "media_eval_corpus_articles",
            _uuid_pk(),
            _media_fk(),
            sa.Column("url", sa.Text(), nullable=False),
            sa.Column("titre", sa.Text(), nullable=True),
            sa.Column("date_pub", sa.Date(), nullable=True),
            sa.Column("rubrique", sa.String(length=100), nullable=True),
            sa.Column("texte", sa.Text(), nullable=True),
            sa.Column("mode_acquisition", sa.String(length=30), nullable=True),
            sa.Column("pre_metriques", JSONB(), nullable=True),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
            sa.UniqueConstraint(
                "media_id", "url", name="uq_media_eval_corpus_media_url"
            ),
        )

    if not inspector.has_table("media_eval_signaux"):
        op.create_table(
            "media_eval_signaux",
            _uuid_pk(),
            _media_fk(),
            sa.Column("critere", sa.String(length=3), nullable=False),
            sa.Column("type_signal", sa.String(length=50), nullable=False),
            sa.Column("statut", sa.String(length=30), nullable=False),
            sa.Column("valeur", JSONB(), nullable=True),
            sa.Column("citation", sa.Text(), nullable=True),
            sa.Column("voie", sa.String(length=30), nullable=False),
            sa.Column("collecteur", sa.String(length=100), nullable=False),
            sa.Column(
                "source_urls", ARRAY(sa.Text()), nullable=False, server_default="{}"
            ),
            sa.Column("sources_consultees", ARRAY(sa.Text()), nullable=True),
            sa.Column("snapshot_id", PGUUID(as_uuid=True), nullable=True),
            sa.Column("run_id", sa.String(length=50), nullable=False),
            sa.Column("dedupe_key", sa.String(length=64), nullable=False),
            sa.Column(
                "collecte_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
            sa.ForeignKeyConstraint(
                ["snapshot_id"], ["media_eval_snapshots.id"], ondelete="SET NULL"
            ),
            sa.CheckConstraint(_CRITERE_CHECK, name="ck_media_eval_signaux_critere"),
            sa.UniqueConstraint(
                "media_id",
                "run_id",
                "dedupe_key",
                name="uq_media_eval_signaux_media_run_dedupe",
            ),
        )
        op.create_index(
            "ix_media_eval_signaux_media_critere",
            "media_eval_signaux",
            ["media_id", "critere"],
        )
        op.create_index(
            "ix_media_eval_signaux_run_id", "media_eval_signaux", ["run_id"]
        )

    if not inspector.has_table("media_eval_debunkages"):
        op.create_table(
            "media_eval_debunkages",
            _uuid_pk(),
            _media_fk(),
            sa.Column("signal_id", PGUUID(as_uuid=True), nullable=False),
            sa.Column("url_debunkage", sa.Text(), nullable=False),
            sa.Column("emetteur", sa.String(length=100), nullable=False),
            sa.Column("poids_emetteur", sa.String(length=30), nullable=False),
            sa.Column("gravite", sa.String(length=30), nullable=False),
            sa.Column("suite_donnee", sa.String(length=30), nullable=False),
            sa.Column("resume", sa.Text(), nullable=True),
            sa.Column("publie_at", sa.Date(), nullable=False),
            sa.Column(
                "created_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
            sa.ForeignKeyConstraint(
                ["signal_id"], ["media_eval_signaux.id"], ondelete="CASCADE"
            ),
            sa.UniqueConstraint("signal_id", name="uq_media_eval_debunkages_signal"),
        )

    if not inspector.has_table("media_eval_evaluations"):
        op.create_table(
            "media_eval_evaluations",
            _uuid_pk(),
            _media_fk(),
            sa.Column("critere", sa.String(length=3), nullable=False),
            sa.Column("score", sa.Float(), nullable=True),
            sa.Column("score_max", sa.Float(), nullable=False),
            sa.Column("niveau", sa.Integer(), nullable=True),
            sa.Column("statut", sa.String(length=30), nullable=False),
            sa.Column("justification", sa.Text(), nullable=False),
            sa.Column(
                "signal_ids",
                ARRAY(PGUUID(as_uuid=True)),
                nullable=False,
                server_default="{}",
            ),
            sa.Column("flags", ARRAY(sa.Text()), nullable=False, server_default="{}"),
            sa.Column("evaluateur", sa.String(length=100), nullable=False),
            sa.Column("version_methodo", sa.String(length=20), nullable=False),
            sa.Column("version_prompt", sa.String(length=64), nullable=False),
            sa.Column("run_id", sa.String(length=50), nullable=False),
            sa.Column(
                "evalue_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
            sa.CheckConstraint(
                _CRITERE_CHECK, name="ck_media_eval_evaluations_critere"
            ),
            sa.CheckConstraint(
                "niveau IS NULL OR (niveau >= 0 AND niveau <= 2)",
                name="ck_media_eval_evaluations_niveau",
            ),
            sa.UniqueConstraint(
                "media_id",
                "critere",
                "evaluateur",
                "run_id",
                name="uq_media_eval_evaluations_media_critere_eval_run",
            ),
        )

    if not inspector.has_table("media_eval_fiches"):
        op.create_table(
            "media_eval_fiches",
            _uuid_pk(),
            _media_fk(),
            sa.Column("run_id", sa.String(length=50), nullable=False),
            sa.Column("score_brut", sa.Float(), nullable=False),
            sa.Column("score_max_applicable", sa.Float(), nullable=False),
            sa.Column("score_renormalise", sa.Float(), nullable=False),
            sa.Column("lettre", sa.String(length=1), nullable=False),
            sa.Column(
                "criteres_evalues",
                ARRAY(sa.Text()),
                nullable=False,
                server_default="{}",
            ),
            sa.Column(
                "criteres_na", ARRAY(sa.Text()), nullable=False, server_default="{}"
            ),
            sa.Column("confiance", sa.String(length=30), nullable=False),
            sa.Column(
                "statut",
                sa.String(length=30),
                nullable=False,
                server_default="brouillon",
            ),
            sa.Column("detail", JSONB(), nullable=True),
            sa.Column(
                "genere_at",
                sa.DateTime(timezone=True),
                server_default=sa.text("now()"),
                nullable=False,
            ),
            sa.ForeignKeyConstraint(
                ["media_id"], ["media_eval_medias.id"], ondelete="CASCADE"
            ),
            sa.UniqueConstraint(
                "media_id", "run_id", name="uq_media_eval_fiches_media_run"
            ),
        )

    # RLS deny-all (pattern sec02) : backend-only, aucune policy. Idempotent.
    for table in _TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"REVOKE ALL ON TABLE {table} FROM anon, authenticated")


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    for table in reversed(_TABLES):
        if inspector.has_table(table):
            op.drop_table(table)
