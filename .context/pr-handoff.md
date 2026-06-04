fix(mot-du-jour): anti-freeze + dico élargi + lien Actu + reveal article réel

« Mot du jour » (La Grille) — 2 bugs + 2 améliorations remontés en prod par le PO,
livrés en **une seule PR groupée** (décision PO). Détail : `docs/bugs/bug-mot-du-jour-bugs.md`.

## Part A — Anti-freeze (critique)
- Timeout dédié 12 s sur `POST grille/today/guess` (override le 30 s global).
- `submitGuess` : suppression du `rethrow` (source du hang silencieux) → état
  `networkError` ré-essayable + self-heal `_reconcileToday()` ; clavier réactivé.
- `_submitGuess` (écran) : plus de future non gérée ; pas de tracking « valide »
  sur erreur réseau.
- Backend **idempotent** : re-submit du même dernier mot (partie en cours) ne
  double-compte pas → retry réseau sûr.

## Part B — Dictionnaire élargi
- Asset curé `grille_proper_nouns_fr.txt` (pays/villes/prénoms) → ITALIE, RUSSIE…
  acceptés. Conjugaisons déjà couvertes par la source existante (vérifié) → pas
  de 2ᵉ source (Lexique383 écarté : CC BY-SA share-alike). Dico régénéré committé.

## Part C — Lien Actu du jour
- `_goToActus` → page complète `…/section/essentiel`.
- CTA « Lire l'actu du jour » toujours visible dans le jeu.

## Part D — Reveal lié à un vrai article (auto-matching)
- Migration additive `gr02_grille_featured_article` (nullable, FK ON DELETE SET NULL).
- `grille_matcher.py` accroche l'article du digest qui matche le mot (best-effort,
  hooké dans le job digest, non bloquant, idempotent).
- `featured*` gated fin de partie ; mobile affiche vrai titre/extrait/source +
  bouton « Lire l'article » (détail in-app), fallback `pourquoi`.

## Vérif
- 62 tests backend verts + 43 mobile verts. `ruff check/format app/` clean.
- Alembic : 1 head (`gr02`), upgrade/downgrade round-trip OK sur DB vide.
- `flutter analyze` clean (hors warning pré-existant carte_cta.dart).

## Notes review
- Migration = zone à risque DB : additive + nullable + FK SET NULL, testée en
  round-trip. Le Dockerfile rejoue `alembic upgrade head` au boot Railway.
- Suite mobile complète a ~27 échecs pré-existants hors-scope (Hive/Supabase) ;
  CI = pytest backend only.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
