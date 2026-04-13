# PR — Fusion "De quoi on parle" dans "Pas de recul" + wiring env tests

Branche : `claude/remove-digest-section-jCCzy` → `main`
Commits :
- `ca0b858` refactor(digest): merge "De quoi on parle" into "Pas de recul" card
- `72f6871` chore(env): wire Flutter + pytest paths in test hooks

---

## Quoi

Deux changements distincts sur la même branche :

1. **Refactor UI digest (ca0b858)** — Suppression de la sous-carte grise *"De quoi on parle ?"* qui précédait la carte *"Pas de recul"*. L'`intro_text` du topic est désormais affiché **en tête** de la carte "Pas de recul" (même carte, sans cadre additionnel). Le champ `recul_intro` (phrase italique d'accroche vers l'article de recul) est supprimé de toute la stack (prompts LLM, schémas Pydantic, pipeline, serializer DB, modèles Flutter, widgets, tests) car redondant avec la phrase 2 de `intro_text`.
2. **Chore env (72f6871)** — Les hooks `post-edit-auto-test.sh` et `stop-verify-tests.sh` utilisent maintenant des chemins absolus vers `./.venv/bin/pytest` et `/opt/flutter/bin/flutter`, avec `PYTHONPATH` et `CI=true` pré-configurés, pour que les tests se lancent correctement depuis les hooks Claude Code.

## Pourquoi

**Refactor** : L'ancienne UI affichait deux cartes contiguës pour un même topic (gris "De quoi on parle" + bleu "Prendre du recul"), ce qui créait une lourdeur visuelle (deux bordures, deux couleurs, deux paragraphes) pour une info logiquement continue — le texte du topic **fait le pont** vers l'article de recul. Par ailleurs, `recul_intro` dupliquait la fonction de la phrase 2 de `intro_text` (les deux servaient d'accroche vers l'article de recul). Fusionner réduit la dette éditoriale côté LLM (un seul champ à générer) et allège l'écran.

**Env** : Sans chemins absolus, les hooks ne trouvaient ni `pytest` ni `flutter` dans le PATH de l'agent, donc `stop-verify-tests.sh` ne vérifiait rien. Maintenant les hooks s'exécutent réellement.

## Fichiers modifiés

### Backend (ca0b858)
- `packages/api/config/editorial_prompts.yaml` — retrait de `recul_intro` des structures + schemas JSON des prompts `writing` et `writing_serene`. Ajout d'une ligne dans la section PONTS clarifiant que la phrase 2 d'`intro_text` joue le rôle.
- `packages/api/app/services/editorial/schemas.py` — suppression de `recul_intro` sur `MatchedDeepArticle` et `SubjectWriting`.
- `packages/api/app/services/editorial/writer.py` — retrait du mapping `recul_intro` depuis la réponse LLM.
- `packages/api/app/services/editorial/pipeline.py` — retrait du bloc qui propageait `sw.recul_intro` vers `s.deep_article.recul_intro`.
- `packages/api/app/services/digest_service.py` — retrait de la sérialisation/désérialisation de `recul_intro` pour `DigestTopicArticle` (lignes ~1400 et ~1792).
- `packages/api/app/schemas/digest.py` — retrait du champ `recul_intro` sur `DigestTopicArticle` et `DigestItem`.

### Mobile (ca0b858)
- `apps/mobile/lib/features/digest/models/digest_models.dart` — suppression du champ `@JsonKey(name: 'recul_intro') String? reculIntro` sur `DigestItem`.
- `apps/mobile/lib/features/digest/models/digest_models.freezed.dart` — **édité à la main** (13 occurrences : mixin getter, 2 copyWith abstract+impl, constructor, final getter, toString, equals, hashCode) car `build_runner` indisponible dans l'env.
- `apps/mobile/lib/features/digest/models/digest_models.g.dart` — retrait des 2 lignes `recul_intro` (from/to Json) — édité à la main aussi.
- `apps/mobile/lib/features/digest/widgets/pas_de_recul_block.dart` — param renommé `reculIntro` → `introText` ; affiché **en haut de la carte** (non italique, lineHeight 1.5) au-dessus de `title + source`. Dartdoc mise à jour.
- `apps/mobile/lib/features/digest/widgets/topic_section.dart` — suppression complète du bloc "De quoi on parle ?" (≈60 lignes). Remplacé par : soit `PasDeReculBlock(introText: topic.introText, ...)` si un deep article existe, soit un paragraphe discret (padding horizontal 12, fontSize 14, pas de carte) sinon.
- `apps/mobile/test/features/digest/widgets/pas_de_recul_block_test.dart` — tests mis à jour pour `introText`.

