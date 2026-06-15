# QA Handoff — Fiche source v3 (endpoint `/profile` unifié + fréquence + cartes article cliquables)

> Rempli par l'agent dev après VERIFY. Input de `/validate-feature` (agent QA Chrome).

## Feature développée
La fiche source (bottom sheet) devient un vrai signal produit : un endpoint unifié
`GET /sources/{id}/profile` alimente en un seul appel la couverture par thèmes, le volume
30 jours, la **fréquence de publication** (nouveau chip horloge dans le header) et les
**3 articles récents** rendus en carte standard `FluxContinuArticleCard` (cliquables →
reader, read-sync, aperçu en appui long). L'évaluation reste reléguée, repliée.

## PR associée
<!-- À compléter après ouverture : gh pr view --web -->
Branche : `boujonlaurin-dotcom/source-profile-endpoint` (base `main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Fiche source (bottom sheet `SourceDetailModal`) | ouverte depuis Sources, Flâner, reader (chip source), thèmes, pépites, onboarding | Modifié |
| Reader article (`ContentDetailScreen`) | `/flux-continu/content/:id` | Cible du tap sur une carte article (existant) |

## Scénarios de test

### Scénario 1 : Happy path — source active riche
**Parcours** :
1. Ouvrir la fiche d'une source qui publie beaucoup (ex. Le Monde) via l'onglet Sources ou une chip source dans le reader.
2. Observer le header.
3. Faire défiler jusqu'aux sections « Couverture par thèmes » et « Derniers articles ».
4. Taper sur une carte article.
**Résultat attendu** :
- Header : nom + domaine + signal « Suivi par N lecteurs » **et** chip horloge fréquence (ex. « ~100/jour », « quelques-uns/semaine »).
- Couverture : barres par thème (label + barre + %), caption « N articles publiés sur la période ».
- Derniers articles : jusqu'à 3 cartes `FluxContinuArticleCard` (logo source, titre, méta), alignées avec le reste de la fiche.
- Tap sur une carte → ouvre le reader de l'article ; au retour, la carte porte le badge « lu » (read-sync).
- Appui long sur une carte → aperçu (preview overlay).

### Scénario 2 : Edge case — source fraîche / sans articles / éval absente
**Parcours** :
1. Ouvrir une source très récente (peu d'historique) → vérifier que la fréquence n'est pas sous-estimée (fenêtre clampée à l'âge réel).
2. Ouvrir une source sans contenu → section articles = carte « Aucun article récent. », couverture masquée.
3. Ouvrir une source non évaluée → bloc « Évaluation Facteur » affiche « Pas encore évaluée », reste repliée.

### Scénario 3 : Cas d'erreur — `/profile` injoignable (fallback gracieux)
**Parcours** :
1. Couper le réseau (ou simuler une 5xx) puis ouvrir une fiche source.
**Résultat attendu** : la sheet ne bloque **jamais**. Fallback statique = header (sans chip
fréquence) + évaluation + réglages (si suivie) + gestion + actions. Couverture / articles /
fréquence masqués. Aucun spinner infini, aucun crash.

### Scénario 4 : Mode smart-search inchangé (non-régression)
**Parcours** :
1. Depuis « Ajouter une source » (smart-search), ouvrir la fiche d'un résultat.
**Résultat attendu** : comportement v2 intact — couverture via `/coverage`, articles en carte
minimale (non cliquable), pas de chip fréquence, pas de FluxContinuArticleCard.

## Critères d'acceptation
- [ ] Chip fréquence visible et cohérent avec le volume réel (mode normal, source connue).
- [ ] 3 cartes article standard cliquables → reader + read-sync + preview appui long.
- [ ] Couverture par thèmes : barres + % + caption corrects.
- [ ] Évaluation repliée par défaut, « à titre indicatif ».
- [ ] Fallback statique sur erreur réseau (jamais de blocage).
- [ ] Mode smart-search non régressé (cartes minimales, pas de chip).
- [ ] 8 call sites de `SourceDetailModal` intacts (constructeur inchangé).

## Zones de risque
- **Couplage `FluxContinuArticleCard` dans une sheet scrollable** : vérifier que le swipe
  horizontal (swipe-to-open) ne crée pas de conflit avec le scroll vertical de la sheet, et
  que tap → reader fonctionne. Si effet de bord, préférer un flag `interactive:false` plutôt
  qu'un fork (cf. plan).
- **Navigation depuis la sheet** : le tap pousse le reader sur le root navigator
  (`RouteNames.contentDetail`) ; la sheet doit rester vivante dessous (retour OK).
- Alignement visuel des cartes (padding +4px pour compenser les 12px internes de la carte).

## Dépendances
- Backend : `GET /api/sources/{source_id}/profile` (nouveau, auth requise). Aucune migration DB.
- Endpoints `/coverage` et `/recent-items` conservés (autres consommateurs).
- Providers mobile : `sourceProfileProvider` (nouveau, autoDispose) ; `sourceRecentArticlesProvider` supprimé ; `sourceCoverageProvider` conservé (smart-search).
