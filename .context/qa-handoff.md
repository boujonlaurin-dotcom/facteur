# QA Handoff — Story 21.2 — Ranking personnalisé sur sections thématiques de la Tournée

## Feature développée

Sur les 2 sections "Thème personnel" du Flux Continu (V1.8, Story 21.1), les articles sont désormais triés via `PillarScoringEngine` (intérêts pondérés Story 22.1 + affinité source + fraîcheur hiérarchisée + qualité) au lieu d'un tri par récence pure. Le change est 100% backend (`recommendation_service.py`) — aucune modif mobile.

## PR associée

À créer via `/go` après cette validation.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flux Continu (home) | `/flux-continu` | Sections #3 et #4 (Thème perso #1 / #2) — ordre des articles dans le hero + carrousel |
| Feed exploration thème (chip) | `/feed?theme=X` | **Doit rester inchangé** (test de non-régression) |

## Scénarios de test

### Scénario 1 : Happy path — un favori avec subtopics priorisés

**Pré-requis seed** : utilisateur connecté avec :
- Favori thème : `tech` (state=favorite, weight ≥ 1.5)
- Subtopic favori : `ai` (poids 3.0) et `startups` (poids 0.5) dans `user_subtopics`
- Au moins 1 source `tech` suivie

**Parcours** :
1. Ouvrir la home → Flux Continu charge.
2. Scroller jusqu'à la section "Thème perso #1" (label "Tech" ou équivalent).
3. Observer l'ordre des articles (hero + cartes carrousel).

**Résultat attendu** :
- Les articles dont `Content.topics` overlap avec `ai` ressortent en tête (premier hero + cartes suivantes).
- Un article `ai` publié il y a 18h doit passer devant un article `startups` publié il y a 2h (à match de qualité source équivalent).
- Les articles ont un `recommendation_reason` non-vide (visible si le composant `RecommendationReasonChip` est utilisé).

### Scénario 2 : Non-régression du path exploration ("tout voir" / chip)

**Parcours** :
1. Depuis le Flux Continu, taper sur la chip `Tech` dans la zone Explorer (bottom).
2. Observer l'ordre des articles affichés (vue exploration thème, pas la section Tournée).

**Résultat attendu** :
- Ordre strictement chronologique (article le plus récent en haut).
- Pas de restriction sur sources suivies (articles de sources non-suivies présents).
- Comportement IDENTIQUE à avant cette PR.

### Scénario 3 : Pagination stable "Plus de…"

**Parcours** :
1. Sur la section "Thème perso #1", taper sur le CTA "Plus de…" (`PlusDeButton`).
2. Comparer la liste étendue avec la liste initiale.

**Résultat attendu** :
- Aucun doublon entre la section initiale (top 10) et la pagination suivante.
- L'ordre des articles reste déterministe entre 2 chargements successifs de la même session (`temperature=0` sur ce path).

### Scénario 4 : User sans subtopic favori (signal faible)

**Pré-requis** : utilisateur avec favori thème `tech` mais aucun `user_subtopic_weights`.

**Parcours** :
1. Ouvrir la home → section Tech.

**Résultat attendu** :
- La section n'est PAS vide.
- Les articles sont triés par Pilier Source (followed/curated en tête) puis Fraîcheur.
- Le rendu visuel reste cohérent (pas de fallback explicite à la chronologie pure attendu — le scoring tourne avec moins de discrimination).

### Scénario 5 : User sans aucune source suivie sur ce thème

**Pré-requis** : utilisateur avec favori thème `tech` mais aucune source `tech` suivie.

**Parcours** :
1. Ouvrir la home → section Tech.

**Résultat attendu** :
- La section n'est PAS vide (fallback curated activé dans `_get_candidates`).
- Les articles affichés proviennent de sources curated `tech` (pas du tier `deep`).

## Critères d'acceptation

- [ ] Section Theme #1 reflète les préférences user (Scénario 1)
- [ ] Section Theme #2 reflète les préférences user (idem)
- [ ] Path exploration chip thème inchangé (Scénario 2)
- [ ] Pagination stable, pas de doublons (Scénario 3)
- [ ] Pas de section vide même avec signal faible (Scénarios 4-5)
- [ ] Latence home ressentie acceptable (< +300ms par rapport à avant — les 2 calls theme étant parallèles)
- [ ] Aucune erreur console mobile / network 5xx sur `/api/feed/?theme=X&personalized=true`

## Zones de risque

- **Latence** : ajout du `PillarScoringEngine` + `_batch_scoring_context` introduit ~100-230ms sur chaque call theme. À mesurer p95 sur Sentry / Railway logs après merge (filtrer `feed_phase4_scoring` avec `mode="personalized_theme"`).
- **Ordre perçu "étrange"** : un article de 22h en tête peut surprendre si la maquette n'explique pas la logique. À surveiller en feedback utilisateur. Le pilier Fraîcheur garde un bonus +25 sur <24h donc le décalage reste borné.
- **Performance pool candidats** : la fenêtre 24h + followed-only borne le pool entre 30-150 articles ; pas de risque de scoring sur >500 candidats.

## Dépendances

- Endpoint backend : `GET /api/feed/?theme=<slug>&personalized=true&limit=10` (et `topic=<UUID>&personalized=true` pour custom topics favoris)
- Service : `app.services.recommendation_service.RecommendationService.get_feed`
- Helper testable : `app.services.recommendation_service.is_personalized_theme_mode`
- Log structuré à monitorer : `feed_phase4_scoring` avec champ `mode="personalized_theme"`

## Notes pour l'agent QA Chrome

- Viewport 390x844 (mobile).
- Le mode "Serein" toggle peut être ON ou OFF — les sections "Thème perso" existent dans les 2 cas (positions différentes selon `_compose(isSerene)`).
- Pour seed rapide : utiliser un compte existant et patcher les favoris via `/api/user-interests/...` (Story 22.1) ou via l'UI "Mes intérêts".
