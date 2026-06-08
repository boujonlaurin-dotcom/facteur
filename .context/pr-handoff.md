# Tournée — clarifier les limites + affordance du bouton de passage + auto-scroll

## Résumé

Refonte de la modal « Mes favoris » (`manage_favorites_sheet.dart`, ouverte depuis
L'Essentiel et les onglets Flâner) pour lever la confusion entre les trois
mécanismes de limite, et élargissement du cap Tournée **5 → 7**.

## Changements

### 1. Cap Tournée 5 → 7 (mirrors synchronisés, aucune migration)
- `tournee_order_prefs_provider.dart` : `kTourneeVisibleCap` 5 → 7.
- `flux_continu_provider.dart` : `_kMaxFavoriteSections` & `_kMaxFavoriteSourceSections`
  5 → 7 (sous-caps par catégorie, avant le `take(kTourneeVisibleCap)`).
- `config/constants.dart` : `InterestConstants.favoriteCap` 5 → 7 (mirror).
- `packages/api/app/constants.py` : `FAVORITE_CAP` 5 → 7 (mirror, constante produit —
  pas de DDL/Alembic). `get_top_themes` borne juste un peu plus large la perso éditoriale.
- Cap Flâner `kMaxFavoriteTabs = 10` : **inchangé**.

### 2. Suppression des blocages « max » par type
Le backend n'impose aucun cap dur (`FavoriteCapReached` = code mort). Retiré côté
modal : `interestsAtCap`/`sourcesAtCap`, le paramètre `atCap` des add-lists, les
`_CapHint(« Maximum … atteint »)`, la classe `_CapHint`, les `catch
(FavoriteCapReachedException)` et l'import devenu inutile. L'ajout n'est plus jamais
bloqué ; le surplus reste grisé sous le trait `_CapDivider` existant.

### 3. Compteurs dans les en-têtes
`_SectionLabel` accepte un `counter` optionnel rendu en pill discret (`· X/7`,
`· X/10`). Essentiel = `clamp(0, 7)/7`, Flâner = `clamp(0, 10)/10`.

### 4. Affordance du bouton de passage
Nouvelle puce `_MoveChip` (icône directionnelle + libellé de destination
« Flâner » / « Essentiel », bord/fond accentués via `item.accent`, cible ≥ 44px,
haptique conservée) en remplacement de la flèche seule, pour sources et thèmes.

### 5. Bonus — auto-scroll vers Flâner
`ScrollController` + `GlobalKey` sur l'en-tête Flâner ; en `initState`, si
`entry == ManageFavoritesEntry.flaner`, `Scrollable.ensureVisible` (300 ms, easeOut).
Entrée Essentiel → pas de scroll (déjà en tête).

## Fichiers modifiés
- `apps/mobile/lib/features/flux_continu/providers/tournee_order_prefs_provider.dart`
- `apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart`
- `apps/mobile/lib/features/flux_continu/widgets/manage_favorites_sheet.dart`
- `apps/mobile/lib/config/constants.dart`
- `packages/api/app/constants.py`
- Tests : `manage_favorites_sheet_test.dart`, `flux_continu_tournee_order_test.dart`,
  `flux_continu_sources_test.dart`, `flux_continu_provider_test.dart`,
  `tournee_composer_sheet_test.dart` (caps 5 → 7, scénarios de coupe ré-équilibrés).

## Vérification
- Backend : `pytest` complet → **1525 passed, 1 skipped, 2 xfailed** (DB test 54322).
- Mobile : `flutter analyze` (aucune issue sur les fichiers touchés) + tests
  flux_continu touchés → **tous verts**.
