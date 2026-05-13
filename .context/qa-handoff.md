# QA Handoff — Couverture médiatique sous le titre du reader

## Feature développée

Section "Couverture médiatique" repositionnée sous le titre dans les deux modes de reader (in-app + scroll-to-site), avec titre raffiné au DS, badge "Couvert par X médias" en état ouvert, et suppression complète de l'ancienne UX footer (boutons "Voir perspectives" / "Retour à l'article", sticky header, méthode de check).

## PR associée

À créer via `/go` (base `main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Reader article (mode in-app, htmlContent Flutter) | `/article/:id` | Modifié |
| Reader article (mode scroll-to-site, WebView sous-jacente) | `/article/:id` | Modifié |

## Scénarios de test

### Scénario 1 : Reader in-app, article avec perspectives
**Parcours** :
1. Ouvrir un article avec `htmlContent` non vide et perspectives disponibles
2. Observer la section "Couverture médiatique" sous le titre (repliée par défaut)
3. Tap sur le header de la section pour l'ouvrir
4. Tap à nouveau pour la refermer

**Résultat attendu** :
- Section encadrée par 2 dividers, entre titre et description
- Titre "Couverture médiatique" rendu en `labelLarge` + `textSecondary` (subtil)
- En état ouvert : badge pill "Couvert par N médias" avec fond `primary.withValues(alpha: 0.1)`, texte `labelMedium` couleur `primary`, juste sous le header et avant la bias bar
- Animation smooth, scroll-into-view à l'ouverture

### Scénario 2 : Reader in-app, article sans perspectives
**Parcours** : Ouvrir un article sans comparaisons (perspectives vides ou null)

**Résultat attendu** : Titre → description directement, aucun divider, aucune section visible

### Scénario 3 : Reader scroll-to-site, article avec perspectives
**Parcours** :
1. Ouvrir un article qualifiant pour le mode scroll-to-site
2. Vérifier structure : header (thumbnail/tags/titre/temps de lecture) → divider → section perspectives → divider → corps article
3. Scroll jusqu'au bas du corps article

**Résultat attendu** :
- Section perspectives apparaît entre header et corps, même rendu que le mode in-app (titre + badge en état ouvert)
- WebView s'active au même seuil de scroll qu'avant (corps article scrollé), pas plus tôt
- Pas de duplication du titre, pas de chevauchement avec le chrome de l'app

### Scénario 4 : Reader scroll-to-site, article sans perspectives
**Parcours** : Ouvrir un article scroll-to-site sans perspectives

**Résultat attendu** : Header → corps directement, comportement WebView inchangé

### Scénario 5 : Footer
**Parcours** : Sur n'importe quel article

**Résultat attendu** : Plus aucun bouton "Voir perspectives" (œil) ni "Retour à l'article" (newspaper + arrowUp) dans le footer. Seuls restent : CTA "Lire sur…", Sauvegarder, Recommander.

### Scénario 6 : Bouton flottant "Lancer l'analyse Facteur" (in-app uniquement)
**Parcours** :
1. Ouvrir un article in-app avec perspectives
2. Ouvrir la section
3. Vérifier que le bouton flottant apparaît
4. Refermer la section

**Résultat attendu** : Bouton visible uniquement quand la section est ouverte ET analysis state == idle ET perspectives non vides. Disparaît à la fermeture.

### Scénario 7 : Dark mode
**Parcours** : Activer le mode sombre, parcourir les scénarios 1–4

**Résultat attendu** : Badge, dividers et couleurs DS suivent le thème.

## Critères d'acceptation

- [ ] Section "Couverture médiatique" sous le titre, avant la description/corps, dans les deux modes de reader
- [ ] Section encadrée par 2 dividers, masquée si aucune perspective
- [ ] Titre de section au DS (`labelLarge` / `textSecondary`)
- [ ] Badge "Couvert par X médias" visible uniquement en état ouvert
- [ ] Suppression totale des boutons footer perspectives
- [ ] Mode scroll-to-site : WebView s'active au même seuil que sur main
- [ ] `flutter analyze` sans warning ni erreur sur les fichiers modifiés
- [ ] Pas de nouveau test en échec (regressions)

## Zones de risque

1. **`_articleKey` et `_computeScrollOffsets`** (mode scroll-to-site) : la clé reste sur le wrapper du corps article uniquement. Un mauvais positionnement déclencherait la WebView trop tôt ou trop tard.
2. **Backgrounds opaques** : chaque enfant top-level (header, dividers, perspectives, article) a `color: colors.backgroundPrimary` pour masquer la WebView. Un oubli laisserait la WebView transparaître.
3. **Prédicat du bouton flottant `Lancer l'analyse`** — désormais piloté par `_perspectivesExpanded` au lieu de `_atPerspectivesSection` (scroll-driven). Devrait apparaître dès l'ouverture de la section.

## Dépendances

- `GET /api/perspectives/:contentId` — backend de comparaisons (inchangé)
- Aucun changement API ; uniquement UI mobile.
