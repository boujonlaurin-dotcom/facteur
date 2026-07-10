# Bug — Confusion du workflow d'ajout de sources premium

> Type : **Bug** (UX + copy trompeuse). Scope : un seul widget Flutter + son test,
> plus un commentaire TODO traçable côté backend. **Aucun changement DB/Alembic.**

## Symptômes signalés

Le flow « connecter un abonnement premium » (`PremiumSourceConnection` :
écran intro → WebView de login → WebView de test → succès) présente trois
problèmes UX, plus une demande bonus.

1. **CTA prématuré (Issue 1).** Le bouton `'Continuer vers l'article test'`
   (step 1, login) est visible et actif dès l'ouverture de la WebView de login,
   avant même que l'utilisateur ait tapé ses identifiants. Ça laisse croire
   qu'il faut cliquer tout de suite.
2. **Header confus + trop de place (Issue 2).** Le `Row` du header de
   `_WebViewStep` mélange un titre (« Connexion » / « Article test ») et un
   `TextButton.icon` « Navigateur » (ouvre l'URL dans le navigateur externe).
   Le libellé « Navigateur » est incompréhensible dans ce contexte et le bloc
   prend de la hauteur.
3. **« Continuer vers l'article test » ne fonctionne pas (Issue 3).** Root cause
   confirmée en code : `PremiumConnection.testUrl` pointe vers la **home du
   média** pour les 13 sources curées (`PREMIUM_CURATED_MAP`,
   `packages/api/app/services/premium_curated_sources.py`) **et** pour tout
   fallback générique (`_genericConnectionFor`, `source_model.dart`). Il n'existe
   **aucun** vrai article test abonné dans le système aujourd'hui — le
   commentaire du code l'admet déjà (« idéalement un article abonné evergreen, à
   défaut la home du média »). Donc le bouton « fonctionne » techniquement mais
   ne montre jamais l'article promis → perception de bug.
4. **Bonus.** Ajouter un système de steps (pills de progression) pour rendre la
   procédure plus lisible/navigable.

## Décisions

- **Issue 3 — pas de deviner d'URLs d'articles abonnés dans cette PR.** Trouver
  un article abonné « evergreen » réel par média est une tâche éditoriale
  séparée (hors scope). On corrige plutôt la **copy** pour ne plus promettre
  « un article test » quand ce n'est que la home. Un `TODO(product)` traçable
  est ajouté en tête de `PREMIUM_CURATED_MAP` (sans changement fonctionnel) et
  pointe vers ce doc.
- **Issue 1 — heuristique host+path pour V1.** On considère l'utilisateur comme
  « ayant navigué » dès que la WebView quitte l'URL de login initiale (host ou
  path différent, query/fragment ignorés). Pas de fallback/timer supplémentaire
  (validé par l'utilisateur). Pas de reset : le flow n'a pas de retour arrière
  vers le step 1 (l'AppBar `X` pop tout l'écran).
- **Issue 2 + Bonus — un seul header repensé.** Le titre texte + « Navigateur »
  sont remplacés par des pills de progression (3 steps : login → vérification →
  terminé) + un bouton icône seul avec tooltip « Ouvrir dans le navigateur
  externe ». L'annonce a11y du titre est préservée via `Semantics(label:)`.
- **Steps intro (0) et succès (3) : pas de pills.** Ce sont des écrans à part
  (pas de `_WebViewStep`) ; l'AppBar donne déjà le contexte. Ajouter les pills
  là demanderait de dupliquer un header inexistant → scope minimal.

## Fichiers concernés

- `apps/mobile/lib/features/sources/widgets/premium_source_connection.dart` —
  fichier principal, tous les changements de code.
- `apps/mobile/lib/features/sources/widgets/premium_web_view.dart` — **aucun
  changement** : `onLoadStart`/`onLoadStop` existent déjà et sont câblés, ils
  n'étaient simplement jamais passés par l'appelant.
- `apps/mobile/test/features/sources/widgets/premium_source_connection_test.dart`
  — MAJ copy + nouveau seam de test pour simuler la navigation.
- `packages/api/app/services/premium_curated_sources.py` — commentaire TODO
  traçable (pas de changement fonctionnel).

## Plan technique

### 1. Gating du CTA step 1 (Issue 1)

Nouveau state `bool _loginNavigated = false` + handler `_handleLoginNavigation`
comparant host+path de l'URL courante à l'URL de login initiale. `_WebViewStep`
(step 1) reçoit `onLoadStop: _handleLoginNavigation` et `showAction:
_loginNavigated`. Le step 2 garde `showAction: true`.

### 2. Header : pills + bouton icône (Issue 2 + Bonus)

Nouveau widget privé `_PremiumStepPills` (inline, calqué sur `_StepPills` de
`veille_widgets.dart`), tokens `colors.primary` (actif) / `colors.border`
(inactif). Header `_WebViewStep` : pills (dans `Semantics(label: title)`) +
`IconButton` seul (tooltip « Ouvrir dans le navigateur externe »).
`_WebViewStep` gagne `stepIndex` (1-based) et `totalSteps` (=3).

### 3. Bouton « en absence » (step 1 avant navigation)

`if (showAction) FacteurButton(...) else SizedBox(height: space4)` pour éviter un
saut de layout brutal de la WebView quand le bouton apparaît.

### 4. Copy honnête (Issue 3)

| Emplacement | Avant | Après |
|---|---|---|
| Titre step 1 | `Connexion` | inchangé |
| CTA step 1 | `Continuer vers l'article test` | `Continuer` |
| Titre step 2 | `Article test` | `Vérification` |
| CTA step 2 | `L'article s'affiche correctement` | `Je suis connecté(e)` |
| Tooltip nouveau | — | `Ouvrir dans le navigateur externe` |
| Hint défaut step 0 | `...confirmez qu'un article abonné s'affiche correctement.` | `...confirmez que votre session est bien active.` |

Les `display_hint` déjà présents dans `PREMIUM_CURATED_MAP` et
`_genericConnectionFor` ne sur-promettent pas et restent inchangés.

### 5. Test

- Étendre le typedef `PremiumWebViewBuilder` pour transmettre `onLoadStop`
  (seul seam propre — pas de back-door `@visibleForTesting`).
- Assertions : bouton `Continuer` caché avant navigation, visible après une
  navigation simulée ; titres/CTA mis à jour ; reste du flow inchangé.

## Vérification

- `flutter analyze` (zéro warning suite au changement de signature du typedef).
- `flutter test test/features/sources/widgets/premium_source_connection_test.dart`.
- `flutter test` (suite complète, cf. hook `stop-verify-tests.sh`).
