# Handoff — Story 10.26 : Layout éditorial + widgets texte

## Contexte

Les stories 10.22 (sources deep), 10.23 (pipeline curation), 10.24 (rédaction LLM) et 10.25 (format editorial_v1 + endpoint API + modèles Dart) sont mergées/prêtes. Le backend renvoie maintenant un `DigestResponse` complet avec tous les champs éditoriaux. Les modèles Dart parsent correctement le nouveau format. **Mais l'UI mobile affiche encore le layout `topics_v1` pour les digests éditoriaux.**

**Story 10.26 = rendre le layout éditorial visible dans l'app** : header dynamique, textes d'intro/transition entre les sujets, section divider, et progression simplifiée (dots).

## Objectif

1. **Brancher le layout `editorial_v1`** dans `DigestBriefingSection` (D3)
2. **Header dynamique** : remplacer "L'Essentiel du jour" par `headerText` de l'API (D1)
3. **Progression simplifiée** : dots discrets au lieu de la barre segmentée (D6)
4. **Créer 3 nouveaux widgets** : `IntroText` (N1), `TransitionText` (N2), `SectionDivider` (N4)
5. **Créer le conteneur `EditorialSubjectBlock`** qui assemble intro + cartes + transition par sujet

## Design doc de référence

**LECTURE OBLIGATOIRE** :
- `docs/design/editorial-digest/03-frontend.md` — sections D1, D3, D6, N1, N2, N4 et **arbre widget final (§9)**
- `docs/design/editorial-digest/implementation-plan.md` — ÉTAPE 6

## Architecture actuelle (ce qui existe après 10.25)

### DigestResponse (modèle Dart — `digest_models.dart`)

Les champs suivants sont disponibles et parsés :
```dart
// Sur DigestResponse
String? headerText;      // "☀️ Ce matin, 3 sujets à retenir"
String? closureText;     // "✅ T'es à jour. Bonne journée !"
String? ctaText;         // "Un truc t'a marqué ? Dis-moi 👋"
bool get usesEditorial;  // formatVersion == 'editorial_v1'
bool get usesTopics;     // true pour topics_v1 ET editorial_v1
PepiteResponse? pepite;
CoupDeCoeurResponse? coupDeCoeur;

// Sur DigestTopic (= 1 sujet éditorial)
String? introText;       // "Le gouvernement dévoile..." (2-3 phrases)
String? transitionText;  // "Pendant ce temps, côté tech…"

// Sur DigestItem / DigestTopicArticle
String? badge;           // "actu", "pas_de_recul", "pepite", "coup_de_coeur"
```

### DigestBriefingSection (`digest_briefing_section.dart`)

C'est le widget principal qui rend le contenu du digest. Actuellement il gère :
- `topics_v1` : affiche des `TopicSection` avec PageView horizontal par topic
- `flat_v1` : affiche les `DigestItem` en liste plate

**Il n'y a pas encore de branche `editorial_v1`.** Les digests éditoriaux passent par le chemin `usesTopics == true` et s'affichent comme des topics classiques sans les textes édito.

### DigestProgressBar (`digest_progress_bar.dart`)

Barre segmentée actuelle. En mode `editorial_v1`, elle doit être remplacée par des dots discrets.

### DigestMode (2 modes)

Déjà réduit à `pourVous` + `serein` (le mode `perspective` a été supprimé en 10.25).

## Spécification technique des widgets

### N1 — IntroText (`digest/widgets/intro_text.dart`)

Texte éditorial (2-3 phrases) au-dessus des cartes pour chaque sujet.
- **Input** : `String introText`
- **Typo** : `FacteurTypography.bodyLarge` (17px, w400), line height 1.5
- **Couleur** : `FacteurColors.textPrimary`
- **Padding** : 16px horizontal, 8px top, 12px bottom
- **Si `introText` est null** : ne pas afficher le widget

