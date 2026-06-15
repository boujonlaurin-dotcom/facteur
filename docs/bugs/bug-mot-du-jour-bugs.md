# Bug + UX — « Mot du jour » : freeze, dico, lien Actu, reveal réel

**Statut** : Corrigé (tests verts — en attente de PR)
**Branche** : `boujonlaurin-dotcom/mot-du-jour-bugs`
**Cible** : `main`
**Type** : Bug (×2) + Amélioration (×2) — **une seule PR groupée** (décision PO)

> Suite de [bug-grille-du-jour-crash.md](bug-grille-du-jour-crash.md) et
> [bug-grille-mot-refuse-et-ux.md](bug-grille-mot-refuse-et-ux.md). Plan détaillé
> validé PO : `.context/attachments/kRhfzo/plan.md`.

## Problèmes remontés en prod (PO)

1. **Freeze (critique)** — après un mot valide, la case se fige (clavier mort),
   il faut killer l'app. Aucune exception Sentry → **hang silencieux** : le POST
   `guess` pouvait tourner ~90 s (timeout 30 s × retries) clavier désactivé, et
   l'échec était avalé (le `.then()` de `_submitGuess` sans `onError`, et un
   `rethrow` qui partait en future non gérée).
2. **Mots valides refusés** (ex. « Italie ») — le dico de validation ne contenait
   quasi aucun nom propre.
3. **Lien Actu du jour pas clair** — indice discret seulement après 2 échecs, et
   `_goToActus` envoyait vers l'accueil flux (pas la page complète des actus).
4. **Reveal pas lié à un vrai article** — `word` + `pourquoi` codés en dur.

## Correctifs

### A — Anti-freeze (fiabilité du POST guess)
- Timeout dédié **12 s** (`ApiConstants.grilleGuessTimeout`) sur `submitGuess`.
- `GrilleState.networkError` (transitoire) → message ré-essayable « Connexion
  difficile — réessaie. », clavier réactivé (`submitting=false`).
- `submitGuess` : **plus de `rethrow`** (source du hang) → pose `networkError`,
  puis **self-heal** `_reconcileToday()` (re-`getToday` sans `AsyncLoading`).
- `_submitGuess` (écran) : `onError`/`catchError` → plus de future non gérée ; un
  essai en erreur réseau n'est pas tracé « valide ».
- **Backend idempotent** : un re-`submit` du même dernier mot (partie en cours)
  renvoie le résultat recalculé **sans ré-append** → retry réseau sûr.

### B — Dictionnaire élargi (mots valides refusés)
- **NOUVEAU** `app/data/grille_proper_nouns_fr.txt` — noms propres curés (pays,
  régions, capitales/villes, prénoms). Build : `_proper_nouns()` unionné.
- **Constat code-time** : `an-array-of-french-words` couvre **déjà les
  conjugaisons** (FINIES, COURUS, IRIONS, AURAIT… vérifiés) → pas de 2ᵉ source
  inflectée (on évite Lexique383, **CC BY-SA share-alike**, peu compatible avec
  un asset embarqué d'app fermée). Le besoin réel (Italie) est couvert par les
  assets curés.
- `grille_words_fr.txt` régénéré et committé (+85 → 13 987 mots).

### C — CTA « Actu du jour » évident
- `_goToActus` → page complète `…/section/essentiel` (`DigestSectionScreen`).
- **CTA toujours visible** « Lire l'actu du jour » (ghost) dans le bloc bas du
  jeu (plus besoin de 2 échecs). Indice discret conservé (nudge complémentaire).
- Label résultat harmonisé.

### D — Reveal lié à un vrai article (auto-matching)
- **Migration** `gr02_grille_featured_article` (additive, nullable, FK
  `ON DELETE SET NULL`) : `featured_content_id/title/excerpt/url/source/matched_at`.
- **Matcher** `app/services/grille_matcher.py` : score mot/thème vs label + thème
  + titre actu (`matches_word_boundary` mot-entier > sous-chaîne pour flexions),
  fige un snapshot. Hooké best-effort dans `DigestGenerationJob.run()` (try/except
  + Sentry, n'altère jamais le digest ; idempotent).
- Schémas/service : `featured*` exposés **gated fin de partie** (comme `mot`).
- Mobile : champs `featured*` (freezed régénéré), result-view affiche vrai
  titre + extrait + source (fallback `pourquoi`), bouton « Lire l'article » →
  détail in-app. Analytics `grille_article_tapped`.

## Vérification
- Backend : 62 tests verts (`test_grille_api`, `_logic`, `_seed`, `_matcher`,
  `test_digest_generation_job`). `ruff check app/` + `ruff format` clean.
- Alembic : 1 head (`gr02`), round-trip `upgrade head`/`downgrade` OK sur DB vide.
- Mobile : 43 tests grille verts, `flutter analyze` clean (hors warning
  pré-existant `carte_cta.dart`).
