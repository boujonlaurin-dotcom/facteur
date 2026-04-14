# QA Handoff — Brise-glace themes-first (PR 3/3)

> Rempli par l'agent dev. Input pour /validate-feature.

## Feature developpee

Transformation de l'empty state de `AddSourceScreen` en brise-glace "themes-first" : l'utilisateur voit ses themes suivis, des exemples cliquables, et des pepites communautaires compactes avant toute saisie.

## PR associee

A creer apres validation.

## Ecrans impactes

| Ecran | Route | Modifie / Nouveau |
|-------|-------|-------------------|
| AddSourceScreen | /settings/sources/add | Modifie (empty state) |
| ThemeSourcesScreen | /settings/sources/theme/:slug | Nouveau |

## Scenarios de test

### Scenario 6 : Empty state themes-first
**Parcours** :
1. Aller sur Settings > Sources > Ajouter une source
2. Observer l'empty state sans taper de texte
**Resultat attendu** : L'ecran affiche dans l'ordre :
- Champ de recherche + bouton "Rechercher"
- Section "Essaie :" avec 4 chips cliquables (Lenny's newsletter, r/france, @fireship, Stratechery)
- Section "Explorer par theme" avec chips horizontaux des themes suivis
- Section "Pepites de la communaute" avec strip horizontale compacte
- Carte AtlasFlux en bas

### Scenario 7 : Drill-down theme -> sources
**Parcours** :
1. Sur AddSourceScreen, taper sur un chip theme (ex: "Tech")
2. Observer l'ecran ThemeSourcesScreen
**Resultat attendu** :
- Navigation vers un nouvel ecran avec Hero animation du chip
- Titre = nom du theme
- 3 sections affichees : "Sources curees", "Candidates", "Decouvertes par la communaute"
- Chaque section avec compteur et sources listees
- Bouton "+" pour ajouter, checkmark si deja suivi

### Scenario 8 : Fallback themes vides
**Parcours** :
1. Se connecter avec un user sans themes suivis
2. Aller sur AddSourceScreen
**Resultat attendu** : La section "Explorer par theme" affiche 3 themes par defaut : Tech, Actu FR, Produit

### Scenario 9 : Exemple cliquable
**Parcours** :
1. Sur AddSourceScreen, taper sur le chip "Lenny's newsletter"
**Resultat attendu** :
- Le champ de recherche se remplit avec "Lenny's newsletter"
- La recherche se lance automatiquement
- Un evenement analytics `add_source_example_tap` est envoye

### Scenario 11 : Ajout depuis pepite
**Parcours** :
1. Sur AddSourceScreen, taper sur une pepite dans le carrousel horizontal
**Resultat attendu** :
- Le modal de detail source s'ouvre
- Bouton "Ajouter" disponible
- Un evenement analytics `add_source_gem_tap` est envoye

## Criteres d'acceptation

- [ ] AC 6 : Empty state themes-first visible avec chips themes suivis
- [ ] AC 7 : Drill-down theme -> sources groupees (Curees/Candidates/Communaute)
- [ ] AC 8 : Pepites communautaires compactees en strip horizontale
- [ ] AC 9 : Exemples cliquables pre-remplissent le champ et lancent la recherche
- [ ] Fallback themes par defaut si user sans themes
- [ ] Hero animation chip -> titre ecran
- [ ] Events analytics : add_source_theme_tap, add_source_example_tap, add_source_gem_tap

## Zones de risque

- Hero animation entre ActionChip et AppBar title : peut ne pas animer si le Material wrapping est incorrect
- Les endpoints backend (GET /sources/themes-followed, GET /sources/by-theme/{slug}) doivent etre deployes sur staging
- Le fallback themes par defaut utilise des slugs codes en dur (tech, actu-fr, produit) qui doivent exister en base

## Dependances

- `GET /api/sources/themes-followed` — retourne les themes suivis par le user
- `GET /api/sources/by-theme/{slug}` — retourne les sources groupees par theme
- `GET /api/sources/trending` — endpoint existant pour les pepites communautaires
