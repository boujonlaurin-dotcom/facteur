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

## Contexte

Implémentation de la maquette « Paywalls Premium » : écran **Soutien** (porte 1, lettre des fondateurs), **murs de feature** (porte 2 : veille plein écran + sheets sources/analyses/serein), gating client-side (cap 30 sources, veille premium, quota 1 analyse/jour, personnalisation serein), confirmation « lien envoyé ». Le CTA n'ouvre jamais un paiement : il déclenche `POST /api/checkout/send-link` (magic link Supabase par email, PR backend #954).

⚠️ **Web = état free uniquement** : RevenueCat est null sur web (`customerInfoProvider` → null → non-premium). Ne pas tester les états premium en web.

⚠️ Les photos fondateurs sont des **placeholders** (aplats de couleur) en attendant les vraies images.

## Écrans impactés

- Réglages (bottom sheet) : tuile « Nous soutenir », badge `N/30` sur Mes sources, stamp `PREMIUM` sur Ma veille/Crée ta veille, sous-row « Personnaliser mes bonnes nouvelles » (lock).
- `/soutien` : écran Soutien complet.
- `/soutien/veille-wall` : mur veille.
- `/soutien/lien-envoye` : confirmation.
- Intro veille : stamp « RÉSERVÉ AUX FACT·EUR·ISSES » + CTA verrouillé.
- Ajout de source : pill « N / 30 médias suivis ».
- Perspectives / Analyse Facteur : gate quota 1/jour (bannière quota épuisé sous le CTA en free).

## Scénarios

1. **Happy path Soutien** : Réglages → « Nous soutenir » → écran Soutien (eyebrow, headline, lettre 2 §, carte bonus avec 2 stamps BIENTÔT, 3 réassurances, prix 3 €/mois, CTA « Reçois ton lien pour nous rejoindre », disclaimer stores). Tap CTA → soit confirmation « Ton lien est en route. » (backend avec send-link), soit toast d'erreur propre, jamais de crash.
2. **Mur veille** : Réglages → « Crée ta veille » (compte free sans veille) → mur veille (3 bénéfices, MissionCard « Notre histoire → » → Soutien, prix, CTA).
3. **Intro veille gated** : deep-link `/veille/config` en free → redirection mur veille.
4. **Cap sources** : ajout de source → pill « N / 30 médias suivis » au-dessus de la recherche (absente en mode veille).
5. **Serein** : Réglages → sous-row « Personnaliser mes bonnes nouvelles » avec cadenas → tap → PaywallSheet variante serein (« Un mode serein à ton image »).
6. **Lien envoyé** : « Renvoyer le lien » 2× de suite → le second affiche « Patiente une minute avant de renvoyer. » (429) si backend actif.
7. **Console/réseau** : pas d'erreurs console inattendues, pas de 4xx/5xx hors 429 attendu.

## Critères d'acceptation

- Aucune copy avec em-dash « — ».
- Aucun crash sur images manquantes (fallback monogramme).
- Navigation retour cohérente (swipe back plein écran).