### Config / Docs (ca0b858 + 72f6871)
- `docs/maintenance/maintenance-merge-intro-pas-de-recul.md` — doc de maintenance (contexte, objectif, liste des changements, mockup ASCII, cas traités, tests, hors périmètre).
- `.claude-hooks/post-edit-auto-test.sh` — `PYTEST`/`FLUTTER`/`CI=true` + `PYTHONPATH` dans les commandes.
- `.claude-hooks/stop-verify-tests.sh` — idem.
- `apps/mobile/pubspec.lock` — régénéré par `flutter pub get`.

## Zones à risque

1. **`digest_models.freezed.dart` édité à la main** — 13 points de modification mécaniques mais pas régénérés par `build_runner`. Si le reviewer a `build_runner` dispo, il est recommandé de lancer `flutter pub run build_runner build --delete-conflicting-outputs` pour valider qu'il produit le même fichier (ou pour l'écraser proprement).
2. **Pipeline éditorial LLM** — `editorial_prompts.yaml` + `writer.py` + `pipeline.py` : si un digest généré avant cette PR est rechargé depuis DB, `recul_intro` sera silencieusement ignoré (le `.get()` supprimé ne lisait plus) — aucun crash, juste perte du champ orphelin.
3. **Sérialisation DB des digests** — `digest_service.py` n'écrit plus `recul_intro` ; un ancien JSON stocké contient encore la clé mais elle n'est plus lue. Pas de migration nécessaire (JSONB).
4. **Widgets digest** — `topic_section.dart` a perdu une grosse section ; vérifier en runtime sur un topic avec deep article ET sur un topic sans, pour s'assurer que le fallback paragraphe discret s'affiche bien.

## Points d'attention pour le reviewer

- **Cohérence prompts ↔ schémas** — les 2 prompts (`writing` et `writing_serene`) doivent produire du JSON qui colle à `SubjectWriting` sans `recul_intro`. J'ai relu les YAML mais vérifier qu'aucun exemple few-shot n'y fait référence.
- **La phrase 2 d'`intro_text` joue bien le rôle de pont** — c'est déjà le cas dans le prompt existant (section PONTS), mais j'ai ajouté une ligne d'insistance. Si le reviewer juge l'instruction insuffisante, on peut durcir le prompt avec un exemple.
- **UX : paragraphe discret sans carte pour topics sans deep article** — choix délibéré pour préserver `intro_text` sans réintroduire de lourdeur visuelle. Si le PO préfère tout simplement masquer `intro_text` dans ce cas, c'est 3 lignes à retirer dans `topic_section.dart`.
- **Freezed hand-edit** — stratégie à valider. Alternative : régénérer proprement dans un commit de suivi.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Aucune migration Alembic** — `recul_intro` vivait uniquement dans le JSON `topics` de la table digest ; pas de colonne SQL à retirer.
- **Backend API contract** — les endpoints `/digest/*` continuent à renvoyer tous les autres champs à l'identique ; seul `recul_intro` disparaît du payload.
- **Autres blocs éditoriaux** (Pépite, Coup de cœur, Actu décalée, Quote) — non touchés.
- **36 tests Flutter pré-existants en échec sur `main`** — vérifié en stashant et re-testant sur `main` avant cette PR ; ce ne sont PAS des régressions introduites ici (hors périmètre).
- **Tests backend DB-dépendants** (~29) — fail localement faute de Postgres ; CI Postgres les exécutera.

## Comment tester

### Backend
```bash
cd /home/user/facteur/packages/api
PYTHONPATH=/home/user/facteur/packages/api ../../.venv/bin/pytest tests/editorial -v
# -> 85/85 pass attendu
PYTHONPATH=/home/user/facteur/packages/api ../../.venv/bin/pytest -x -q --tb=short
# -> les DB-dep fail, le reste passe
```

### Mobile
```bash
cd /home/user/facteur/apps/mobile
CI=true /opt/flutter/bin/flutter test --no-pub test/features/digest/widgets/pas_de_recul_block_test.dart
# -> tests du widget refactore (introText)
CI=true /opt/flutter/bin/flutter analyze --no-pub
```

### Runtime / visuel (a faire cote reviewer)
1. Lancer un digest qui contient au moins 1 topic avec deep article et 1 topic sans.
2. **Topic avec deep article** : la carte "Pas de recul" doit afficher `intro_text` en haut (paragraphe non italique) puis le titre de l'article + la source + la fleche. Aucune carte grise avant.
3. **Topic sans deep article** : un paragraphe discret (padding lateral, pas de cadre, fontSize 14) affichant `intro_text`. Aucune carte "Pas de recul" en dessous.
4. Generer un nouveau digest via la pipeline LLM (ou forcer un run) et verifier que le JSON produit ne contient plus `recul_intro` et que la phrase 2 d'`intro_text` joue bien le role d'accroche vers l'article de recul.

### Regenerer freezed proprement (optionnel mais conseille avant merge)
```bash
cd /home/user/facteur/apps/mobile
/opt/flutter/bin/flutter pub run build_runner build --delete-conflicting-outputs
git diff lib/features/digest/models/digest_models.freezed.dart
# -> diff attendu : vide (ou cosmetique)
```
