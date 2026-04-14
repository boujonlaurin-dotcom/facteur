# Maintenance — Fusion "De quoi on parle ?" dans "Pas de recul"

> **Branche** : `claude/remove-digest-section-jCCzy`
> **Date** : 2026-04-13
> **Type** : Maintenance (UX + simplification pipeline éditorial)

---

## Contexte

Le digest affiche, pour chaque sujet, deux sous-cartes éditoriales contiguës :

1. **"De quoi on parle ?"** (carte grise, `topic.introText`) — 2 phrases de contexte + pont vers l'article deep
2. **"Pas de recul"** (carte bleue, `deepArticle.reculIntro`) — 1 phrase italique qui relance vers le deep

Ces deux blocs se chevauchent sémantiquement :
- La phrase 2 de `intro_text` fait déjà le pont vers l'article deep (via les tournures `PONTS` du prompt).
- `recul_intro` reprend ce rôle d'accroche vers le deep.

Côté visuel : deux blocs pleins, deux bordures latérales, deux couleurs, deux niveaux hiérarchiques → lourdeur perçue.

## Objectif

Fusionner `intro_text` **dans** la carte "Pas de recul" et supprimer `recul_intro` (champ + prompt).
Pour les sujets **sans article deep**, afficher `intro_text` en paragraphe discret (pas de carte).

## Changements

### Backend (`packages/api`)

| Fichier | Action |
|---|---|
| `config/editorial_prompts.yaml` | Supprimer `recul_intro` des deux prompts `writing` et `writing_serene` (bloc STRUCTURE + schéma JSON attendu). |
| `app/services/editorial/schemas.py` | Retirer `recul_intro` de `MatchedDeepArticle` et `SubjectWriting`. |
| `app/services/editorial/writer.py` | Retirer le champ `recul_intro` du parsing LLM (construction `SubjectWriting`). |
| `app/services/editorial/pipeline.py` | Retirer l'injection `s.deep_article.recul_intro = sw.recul_intro`. |
| `app/services/digest_service.py` | Retirer la sérialisation (`"recul_intro": ...`) et la désérialisation (`recul_intro=art_data.get(...)`). |
| `app/schemas/digest.py` | Retirer `recul_intro: str | None = None` de `DigestTopicArticle` et `DigestItem`. |

Le prompt `writing` conserve le rôle du pont (phrase 2 de `intro_text` + section `PONTS VERS L'ARTICLE DE FOND` existante).

### Mobile (`apps/mobile`)

| Fichier | Action |
|---|---|
| `lib/features/digest/models/digest_models.dart` | Retirer `reculIntro` de `DigestItem`. |
| `lib/features/digest/widgets/pas_de_recul_block.dart` | Remplacer le paramètre `reculIntro` (italique) par `introText` (texte normal). Le bloc accepte désormais le contexte du sujet en en-tête. |
| `lib/features/digest/widgets/topic_section.dart` | Supprimer la carte grise "De quoi on parle ?". Injecter `topic.introText` dans `PasDeReculBlock`. Pour les sujets sans deep article mais avec `introText`, afficher un petit paragraphe discret (sans carte, sans bordure, `textSecondary`). |
| `test/features/digest/widgets/pas_de_recul_block_test.dart` | Renommer les tests `reculIntro` → `introText`. |
| `lib/features/digest/models/digest_models.freezed.dart` + `.g.dart` | Régénérés via `build_runner`. |

### UI finale

```
┌──────────────────────────────────────────┐
│ [badge pas_de_recul]                     │
│ Le mix éolien-solaire espagnol absorbe   │
│ le choc gazier là où d'autres pays       │
│ répercutent la hausse. Vert détaille     │
│ pourquoi ce modèle reste difficile à     │
│ répliquer.                               │
│                                          │
│ Comment les renouvelables...    [thumb]  │
│ Vert →                                   │
└──────────────────────────────────────────┘
```

Pour les sujets **sans deep** (rare), seulement un paragraphe sous les articles actu :

```
  31 ouvertures au premier semestre, un plus bas depuis 2016.
```

## Cas traités

- ✅ Sujet avec deep + intro_text → carte bleue unique avec contexte en haut
- ✅ Sujet avec deep sans intro_text (fallback LLM) → carte bleue sans contexte (title + source + thumb uniquement)
- ✅ Sujet sans deep avec intro_text → paragraphe discret sous les articles actu
- ✅ Sujet sans deep sans intro_text → rien (comportement actuel conservé)

## Tests

- `pytest packages/api` : vérifier que les tests éditoriaux passent après retrait de `recul_intro`
- `flutter test apps/mobile` : tests du `PasDeReculBlock` adaptés (reculIntro → introText)
- `flutter analyze` : pas de warnings

## Hors périmètre

- Pas de migration DB (le champ `recul_intro` n'est pas persisté — il ne vit qu'en mémoire dans la structure `EditorialGlobalContext`).
- Pas de changement de design-system (on réutilise typo + couleurs existantes).
