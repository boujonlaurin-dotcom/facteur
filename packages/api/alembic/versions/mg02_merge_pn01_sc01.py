"""merge pn01_server_push + sc01_drop_ucs_excl_idx

Hotfix fork Alembic (même classe d'incident que `mg01_merge_au01_rsvps` et
`5de67819bc61`). Après le merge de `mg01_merge_au01_rsvps`, deux branches sont
reparties en parallèle du même parent `mg01_merge_au01_rsvps` :

  mg01 ──► gh01_grille_hybrid_word ──► ex01_drop_extraction_ts ──► pn01_server_push
   └─────► sc01_drop_ucs_excl_idx

→ 2 heads (`pn01_server_push`, `sc01_drop_ucs_excl_idx`). Le `Dockerfile`
exécute `alembic upgrade head` (singulier) au boot Railway et échoue avec
"Multiple head revisions are present" : la DB est restée figée sur
`mg01_merge_au01_rsvps`, donc les colonnes `hybrid_*` de `gh01` ne sont jamais
créées et `/api/grille/today` renvoie un 500 `ProgrammingError`
(grille_puzzles.hybrid_field n'existe pas).

Cette révision unifie le graphe sans DDL : au prochain boot, Alembic appliquera
naturellement la branche en attente (`gh01` → `ex01` → `pn01`) + `sc01`, puis
ce merge. Exactement 1 head ensuite.

⚠️ EXPAND-CONTRACT — à valider AVANT déploiement (DB Supabase partagée
prod/staging) : parmi les migrations rejouées, `ex01_drop_extraction_ts` fait un
`DROP COLUMN contents.extraction_attempted_at` (contract, non additif). `main`
ne référence plus la colonne ; confirmer que le code **prod déployé** (branche
`production`) ne la lit/écrit plus avant de merger ceci. Les 3 autres sont sûres
(`gh01` = colonnes nullable, `pn01` = nouvelles tables, `sc01` = drop d'un index
mort). Voir docs/runbooks/recover-from-alembic-drift.md.

Revision ID: mg02_merge_pn01_sc01
Revises: pn01_server_push, sc01_drop_ucs_excl_idx
Create Date: 2026-06-16

"""

revision: str = "mg02_merge_pn01_sc01"
down_revision: tuple[str, ...] = (
    "pn01_server_push",
    "sc01_drop_ucs_excl_idx",
)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
