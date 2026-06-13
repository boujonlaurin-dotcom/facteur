# Maintenance — Cartographie de la pipeline de highlighting (titres perspectives)

> **Date** : 2026-05-19
> **Branche** : `boujonlaurin-dotcom/fix-article-highlight`
> **PR ciblée** : `main`
> **Type** : investigation / outillage (read-only)

## Contexte

Retour utilisateur sur la feature de highlight des titres dans le panneau
"Couverture médiatique" (Story 7.4, perspectives bottom-sheet) :

> Les highlight ne sont pas encore parfaitement calibrés — ils doivent être
> judicieusement choisis, de façon parcellaire, pour vraiment amener un
> éclairage précis.

La pipeline actuelle (`TitleAnnotationService`) est 100 % déterministe :
spaCy POS + lemmatisation + filtrage stopwords FR + overlay NER, cap à 4
spans par titre, priorité `entity > ADJ > NOUN/PROPN > VERB`.

Avant de la modifier, on a besoin d'**observer concrètement** sa sortie sur
des clusters réels récents et de la comparer à un highlighting "cible"
défini manuellement avec le PO.

## Décision

1. **Pas de modification de la pipeline dans cette PR.** Outillage
   uniquement, read-only.
2. **Pas d'intégration Mistral** ici (phase 2 Story 7.4 reste dormante).
   La décision sera prise après cartographie.
3. **Pas de modif UI** dans cette PR (le quick-win UI "tout noir" est
   prévu séparément).

## Livrables

1. **Script** `packages/api/scripts/inspect_title_annotations.py`
   - Sélectionne les N clusters récents les plus actifs (fenêtre 7 jours,
     paramétrable).
   - Pour chaque cluster, choisit une référence (article du milieu de
     fenêtre, ou le plus récent — paramétrable) et roule la pipeline
     existante (`TitleAnnotationService.compute_strong_tokens_batch`,
     `diff_spans`, `compute_shared_tokens`, `compute_reference_pivot`).
   - Génère un rapport Markdown lisible avec sections vides "Cible
     attendue" pour annotation manuelle.

2. **Premier rapport** `.context/highlight-cartography-<date>.md`
   - Généré à partir de la prod (compte read-only `claude_analytics_ro`).
   - Servira de support à la séance d'annotation manuelle avec le PO.

## Tâches

- [x] Doc maintenance créée
- [x] Script `inspect_title_annotations.py` écrit
- [x] Smoke test local (5 pseudo-clusters générés : Cannes, Bolloré, Trump, Darmanin, Ebola)
- [x] Premier rapport `.context/highlight-cartography-2026-05-19.md`
- [ ] PR ouverte vers `main` (via `/go`)

## Découvertes faites pendant la cartographie

1. **`Content.cluster_id` n'est JAMAIS persisté en prod** (vérifié 2026-05-19 :
   0 / 41 308 rows). Le clustering tourne en mémoire via `find_hot_cluster`
   (`packages/api/app/services/article_clustering_service.py`). Le script
   pivote sur un pseudo-clustering entity-based (PERSON / ORG / EVENT)
   pour rester fidèle à ce qui tourne en prod.

2. **Le rôle `claude_analytics_ro` exposé dans l'env du workspace
   conductor (`DATABASE_URL_RO`) ne voit aucune row de `contents`**
   (probablement filtré par RLS). Pour lancer le script directement
   contre la DB, il faut un rôle avec SELECT non-filtré (admin ou
   `supabase_read_only_user` exposé via le MCP). Le mode `--input
   <dump.json>` contourne ce blocage : on génère le dump via une requête
   SQL MCP puis on lance le script localement.

3. **`Content.entities` est un `text[]` de JSON strings** (pas du JSONB
   structuré). Parse via `app.services.article_clustering_service.parse_entities`.

## Suite (hors-scope de cette PR)

- Séance d'annotation manuelle (cible attendue par cluster).
- PR séparée : ajustements chirurgicaux dans `TitleAnnotationService`
  (cap, priorités, filtres) une fois la cible définie.
- PR UI : texte uniforme noir dans `DiffTitle` (déjà planifiée).
