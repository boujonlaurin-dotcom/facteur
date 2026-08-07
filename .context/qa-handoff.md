# QA Handoff — PR-4 : ordre des blocs de la Tournée par le score top-3

> Rempli par l'agent dev. Input de `/validate-feature`. Lot :
> `docs/maintenance/maintenance-reco-optimisation-lot2.md` (§ PR-4).

## Feature développée

Les blocs de la Tournée (thèmes, sources, veille, « Choisie pour vous ») ne sont
plus simplement **dépriorisés** quand ils sont maigres : ils sont **triés par la
somme des 3 meilleurs `score_total` de leurs articles**. Les slots manquants
comptant 0, un bloc à 1 article coule structurellement (≈ 1 × s contre 3 × s)
sans avoir besoin d'être un cas spécial.

L'ordre est calculé **une seule fois par journée tournée** (frontière 07h30
Paris), à la complétion du fan-out, puis **gelé et persisté** — aucun bloc ne
bouge pendant le remplissage progressif ni pendant la session.

En prime, le champ `block_score` de l'event `article_impression` (PR-1), qui
valait `null` en prod, est désormais renseigné : c'est lui qui reliera « ordre
des blocs » et « CTR mesuré ».

## PR associée

À créer (`--base main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée du jour (Flux continu) | `/flux-continu` | Modifié — **ordre** des blocs sous la carte héros |

Aucun nouveau composant, aucune nouvelle UI : seuls l'**ordre** des sections et
le contenu d'un event analytics changent.

## Scénarios de test

### Scénario 1 — Cold boot : aucun bloc ne saute pendant le remplissage
**Parcours** :
1. Vider les données de l'app (ou franchir 07h30), ouvrir la Tournée.
2. Observer la page pendant tout le remplissage progressif (~10-15 recompositions).

**Résultat attendu** : les blocs se remplissent **en place**, dans l'ordre par
défaut. Une **seule** réorganisation survient, à la toute fin, quand tout est
chargé. Aucun saut au milieu du remplissage.

### Scénario 2 — Ré-ouverture dans la même journée
**Parcours** :
1. Après le scénario 1, quitter l'app et la rouvrir (puis pull-to-refresh).

**Résultat attendu** : l'ordre est **identique** à celui de la fin du scénario 1,
et il l'est **dès la première frame de contenu** — aucune réorganisation visible,
même après le refresh.

### Scénario 3 — Les blocs pauvres sont en bas
**Parcours** :
1. Ouvrir la Tournée avec des favoris dont au moins un ne ramène qu'un article.

**Résultat attendu** : le bloc à 1 article se trouve **sous** les blocs bien
fournis. Actus du jour, Bonnes Nouvelles et La Grille gardent leur position
habituelle — ils ne sont **jamais** poussés en queue (ils ne portent pas de
score, donc ils tiennent leur place).

### Scénario 4 — Compte personnalisé
**Parcours** :
1. Réordonner sa Tournée à la main via « Composer ma Tournée », puis recharger.

**Résultat attendu** : l'ordre manuel départage les blocs de **score égal** ; un
bloc manuellement remonté mais nettement moins fourni peut descendre (risque
tranché par le PO). Rien ne bouge dans la journée en cours après le premier
chargement.

### Scénario 5 — Réseau coupé / blocs vides
**Parcours** :
1. Passer en mode avion puis ouvrir la Tournée, puis revenir en ligne.

**Résultat attendu** : aucun crash, aucune page vide anormale. Sans article
scoré, aucun tri n'est appliqué (ordre par défaut). Au retour du réseau, tri
normal au chargement suivant.

### Scénario 6 — Bascule de journée
**Parcours** :
1. Laisser l'app ouverte à cheval sur 07h30 Paris (ou décaler l'horloge), puis
   recharger la Tournée.

**Résultat attendu** : l'ordre de la veille est **jeté**, pas rejoué ; un ordre
frais est calculé à la complétion du fan-out (donc à nouveau une seule
réorganisation, en fin de chargement).

## Critères d'acceptation

- [ ] Aucun bloc ne saute pendant le fan-out (une seule réorganisation, à la complétion)
- [ ] L'ordre est stable toute la journée, identique à la ré-ouverture, dès la 1ʳᵉ frame
- [ ] Un bloc à 1 article n'est plus au-dessus du pli quand des blocs denses existent
- [ ] Actus / Bonnes Nouvelles / La Grille gardent leur position (jamais poussés en queue)
- [ ] Le quota de 3 sections « Choisie pour vous » sous le cap 13 reste honoré après tri
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus

## Zones de risque

- **Cap 13** : un bloc dégradé peut désormais tomber **hors** du cap et
  disparaître de la page. C'est voulu — mais vérifier que le quota suggestions
  survit au tri.
- **Frontière 07h30 Paris** (scénario 6) : la clé `tournee_score_order_v1` porte
  le jour dans sa valeur ; une entrée d'hier doit être ignorée, pas appliquée.
- **Comptes personnalisés** : un bloc glissé en tête peut descendre **le
  lendemain**. Jamais dans la même session.
- **Kill-switch** `kTourneeScoreSortEnabled` (`tournee_order_prefs_provider.dart`) :
  à `false`, retour exact au comportement d'avant (dépriorisation binaire
  riches/maigres). C'est le rollback si l'ordre observé déplaît.

## Dépendances

- Aucun endpoint nouveau : le tri consomme `recommendation_reason.score_total`,
  déjà servi par `GET /api/feed`.
- **Aucune migration Alembic** (mobile-only).
- Nouvelle clé `SharedPreferences` : `tournee_score_order_v1`, valeur
  `{"day": "<dayKey>", "keys": [...]}` — clé unique day-stampée, auto-invalidante.
- Event analytics `article_impression` : la propriété `block_score` passe de
  `null` à une valeur réelle.

## Notes pour l'agent QA

- Viewport 390×844, sémantique activée au boot (skill `facteur-qa-web`).
- Le gel de l'ordre se produit **après** la dernière tâche du fan-out : laisser
  la page se poser complètement avant d'asserter l'ordre final.
- Le comportement dépend des scores réels renvoyés par le backend. Sur un compte
  sans favori bien fourni, il peut n'y avoir aucun changement visible — ce n'est
  pas un échec, c'est le cas « rien à trier ».
