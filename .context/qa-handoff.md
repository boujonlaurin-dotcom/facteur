# QA Handoff — Reco médias onboarding « interest-aware » + polish copy

## Feature développée

Les médias recommandés pendant l'onboarding (deck à swiper + carrousel « Tes
médias, sur mesure ») tiennent maintenant compte de ce que chaque source
**publie réellement** (`coverage_themes`), pas seulement de son étiquette : une
source sans lien avec les thèmes cochés ne peut plus remonter grâce à ses seuls
bonus de fiabilité/volume ni à son audience. Plus quelques polish copy
(majuscules, vocabulaire, loader nommé, emphase du lien manifeste).

## PR associée

À créer (`--base main`). Story : `docs/stories/core/onboarding.reco-interest-aware.md`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Welcome (page 1, manifeste) | `/onboarding` (question 0) | Modifié (copy + emphase lien) |
| Concentration des médias | `/onboarding` (Section 1) | Modifié (copy) |
| Swipe désambiguateur | `/onboarding` (avant sources) | Modifié (deck + loader) |
| Sources « sur mesure » | `/onboarding` (Q9) | Modifié (ordre suggestions + loader) |

## Scénarios de test

### Scénario 1 : parcours non-sport (happy path)
**Parcours** :
1. Démarrer un onboarding neuf (session anonyme).
2. Choisir des thèmes **sans Sport** (ex. Tech + Société).
3. Dérouler jusqu'au swipe désambiguateur, puis jusqu'à la page sources.
**Résultat attendu** : ni l'Équipe ni une généraliste très sportive
(Ouest-France) n'ouvre le deck ni la liste « Tes suggestions » ; les premières
cartes portent des thèmes/sujets cochés.

### Scénario 2 : page 1 (manifeste)
**Parcours** : ouvrir l'onboarding, lire le bouton, le déplier, le replier.
**Résultat attendu** : « Lire notre manifeste » (pas de double majuscule), lien
en couleur d'accent + demi-gras, dépliage inline inchangé ; à l'intérieur :
« Notre manifeste », « Le projet », « Notre mission », « Notre approche ».

### Scénario 3 : écran concentration des médias
**Résultat attendu** : « médias » n'apparaît plus que 2 fois ; la fin de phrase
est « ... pour mieux **diversifier tes sources**. »

### Scénario 4 : loader de recherche
**Parcours** : entrer sur le swipe / la page sources avec un réseau lent
(throttling) pour attraper l'état de chargement.
**Résultat attendu** : spinner sobre + « Recherche de tes médias » + « Basé sur
tes intérêts » (plus de spinner nu).

### Scénario 5 : edge case « Passer » les thèmes
**Parcours** : sauter la sélection de thèmes.
**Résultat attendu** : comportement historique — suggestions garnies par la
fiabilité, aucune liste vide.

### Scénario 6 : edge case swipe-like hors-intérêt
**Parcours** : dans le deck, glisser à droite une source hors des thèmes cochés.
**Résultat attendu** : elle se retrouve bien dans les suggestions / pré-cochée
(le signal révélé prime sur la pénalité).

## Critères d'acceptation

- [ ] Aucune source clairement hors-intérêt en tête du deck ni des suggestions.
- [ ] Une généraliste matchée mais diluée reste proposée, mais après les sources
      focalisées.
- [ ] « Passer » les thèmes ⇒ aucune régression (liste non vide).
- [ ] Copy : plus de doubles majuscules page 1, « diversifier tes sources »,
      loader nommé.
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## Zones de risque

- **Effet de bord voulu** : le catalogue mobile reçoit pour la première fois
  `secondary_themes`, `granular_topics` et `source_tier`. Les badges
  « Spécialisé en X » et la section « Pépites » (tier `deep`) vont s'activer
  alors qu'ils ne renvoyaient rien : vérifier qu'ils s'affichent proprement
  (pas de doublon, pas de débordement de carte).
- `coverage_themes` est NULL pour ~50/124 sources curées : ces sources doivent
  rester proposées (couverture inconnue = jamais pénalisante).
- Le deck peut contenir moins de cartes qu'avant sur un thème très pauvre (les
  hors-intérêt ne remplissent plus les pôles) : vérifier qu'il n'est jamais vide.

## Dépendances

- `GET /sources` (catalogue) : le champ `coverage_themes` doit être présent dans
  la réponse, ainsi que `secondary_themes` / `granular_topics` / `source_tier`.
- Aucune migration Alembic.
