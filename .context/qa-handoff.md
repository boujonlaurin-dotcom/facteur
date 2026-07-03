# QA Handoff — « Notif du jour » (bandeau agrégateur quotidien)

## Feature développée
Ligne de notification unique en tête du feed Essentiel : file de messages (profil + nudges absorbés), un seul visible à la fois, max 3/jour (le suivant après tap CTA ou dismiss croix), rotation quotidienne. Remplace les bandeaux renudge / well-informed / géoloc.

## PR associée
Branche `boujonlaurin-dotcom/notif-du-jour-composant` → PR vers `main` (voir `gh pr view`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Essentiel (feed) | `/feed` | Modifié (carte Notif du jour en tête, sous bandeau Lettres) |
| Mes abonnements | `/settings/subscriptions?add=1` | Modifié (auto-ouverture feuille d'ajout) |
| Profil | `/settings/profile` | Modifié (tuile « Ma configuration » + barre de progression) |

## Scénarios de test

### Scénario 1 : affichage un-à-la-fois (happy path)
**Parcours** :
1. Ouvrir le feed Essentiel (compte connecté, onboarding fait).
2. Observer la zone sous le bandeau Lettres.
**Résultat attendu** : au plus **une** carte Notif du jour (icône teintée 34px, titre 1 ligne, CTA-lien avec flèche, croix à droite). Jamais deux messages empilés. Pas de flash au chargement.

### Scénario 2 : dismiss → message suivant
**Parcours** :
1. Taper la croix de la carte.
**Résultat attendu** : repli fluide (~300ms, hauteur + fondu), puis le **message suivant** de la file apparaît. Après 3 consommations dans la journée, plus rien ne s'affiche (recharger : toujours rien — persisté).

### Scénario 3 : CTA Serein in-place
**Parcours** (visible seulement si mode Serein OFF) :
1. Taper la carte « Pas dans le mood pour l'actu chaude ? ».
**Résultat attendu** : aucune navigation ; le mode Serein s'active, la carte se replie et le message suivant apparaît.

### Scénario 4 : CTA navigation directe
**Parcours** :
1. Taper « Tes médias préférés manquent à l'appel ? » (si < 3 sources suivies) → panneau d'ajout de média **direct** (pas la liste).
2. Taper « Abonné à un média ? Ajoute-le ici » (si sources payantes suivies non liées) → Mes abonnements s'ouvre **avec la feuille d'ajout déjà ouverte**.
**Résultat attendu** : zéro tap intermédiaire.

### Scénario 5 : NPS well-informed inline
**Parcours** (si le message est dû) :
1. Carte « Te sens-tu bien informé·e en ce moment ? » : boutons 1..10 à la place du CTA.
2. Taper un score.
**Résultat attendu** : soumission (POST well-informed), repli, message suivant. La croix = skip.

### Scénario 6 : profil — Ma configuration
**Parcours** :
1. Aller sur `/settings/profile`.
**Résultat attendu** : tuile « Ma configuration » avec barre de progression, tap → relance le parcours d'onboarding.

## Vérifications transverses
- Console sans erreurs ; réseau sans 4xx/5xx inattendus.
- Fidélité hifi : fond crème surface, radius 14, ombre douce, pas de bordure ; tints ocre/vert/steel.
- Les anciens gros bandeaux renudge/géoloc/well-informed n'apparaissent **plus**.
- ⚠️ Web : les demandes OS (renudge push, géoloc device) ne se testent pas — on-device Android requis (hors QA web).