### N2 — TransitionText (`digest/widgets/transition_text.dart`)

Court texte de liaison entre 2 sujets.
- **Input** : `String transitionText`
- **Typo** : `FacteurTypography.bodySmall` (13px, w400), _italique_
- **Couleur** : `FacteurColors.textSecondary`
- **Séparateur** : ligne 1px `textTertiary @ 20%` au-dessus et en-dessous
- **Padding** : 24px vertical
- **Si `transitionText` est null** (dernier sujet) : ne pas afficher

### N4 — SectionDivider (`digest/widgets/section_divider.dart`)

Séparateur "Et aussi…" entre les 3 sujets principaux et les sections pépite/coup de coeur.
- **Typo** : `FacteurTypography.displaySmall` (18px, w600), centré
- **Décor** : ligne 2px `primary @ 30%`, 60px wide, centrée
- **Padding** : 32px top, 16px bottom

### D1 — Header dynamique

Dans `DigestBriefingSection`, remplacer le titre statique "L'Essentiel du jour" par `digest.headerText` quand non null.
- **Fallback** : si `headerText` est null, garder "L'Essentiel du jour"
- **Typo** : même style existant `FacteurTypography.displayLarge` (28px, w700)

### D3 — Branchement layout

Dans `DigestBriefingSection`, ajouter une branche quand `digest.usesEditorial` :
```
if (digest.usesEditorial) → renderEditorialLayout()
else if (digest.usesTopics) → renderTopicsLayout() (existant)
else → renderFlatLayout() (existant)
```

Le layout éditorial assemble les sujets via un `EditorialSubjectBlock` :
```
for subject in topics:
  Column(
    IntroText(subject.introText),
    [cartes articles existantes — garder le rendu actuel des TopicSection],
    TransitionText(subject.transitionText),  // null pour le dernier
  )

SectionDivider("Et aussi…")

// Pépite + Coup de coeur = cartes normales pour l'instant
// (les widgets PepiteBlock et CoupDeCoeurBlock arrivent en 10.27)
```

### D6 — Progression dots

En mode `editorial_v1`, remplacer la `DigestProgressBar` par des dots discrets :
- N dots (= nombre de sujets + slots pepite/cdc)
- Dot rempli si le sujet est "couvert" (`isCovered`)
- Style : 6x6 cercles, spacing 6px, couleur `primary` (rempli) / `border @ 40%` (vide)
- Position : sous le header text, même row que le mode selector si possible

## Arbre widget attendu (editorial_v1)

```
DigestBriefingSection (modifié D1/D3)
├── Header
│   ├── Text(digest.headerText ?? "L'Essentiel du jour")  ← D1
│   ├── ProgressDots(processedCount / totalCount)          ← D6
│   └── DigestModeTabSelector(2 modes)                     ← existant
│
├── for topic in digest.topics:
│   └── EditorialSubjectBlock
│       ├── IntroText(topic.introText)                     ← N1
│       ├── [cartes articles — rendu TopicSection existant]
│       └── TransitionText(topic.transitionText)           ← N2
│
├── SectionDivider("Et aussi…")                            ← N4
│
├── [Pépite carte — rendu simple pour l'instant]
├── [Coup de coeur carte — rendu simple pour l'instant]
│
└── [Closure block — sera ajouté en Story 10.28]
```

## Ce qui NE FAIT PAS partie de cette story

- **Badges sémantiques (D4)** → Story 10.27
- **Rank badge retiré (D5)** → Story 10.27
- **ArticlePairView swipe horizontal (N3)** → Story 10.27
- **PepiteBlock et CoupDeCoeurBlock (N5)** → Story 10.27
- **ClosureBlock (D7)** → Story 10.28
- **FeedbackBottomSheet (N6)** → Story 10.28

Pour cette story, les cartes articles gardent leur rendu actuel. La pépite et le coup de coeur sont rendus comme des cartes normales en fin de liste. Le focus est sur le **layout et les textes édito**.

