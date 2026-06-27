# QA Handoff — Rituel matinal « Ton édition vient d'arriver » (Story 28.1)

> Input pour `/validate-feature` (Playwright Agent CLI, skill `facteur-qa-web`, viewport 390×844,
> sémantique activée au boot — build web Flutter = canvas).

## Feature développée
Écran d'ouverture quotidien `/edition` : au premier open du jour (après la bascule 7h30 Paris), un
écran enveloppe « Bonjour / Ton édition du {date} vient d'arriver » s'affiche instantanément, révèle
le **sommaire des sections réelles** du jour + un CTA « Ouvrir l'édition », puis traverse un loader
de 2 s avant d'arriver en fondu sur l'Essentiel. 1×/jour ; les opens suivants vont droit au feed.

## PR associée
<!-- à compléter après /go -->

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| MorningRitualScreen | `/edition` | Nouveau |
| Essentiel (Flux Continu) | `/flux-continu` | Cible de redirection (inchangé) |
| Gate redirection | `routerProvider` / `postAuthHomePath` | Modifié |

## Scénarios de test

### Scénario 1 : Happy path — édition prête
1. Premier open du jour (édition du jour disponible / préchargée).
2. L'app atterrit sur `/edition` : « Bonjour. » + « Ton édition du {date} vient d'arriver. » s'affichent
   **immédiatement, sans spinner**.
3. Le sommaire apparaît en fondu sous « L'Essentiel du jour » : libellés réels des sections
   (ex. « Technologie · Actus du jour · Mot du jour · Bonnes Nouvelles »), + « Reçue à 7h00 » + CTA.
4. Tap « Ouvrir l'édition ».
**Résultat attendu** : micro-chargement (loader vélo + citation) ~2 s, puis fondu vers `/flux-continu`
avec l'Essentiel déjà prêt. Le sommaire reflète exactement les sections rendues dans le feed (même
ordre, « Mot du jour » au même emplacement que La Grille).

### Scénario 2 : 2ᵉ open le même jour → pas de rituel
1. Après avoir ouvert l'édition (scénario 1), relancer un open (revenir au splash / relancer).
**Résultat attendu** : redirection **directe** vers `/flux-continu` (ou `/flaner` si closing déjà
dismissée). L'écran `/edition` n'apparaît pas.

### Scénario 3 : Édition pas prête (réseau froid / avant 7h)
1. Forcer un état où l'édition du jour n'est pas prête (digest absent / stale / d'hier).
**Résultat attendu** : « Bonjour + date » seul (jamais de fausse promesse), pas de sommaire ni de CTA
actif ; après un délai borné (~4 s) → redirection vers `/flux-continu` **sans** marquer « vu »
(le rituel reviendra au prochain open une fois l'édition arrivée).

## Critères d'acceptation
- [ ] Rendu instantané du greeting (zéro spinner au repos).
- [ ] Sommaire = libellés exacts des sections réellement affichées, même ordre que le feed,
      « Mot du jour » inséré à la position de La Grille, héros exclu.
- [ ] CTA non interactif tant que l'édition n'est pas prête ; interactif dès qu'elle l'est.
- [ ] Tap CTA → loader ~2 s → fondu vers Essentiel.
- [ ] 1×/jour : 2ᵉ open saute le rituel.
- [ ] Édition pas prête → feed sans marquer « vu ».
- [ ] Console sans erreur ; réseau sans 4xx/5xx inattendu ; **aucun appel réseau lancé par l'écran**
      (lecture seule de l'état préchargé).

## Zones de risque
- **Router** (`postAuthHomePath` / redirect) : vérifier l'absence de rebond / boucle entre `/edition`,
  `/splash` et `/flux-continu`. Le rituel ne doit **pas** apparaître juste après l'onboarding.
- Cache SWR d'hier : ne jamais montrer le rituel sur du contenu périmé (`dayKey` + `isStaleFallback`).
- Reduce motion : fondu simplifié.

## Dépendances
- Aucun nouvel endpoint. Lit l'état déjà préchargé (`/digest/both`, `/top-themes`, `/essentiel`,
  feed) via `fluxContinuProvider` / `digestProvider`. Aucune migration, aucun changement backend.
- Analytics PostHog : `morning_ritual_shown`, `morning_ritual_opened`, `morning_ritual_skipped_not_ready`.
