# QA Handoff — Lettre du jour : timeline overlay + ajustements PO

> Input pour `/validate-feature` (Playwright Agent CLI, skill `facteur-qa-web`, viewport 390×844,
> sémantique activée au boot — build web Flutter = canvas).

## Feature développée
Finalisation de l'EPIC « Lettre du jour » : (1) le strip de pills au-dessus de l'Essentiel devient un
**bouton « rewind »** dans l'en-tête de la carte, ouvrant une **timeline en feuille du bas** ; (2) 4
ajustements PO — **rewind réduit à 3 options**, **retrait du bouton « personnaliser »** de la carte
Essentiel + **« GÉRER » plus grand**, **rewind par swipe horizontal + CTA « mode serein »** ajoutés à
la page **Lettre du jour** (le rituel matinal).

## PR associée
<!-- à compléter après /go -->

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Essentiel (Flux Continu) | `/flux-continu` (onglet Essentiel) | Modifié (strip retiré, rewind ajouté, bouton perso retiré) |
| Feuille timeline | overlay (showModalBottomSheet) | Modifié (3 lignes : Aujourd'hui, Hier, Cette semaine) |
| Lettre du jour (rituel matinal) | `/edition` | Modifié (swipe rewind « Hier », trigger « Remonter le temps », CTA serein) |
| Inline « GÉRER » (MyInterestsIntro) | `/flux-continu` (mode personnalisé) | Modifié (plus visible) |

## Scénarios de test

### Scénario 1 : Timeline réduite à 3 options
**Parcours** : Essentiel → taper le déclencheur ⏪ « Aujourd'hui ».
**Résultat attendu** : feuille du bas avec titre « Remonter le temps » et **exactement 3 lignes** :
« Aujourd'hui » (cerclée, sélection courante), « Hier », « Cette semaine ». **Plus de J-2…J-7.** Statut
lu/non-lu présent si streaks dispo.

### Scénario 2 : Carte Ton Essentiel sans bouton « personnaliser »
**Parcours** : Essentiel → observer l'en-tête de la carte « Ton Essentiel ».
**Résultat attendu** : titre non tronqué ; déclencheur ⏪ présent à droite ; **aucun bouton/engrenage
« personnaliser »** (ni en today, ni sur une lettre passée). La carte s'affiche en entier.

### Scénario 3 : Inline « GÉRER » plus visible
**Parcours** : être en mode personnalisé (au moins 1 favori de Tournée) → repérer la ligne
« TES N FAVORIS DE TOURNÉE … GÉRER ».
**Résultat attendu** : le bouton « GÉRER » ressort (libellé plus grand, fond accent doux ocre + contour),
clairement le point d'entrée des préférences ; tap → sheet « Composer ma Tournée ».

### Scénario 4 : Page Lettre du jour — rewind par swipe horizontal
**Parcours** : ouvrir la page Lettre du jour (`/edition`, rituel matinal) → observer le bord gauche →
glisser la lettre **vers la droite**.
**Résultat attendu** : une carte « Hier » crème dépasse du **bord gauche** au repos (liseré ~24 px) ;
en glissant vers la droite, la lettre suit le doigt et la carte « Hier » se tire en parallax ; au-delà du
seuil (ou fling), navigation vers le feed en **édition « Hier »** (lecture seule, footer « Revenir à
aujourd'hui »). Sous le seuil → snap-back élastique. Repli accessible : un lien **« Remonter le temps »**
ouvre la timeline complète.

### Scénario 5 : Page Lettre du jour — CTA « mode serein »
**Parcours** : sur la page Lettre du jour, repérer « Pas d'humeur pour les news difficiles ? » → taper
« Active ton mode serein ».
**Résultat attendu** : snackbar « Mode serein activé » ; la préférence est persistée (toggle partagé avec
le feed). Bouton désactivé tant que la préférence charge.

### Scénario 6 : Coexistence des gestes + dégradation gracieuse
**Parcours** : sur la Lettre du jour, glisser **vers le haut** (doit ouvrir l'édition, inchangé) puis,
en repartant, glisser **vers la droite** (rewind). Vérifier qu'un seul geste se déclenche à la fois.
Streaks off → ouvrir la timeline.
**Résultat attendu** : swipe-up = ouverture, swipe-droite = rewind, jamais les deux ensemble. Timeline
sans pastille lu/non-lu quand streaks indisponible ; navigation OK quand même.

## Critères d'acceptation
- [ ] Timeline = **3 lignes** (Aujourd'hui, Hier, Cette semaine), ligne active cerclée.
- [ ] Carte Ton Essentiel : **aucun** bouton « personnaliser » (today ET passé) ; déclencheur ⏪ présent.
- [ ] « GÉRER » nettement plus visible (libellé 13 px, fond accent).
- [ ] Page Lettre du jour : carte « Hier » qui dépasse à gauche ; swipe droite → édition « Hier ».
- [ ] Swipe-up (ouverture) toujours fonctionnel et exclusif du swipe horizontal.
- [ ] CTA serein : toggle persistant + snackbar « Mode serein activé ».
- [ ] Lien « Remonter le temps » (repli a11y) ouvre la timeline.
- [ ] Dark mode : couleurs lisibles (tokens thème). Console sans erreurs ; réseau sans 4xx/5xx inattendus.

## Zones de risque
- Hauteur de la page Lettre du jour sur petits écrans (rewind trigger + CTA serein ajoutés sous le
  sommaire) → vérifier l'absence d'overflow visible sur 390×844.
- Arène de gestes H vs V sur la Lettre du jour (le swipe-up ne doit pas être volé par le swipe horizontal
  et inversement).
- `reduceMotion` : la carte « Hier » reste statique (pas de parallax) mais le commit au fling reste possible.

## Dépendances
- **Aucun** changement back-end (pas d'Alembic/migration).
- Statut lu/non-lu : `GET /api/streaks/activity` (existant). Mode serein : `sereinToggleProvider`
  (préférence existante `serein_enabled`).
