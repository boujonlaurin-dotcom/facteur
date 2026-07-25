"""contents.entities — index trigram pour le 1er batch « Comparer les angles ».

Le live path des perspectives (``PerspectiveService.search_internal_perspectives``)
cherche les articles partageant une entité PERSON/ORG via
``array_to_string(entities, ' ') ILIKE '%nom%'`` — non-sargable : Postgres borne
la fenêtre 72h avec ``ix_contents_published_at`` puis évalue l'``ILIKE`` **ligne
par ligne** sur toute la fenêtre (~1,58 s en prod, coût O(articles publiés)).

Cette révision pose un index GIN trigram (pg_trgm) sur l'expression de la requête
pour que le planner ne remonte que les lignes candidates (bitmap) au lieu de
scanner la fenêtre entière (mesuré local : 6911 lignes filtrées → 9 candidates).

Deux objets, tous deux ADDITIFS et idempotents — sûrs sur la DB partagée
staging↔prod : le backend prod (ancien code ``production``, requête inchangée) les
ignore jusqu'au passage hebdo :

1. ``public.content_entities_text(text[])`` — wrapper **IMMUTABLE** de
   ``array_to_string($1, ' ')``. Indispensable : le builtin polymorphe
   ``array_to_string(anyarray, text)`` est déclaré **STABLE**, donc rejeté dans
   une expression d'index (« functions in index expression must be marked
   IMMUTABLE »). Pour du ``text[]`` la sortie est réellement immutable → le
   wrapper est légitime. ``search_internal_perspectives`` bascule sur ce wrapper
   (même PR) pour que l'expression indexée matche.
2. ``ix_contents_entities_trgm`` — GIN sur ``content_entities_text(entities)`` avec
   l'opclass **``extensions.gin_trgm_ops``**. Le baseline crée pg_trgm ``WITH
   SCHEMA extensions`` ; l'opclass DOIT être qualifiée car ``extensions`` n'est
   pas dans le ``search_path`` des connexions (vérifié : ``gin_trgm_ops`` nu ⇒
   « operator class does not exist »).

Rollout (recommandé) : construire l'index une fois via Supabase — d'abord la
fonction, puis ``CREATE INDEX CONCURRENTLY`` (~30-90 s, non bloquant pour
l'ingestion) — AVANT merge, puis cette migration ``IF NOT EXISTS`` est un no-op
rapide au boot des deux services Railway.
"""

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "pt01_contents_entities_trgm"
down_revision: str | None = "181c618da382"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    # 1) Wrapper IMMUTABLE — instantané, sûr dans la transaction Alembic.
    #    Idempotent (CREATE OR REPLACE) ; corps identique ⇒ l'index dépendant
    #    survit à un rejeu au boot de la DB partagée.
    op.execute(
        """
        CREATE OR REPLACE FUNCTION public.content_entities_text(text[])
        RETURNS text
        LANGUAGE sql
        IMMUTABLE
        PARALLEL SAFE
        AS $func$ SELECT array_to_string($1, ' ') $func$
        """
    )
    # 2) Index GIN trigram. CREATE INDEX CONCURRENTLY ne peut pas tourner dans
    #    la transaction Alembic (env.py enveloppe tout dans un seul begin) →
    #    bloc autocommit. IF NOT EXISTS : no-op si déjà bâti hors-bande.
    with op.get_context().autocommit_block():
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_contents_entities_trgm "
            "ON public.contents "
            "USING gin (public.content_entities_text(entities) "
            "extensions.gin_trgm_ops)"
        )


def downgrade() -> None:
    # L'index dépend de la fonction → le retirer d'abord (hors transaction),
    # puis la fonction.
    with op.get_context().autocommit_block():
        op.execute("DROP INDEX CONCURRENTLY IF EXISTS ix_contents_entities_trgm")
    op.execute("DROP FUNCTION IF EXISTS public.content_entities_text(text[])")