## Fichiers à modifier

| Fichier | Changement |
|---------|------------|
| `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` | Branchement D3, header dynamique D1, progression dots D6 |
| `apps/mobile/lib/features/digest/widgets/intro_text.dart` | **NOUVEAU** — Widget N1 |
| `apps/mobile/lib/features/digest/widgets/transition_text.dart` | **NOUVEAU** — Widget N2 |
| `apps/mobile/lib/features/digest/widgets/section_divider.dart` | **NOUVEAU** — Widget N4 |
| `apps/mobile/lib/features/digest/widgets/editorial_subject_block.dart` | **NOUVEAU** — Conteneur qui assemble intro + cartes + transition |
| `apps/mobile/lib/features/digest/widgets/progress_dots.dart` | **NOUVEAU** — Dots de progression (remplace DigestProgressBar en editorial_v1) |

## Dépendances code existant

| Composant | Fichier | Usage |
|-----------|---------|-------|
| `DigestBriefingSection` | `digest_briefing_section.dart` | Widget principal — à modifier |
| `DigestProgressBar` | `digest_progress_bar.dart` | Barre actuelle — garder pour flat_v1/topics_v1, ajouter ProgressDots pour editorial_v1 |
| `TopicSection` | `digest_briefing_section.dart` (ou widget séparé) | Rendu des cartes par topic — réutiliser dans EditorialSubjectBlock |
| `DigestCard` | `digest_card.dart` | Carte article — réutiliser tel quel |
| `FacteurTypography` | `core/theme/` | Typography tokens |
| `FacteurColors` | `core/theme/` | Color tokens |
| `digest_provider.dart` | provider | `processedCount`, `totalCount`, `progress` — déjà mis à jour en 10.25 |

## Fallbacks

- Si `headerText` est null → afficher "L'Essentiel du jour" (texte statique existant)
- Si `introText` est null → pas de bloc texte au-dessus des cartes (espace direct vers les cartes)
- Si `transitionText` est null → pas de transition (normal pour le dernier sujet)
- Si `pepite`/`coupDeCoeur` est null → ne pas afficher le SectionDivider ni les sections correspondantes
- Si un digest est `topics_v1` → zéro changement, le layout actuel est conservé

## Critères de validation

1. Un digest `editorial_v1` affiche le header dynamique (`headerText`)
2. Chaque sujet montre son `introText` au-dessus des cartes
3. Les transitions `transitionText` apparaissent entre les sujets (pas après le dernier)
4. Le SectionDivider "Et aussi…" apparaît avant pépite/cdc
5. Les dots de progression reflètent le nombre de sujets couverts
6. Un digest `topics_v1` ou `flat_v1` **n'est pas affecté** (rétrocompatibilité)
7. `flutter analyze` + `flutter test` passent
8. Le scroll est fluide (pas de jank) avec les nouveaux widgets texte

## Risques

- **Conflit de layout** : `DigestBriefingSection` est un widget complexe (~400+ lignes). Bien comprendre le flow existant avant de toucher au layout.
- **FacteurTypography / FacteurColors** : vérifier que les tokens existent (`displayLarge`, `bodyLarge`, `bodySmall`, `displaySmall`, `textPrimary`, `textSecondary`, `textTertiary`). Si non, utiliser les équivalents les plus proches du design system.
- **TopicSection réutilisation** : le rendu des cartes par topic est peut-être intimement lié au layout topics_v1. Si c'est le cas, extraire la logique de cartes dans un widget partagé plutôt que dupliquer.

## Contraintes techniques

- **Flutter SDK >=3.0.0 <4.0.0**
- **Riverpod 2.5** (code gen, build_runner)
- **Python 3.12 only** côté backend (pas touché dans cette story)
- Après modification des widgets Freezed : `dart run build_runner build --delete-conflicting-outputs`
