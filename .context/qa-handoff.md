# QA Handoff — « Rattraper » : nudge éphémère + point rouge « pas à jour »

> Rempli par l'agent dev. Input de /validate-feature. Story : `docs/stories/core/9.7.essentiel-rattraper-signal.md`.
> (Handoff précédent « Lettres passées à parité visuelle » archivé dans
> `.context/qa-handoff-lettres-parite.md`.)

## Feature développée

L'en-tête de la carte « Ton Essentiel » n'affiche plus « Rattraper » en
permanence. En today à jour → icône ⏪ seule. Si l'édition d'hier (J-1) n'a pas
été ouverte → point rouge persistant sur ⏪ + le texte « Rattraper ? » qui
apparaît en fondu (~1 s), tient 2 s, disparaît en fondu, au plus 1×/jour. Sur
une lettre passée → « Revenir » fixe (inchangé).

## PR associée

_(à compléter à l'ouverture de la PR)_

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flux Continu — carte « Ton Essentiel » (en-tête, déclencheur rewind) | onglet Essentiel | Modifié |

## Scénarios de test

> ⚠️ L'état « en retard » dépend des streaks (J-1 `opened == false`), difficile
> à forcer sur le build web sans backend/streaks peuplés. **La preuve principale
> = les widget tests** (`essentiel_hi_fi_card_test.dart`,
> `ephemeral_rattraper_label_test.dart`, `edition_read_status_provider_test.dart`).
> Playwright couvre surtout le rendu « à jour » et le tap ⏪ → timeline.

### Scénario 1 : à jour (happy path) — header épuré
**Parcours** :
1. Ouvrir l'app, onglet Essentiel (today), utilisateur à jour.
2. Observer l'en-tête à droite du titre « Ton Essentiel ».
**Résultat attendu** : icône ⏪ **seule**, aucun texte « Rattraper », aucun point
rouge. Tap sur ⏪ → la timeline « Remonter le temps » s'ouvre.

### Scénario 2 : en retard — point rouge + nudge éphémère
**Parcours** :
1. Utilisateur ayant manqué l'édition d'hier (J-1 non ouverte).
2. Ouvrir l'onglet Essentiel (today).
**Résultat attendu** : **point rouge** vif sur ⏪ (persistant) ; **~1 s** après,
« Rattraper ? » apparaît en fondu, **tient 2 s**, disparaît en fondu. Ne se
rejoue **pas** dans la journée (gate 1×/jour). Le point rouge, lui, reste.

### Scénario 3 : lettre passée — « Revenir » fixe
**Parcours** :
1. Ouvrir la timeline, sélectionner « Hier ».
**Résultat attendu** : l'en-tête montre « Revenir » **fixe** (sans point rouge,
sans animation).

### Scénario 4 : reduce-motion / accessibilité
**Parcours** :
1. Activer « Réduire les animations » (OS), état « en retard ».
**Résultat attendu** : le point rouge reste (signal immobile) ; le texte animé
« Rattraper ? » **n'est pas joué**.

## Critères d'acceptation

- [ ] À jour → icône ⏪ seule (ni libellé fixe, ni point, ni nudge).
- [ ] En retard → point rouge persistant + « Rattraper ? » fondu-in ~1 s / tient
  2 s / fondu-out, au plus 1×/jour.
- [ ] Lettre passée → « Revenir » fixe, sans point.
- [ ] ⏪ toujours tappable (ouvre la timeline) dans tous les états ; cible ≥ 24 px.
- [ ] Reduce-motion → pas d'animation de texte.
- [ ] Aucun faux positif au cold-boot / nouvel utilisateur (streaks indispo).

## Zones de risque

- Frontière de jour 07h30 Paris vs off-by-one streaks (déjà assumé par la
  timeline existante ; cf. `.context/streaks-health-handoff.md`).
- Gate 1×/jour persisté au moment du fondu-in (prefs
  `essentiel_rattraper_nudge_last_shown_v1`).

## Dépendances

- Aucun endpoint / migration. Réutilise `editionReadStatusProvider` (streaks).
