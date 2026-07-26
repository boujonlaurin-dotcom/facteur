# QA Handoff — Objectif quotidien réglable + footer validé vert (story 30.2)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/30.2.objectif-quotidien-reglable.md`.

## Feature développée
L'objectif quotidien de lectures abouties devient réglable (1 → 7, défaut 2) via
un curseur dans l'écran « Progression », persisté serveur (`daily_goal`). Le toast
« objectif atteint » propose un CTA pour l'ajuster, et le footer d'un article
terminé passe tout au vert `success`.

## PR associée
À créer (`/go`) vers `main`.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Progression | `/lettres` | Modifié — nouvelle carte « Objectif quotidien » sous l'en-tête |
| Lecteur d'article (détail) | `/flaner/content/:id` | Modifié — CTA toast + couleur footer |

## Scénarios de test

### Scénario 1 : Régler l'objectif (happy path)
1. Ouvrir « Progression » (`/lettres`).
2. Repérer la carte « Objectif quotidien » (sous l'en-tête).
3. Glisser le curseur de 2 à 5.
**Attendu** : la valeur affichée passe à « 5 articles » ; après un reload de
l'écran, la valeur reste 5 (persistée serveur).

### Scénario 2 : CTA du toast à l'objectif atteint
1. Régler l'objectif à 1 (pour atteindre l'objectif en une lecture).
2. Ouvrir un article et le lire jusqu'au bout.
**Attendu** : le toast `micro` « lu jusqu'au bout » affiche la ligne tappable
« Quel objectif on se donne ? » ; un tap ouvre l'écran Progression et ferme le
toast.

### Scénario 3 : Pas de CTA sous l'objectif
1. Régler l'objectif à 3.
2. Lire un seul article jusqu'au bout (1/3).
**Attendu** : le toast affiche « 1/3 » sans CTA.

### Scénario 4 : Footer validé vert
1. Lire un article jusqu'au bout.
**Attendu** : le pied de page passe en état validé — le bouton « Lire sur … »
est vert `success` (plus de gris), cohérent avec la teinte du pill et le toast.

### Scénario 5 : Gate gamification
1. Désactiver la gamification (réglages).
2. Ouvrir « Progression ».
**Attendu** : la carte « Objectif quotidien » est masquée.

## Critères d'acceptation
- [ ] Curseur 1 → 7, défaut 2, valeur persistée après reload.
- [ ] CTA présent uniquement à `current >= total`.
- [ ] Footer article terminé entièrement vert `success`.
- [ ] Carte masquée si gamification désactivée.
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## Zones de risque
- Optimistic UI du curseur : rollback + SnackBar si le PUT échoue.
- Le CTA du toast n'est tappable que sur sa propre ligne (niveau `micro` non
  tappable globalement).

## Dépendances
- `PUT /api/users/profile` avec `{"daily_goal": <1..7>}` (422 hors bornes).
- `GET /api/streaks` (ou route streak) renvoie `daily_goal`.
- Migration `dg01_daily_goal_user_profiles` appliquée (colonne `user_profiles.daily_goal`).
