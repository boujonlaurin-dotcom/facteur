# QA Handoff — « Notif du jour » (bandeau agrégateur quotidien)
# QA Handoff — Header/Footer flottants « liquid glass » (reader)

## Feature développée
Le header et le footer de l'écran de lecture (`ContentDetailScreen`) deviennent des surfaces « liquid glass » (`GlassPill` : blur conditionnel + fond translucide + hairline + ombre douce), pattern extrait de `MainBottomNav`. Le header est un cadre haut collé aux bords (haut/gauche/droite, sous la status bar) dont seuls les coins bas sont arrondis (rayon 20 px) ; le footer est un pill flottant détaché des bords dont seuls les coins hauts sont arrondis. La barre de progression de lecture vit désormais *dans* le pill du header (clipée par ses coins arrondis). Le fond du header couvre toute la zone status bar (plus de scrim) et garde les icônes système lisibles.

## PR associée
À créer (branche `boujonlaurin-dotcom/floating-webview-header-footer`, base `main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Écran de lecture (reader in-app, scroll-to-site, WebView, vidéo/audio) | `/content/:id` (ContentDetailScreen) | Modifié |

## Scénarios de test

### Scénario 1 : Reader in-app — pills flottants (happy path)
**Parcours** :
1. Ouvrir un article avec contenu in-app depuis le feed
2. Observer le header en haut et le footer en bas
3. Scroller dans l'article
**Résultat attendu** : header et footer sont des pills à coins arrondis 20 px, détachés des bords (12 px de marge horizontale) ; le contenu de l'article transparaît derrière (fond translucide ; sur le build web le fond est quasi-opaque, sans blur — attendu). Le texte de l'article passe *derrière* les pills en scrollant.

### Scénario 2 : Footer auto-hide
**Parcours** :
1. Dans le reader in-app, scroller vers le bas
2. Puis scroller vers le haut
3. Atteindre la fin de l'article
**Résultat attendu** : le footer glisse entièrement hors écran au scroll bas (ombre incluse : aucun liseré résiduel en bas), réapparaît au scroll haut, et devient permanent en fin d'article avec le CTA orange.

### Scénario 3 : Barre de progression dans le pill
**Parcours** :
1. Ouvrir un article in-app, scroller au-delà de 5 %
2. Observer le bord bas du pill header
**Résultat attendu** : la barre de progression s'affiche collée au bord bas *intérieur* du pill header, clipée par les coins arrondis (elle ne déborde jamais du pill).

### Scénario 4 : Status bar lisible
**Parcours** :
1. Ouvrir un article, scroller pour amener du texte sous la status bar
**Résultat attendu** : le fond du header couvre toute la zone de la status bar (il s'étend sous elle) ; l'heure et les icônes système restent lisibles quel que soit le contenu qui scrolle derrière ; le bouton back du header reste cliquable.

### Scénario 5 : Light / dark mode
**Parcours** :
1. Répéter le scénario 1 en thème clair puis sombre
**Résultat attendu** : light = fond crème translucide, bordure noire 8 % ; dark = fond backgroundPrimary translucide, bordure blanche 12 %, ombre plus marquée. Pas de pill illisible ni de contraste cassé.

### Scénario 6 (device) : WebView / fallback sans blur
**Parcours** :
1. Ouvrir un article scroll-to-site, taper le CTA pour révéler le site (WebView)
2. Ouvrir un article d'une source premium connectée
**Résultat attendu** : sur Android en mode WebView, les pills passent en fond quasi-opaque (pas de blur — un BackdropFilter ne peut pas échantillonner une platform view) ; dégradation quasi invisible, aucun artefact graphique. Sur iOS vérifier que le blur au-dessus de WKWebView fonctionne, sinon signaler (extension du fallback à prévoir).

## Critères d'acceptation
- [ ] Header = cadre haut collé aux bords, coins bas arrondis (radius 20), s'étend sous la status bar
- [ ] Footer = pill flottant détaché des bords, coins hauts arrondis (radius 20), bottom = safe area + 8
- [ ] Contenu visible derrière les surfaces (translucide / blur natif)
- [ ] Barre de progression clipée dans le pill header
- [ ] Footer auto-hide sort entièrement de l'écran (ombre comprise)
- [ ] Fond du header couvre la status bar (plus de scrim) ; icônes système lisibles
- [ ] Aucune régression : back, chip source, partage, sauvegarde, tournesol, CTA « Lire sur… »
- [ ] Console web sans erreurs, réseau sans 4xx/5xx inattendus

## Zones de risque
- Clearances de contenu : tous les modes (scroll-to-site, in-app, vidéo, audio, WebView fallback) réservent la même hauteur `topInset + _kHeaderContentHeight (59) + _kHeaderContentGap (15)` sous le header, via le getter unique `_headerHeight` — vérifier qu'aucun titre n'est masqué à l'ouverture et, en WebView, que le bandeau du média n'est jamais tronqué par le header.
- Distance d'auto-hide du footer (`+ marge basse + _kFooterShadowClearance (24)`) — vérifier l'absence de « pill fantôme » en bas.
- Flutter web = canvas : activer la sémantique au boot avant tout `snapshot` (cf. skill `facteur-qa-web`), viewport 390x844.

## Dépendances
Aucune (changement front-only, zéro backend / migration).
# QA Handoff — Paywalls Premium « Fact·eur·isse » (PR 2 mobile)

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
