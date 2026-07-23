# QA Handoff — Tournée vivante : suggestions garanties + CTA (Story 22.6)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/22.6.tournee-suggestions-garanties-cta.md`.

## Feature développée

La Tournée du jour garantit désormais un accent quotidien de 4-5 sections
« Choisie pour vous » **pour tous les comptes** (même 8+ favoris), avec un quota
de 3 suggestions visibles sous le cap d'affichage pour les comptes personnalisés,
et un CTA direct « Ajouter à mon Essentiel » sur chaque carte suggérée.

## PR associée

À créer via `/go` (base `main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée du jour / Flux Continu | `/flux-continu` | Modifié |
| Sheet « Pourquoi cette section ? » | overlay | Inchangé (toujours fonctionnel) |

## Scénarios de test

### Scénario 1 : Happy path — CTA sur la carte suggérée
**Parcours** :
1. Ouvrir la Tournée du jour avec un compte qui reçoit des suggestions.
2. Repérer une section badgée « Choisie pour vous ».
3. Taper le bouton « Ajouter à mon Essentiel » en pied de carte.
**Résultat attendu** : spinner bref, SnackBar « Ajouté à ton Essentiel », la
section devient favorite (badge « Choisie pour vous » disparaît), l'ordre des
autres favoris n'est **pas** permuté.

### Scénario 2 : Quota visible (compte personnalisé)
**Parcours** :
1. Compte avec un ordre de Tournée personnalisé et beaucoup de favoris (proche
   du cap 13).
2. Ouvrir la Tournée.
**Résultat attendu** : exactement 3 sections « Choisie pour vous » restent
visibles en queue, sous le cap — elles ne sont plus toutes coupées.

### Scénario 3 : Dismiss d'une suggestion
**Parcours** :
1. Sur une section suggérée, ouvrir le « i » du badge → sheet.
2. Choisir « Retirer » (dismiss).
**Résultat attendu** : la section disparaît (retrait local réversible) ; une
autre suggestion coupée par le cap peut remonter à sa place.

### Scénario 4 : Anti double-tap
**Parcours** :
1. Taper rapidement 2× le bouton « Ajouter à mon Essentiel ».
**Résultat attendu** : une seule promotion (bouton désactivé pendant l'attente),
une seule SnackBar.

## Critères d'acceptation

- [ ] 4-5 suggestions/jour garanties, y compris pour un compte 8+ favoris.
- [ ] ≥3 suggestions visibles sous le cap pour un compte personnalisé, ordre des
  favoris préservé.
- [ ] CTA « Ajouter à mon Essentiel » rendu uniquement sur les sections suggérées.
- [ ] La sheet « Pourquoi cette section ? » (garder/retirer) reste fonctionnelle.
- [ ] Pas d'em-dash dans la copy visible.

## Zones de risque

- Ordre des favoris jamais permuté par l'insertion du quota (vérifier visuellement).
- Sections éditoriales (Actus, Bonnes, Grille) : sur un compte très chargé elles
  peuvent être repoussées hors cap (comportement pré-existant, non aggravé).
- Instrumentation PostHog : impression dédupliquée 1×/section/jour (persistée) —
  non visible à l'écran mais à ne pas casser.

## Dépendances

- Backend `GET /api/users/top-themes` (plancher de suggestions, aucune migration).
- Events PostHog : `suggestion_impression`, `suggestion_promoted`,
  `suggestion_dismissed`.
