# Design Doc — Frontend Digest Éditorialisé

**Version:** 1.0
**Date:** 10 mars 2026
**Auteur:** Brainstorm Laurin + Claude
**Statut:** Draft — En attente validation

---

## 1. Vue d'ensemble

### 1.1 Changements UI

Le digest passe du format `topics_v1` (topic clusters avec horizontal scroll) au format `editorial_v1` :

| Avant (topics_v1) | Après (editorial_v1) |
|-------------------|---------------------|
| Header "L'Essentiel du jour — 3/5" | Header éditorialisé dynamique |
| Topic sections avec PageView horizontal | Blocs éditoriaux avec swipe actu/deep |
| Reason badges algorithmiques | Badges sémantiques (🔴 🔭 🍀 💚) |
| Pas de texte entre les cartes | Texte édito + transitions entre chaque bloc |
| Closure = progression complète | Closure = texte éditorial + CTA feedback |

### 1.2 Ce qui ne change pas

- Container `DigestBriefingSection` (gradient, border, shadow)
- `FacteurCard` base widget (tap scale animation)
- `FacteurThumbnail` pour les images
- Swipe mechanics (`SwipeToOpenCard`)
- Mode selector (segmented control) — mais modes ajustés
- Design tokens (couleurs, typo, spacing, radius)
- Dismiss banner + mute flow

---

## 2. Nouveau format de données

### 2.1 DigestResponse (editorial_v1)

```dart
class EditorialDigestResponse {
  final String digestId;
  final String userId;
  final String targetDate;
  final String formatVersion; // "editorial_v1"
  final String mode; // "pour_vous", "serein"
  final String headerText;
  final List<EditorialSubject> subjects; // 3 sujets
  final EditorialSlot pepite;
  final EditorialSlot coupDeCoeur;
  final String closureText;
  final String ctaText;
  final bool isCompleted;
  final DateTime? completedAt;
  final int completionThreshold;
  final DateTime generatedAt;
}
```

### 2.2 EditorialSubject

```dart
class EditorialSubject {
  final String topicId;
  final String label;
  final int rank; // 1, 2, 3
  final String introText; // 2-3 phrases édito
  final String? transitionText; // null pour le dernier sujet
  final DigestItem actuArticle; // 🔴 L'actu du jour
  final DigestItem? deepArticle; // 🔭 Le pas de recul (nullable)
  final bool isUserSource; // true si actu = source suivie
}
```

### 2.3 EditorialSlot

```dart
class EditorialSlot {
  final DigestItem article;
  final String badge; // "pepite" | "coup_de_coeur"
  final String? miniEditorial; // 1-2 phrases (pépite)
  final int? communitySaves; // nombre de saves (coup de cœur)
}
```

---

## 3. Layout complet

### 3.1 Structure verticale du digest

```
┌─ DigestBriefingSection (container existant) ───────────┐
│                                                         │
│  ┌─ EditorialHeader ─────────────────────────────────┐  │
│  │  headerText (dynamique, LLM)                      │  │
│  │  Mode selector (segmented control)                │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ EditorialSubjectBlock (×3) ──────────────────────┐  │
│  │                                                    │  │
│  │  ┌─ IntroText ─────────────────────────────────┐  │  │
│  │  │  "📌 Trump menace de couper..."              │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                                                    │  │
│  │  ┌─ ArticlePairView (PageView) ────────────────┐  │  │
│  │  │  Page 1: ActuCard (🔴)                       │  │  │
│  │  │  Page 2: DeepCard (🔭) — si dispo            │  │  │
│  │  │  [dot indicators]                            │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                                                    │  │
│  │  ┌─ TransitionText ────────────────────────────┐  │  │
│  │  │  "Pendant ce temps, côté tech…"              │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                                                    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ SectionDivider ("Et aussi…") ────────────────────┐  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ PepiteBlock ─────────────────────────────────────┐  │
│  │  Mini-édito (1 phrase)                             │  │
│  │  PepiteCard (🍀)                                   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ CoupDeCoeurBlock ────────────────────────────────┐  │
│  │  CoupDeCoeurCard (💚) + "Gardé par N lecteurs"    │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─ ClosureBlock ────────────────────────────────────┐  │
│  │  closureText + ctaText + feedback button           │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Responsive et scroll

- Le digest entier est un **scroll vertical** (ListView ou SingleChildScrollView)
- Chaque `EditorialSubjectBlock` contient un **PageView horizontal** pour le swipe actu/deep
- Les blocs Pépite et Coup de cœur sont des cartes simples (pas de swipe)
- Le scroll vertical est naturel et continu — pas de pagination entre les sujets

---

## 4. Widgets détaillés

### 4.1 EditorialHeader

Remplace le header actuel "L'Essentiel du jour — 3/5".

```
┌───────────────────────────────────────────────┐
│                                               │
│  ☀️ Ce matin, 3 sujets à retenir             │
│     + tes pépites                             │
│                                               │
│  [Pour vous]  [Serein]          ← segmented   │
│                                               │
└───────────────────────────────────────────────┘
```

**Specs :**
- Titre : `FacteurTypography.displayLarge` (28px, w700, DM Sans)
- Couleur : `FacteurColors.textPrimary`
- Padding : `FacteurSpacing.space4` (16px) horizontal, `space3` (12px) vertical
- Le titre vient du `headerText` de l'API (dynamique)
- Mode selector : composant existant `DigestModeTabSelector`, mais avec seulement 2 modes : "Pour vous" et "Serein" (le mode "Ouvrir son point de vue" est retiré en V1)

### 4.2 IntroText (texte éditorial)

Nouveau widget. Affiche le texte d'intro LLM entre le header de sujet et les cartes.

```
┌───────────────────────────────────────────────┐
│ 📌 Trump menace de couper les réseaux sociaux │
│ en Europe. Pas réaliste à date — mais ça      │
│ révèle la guerre numérique qui oppose les     │
│ deux blocs depuis 20 ans. The Conversation    │
│ décrypte comment on en est arrivé là.         │
└───────────────────────────────────────────────┘
```

**Specs :**
- Police : `FacteurTypography.bodyLarge` (17px, w400, DM Sans)
- Couleur : `FacteurColors.textPrimary`
- Line height : 1.5 (aéré pour la lecture)
- Padding : `space4` (16px) horizontal, `space2` (8px) top, `space3` (12px) bottom
- Les emojis (📌, 🔴) font partie du texte renvoyé par l'API

### 4.3 ArticlePairView (swipe actu/deep)

Réutilise la mécanique `PageView` existante du `TopicSection`.

**Avec deep article :**

```
┌──────────────────────┐  ┌──────────────────────┐
│ ┌──────────────────┐ │  │ ┌──────────────────┐ │
│ │   [thumbnail]    │ │  │ │   [thumbnail]    │ │
│ │                  │ │  │ │                  │ │
│ └──────────────────┘ │  │ └──────────────────┘ │
│ 🔴 L'actu du jour    │  │ 🔭 Le pas de recul   │
│                      │  │                      │
│ "Trump brandit la    │  │ "Souveraineté        │
│  menace d'un blocage │  │  numérique : 20 ans  │
│  des réseaux en UE"  │  │  de dépendance       │
│                      │  │  européenne"          │
│ Le Monde · 3 min     │  │ The Conversation     │
│ Aujourd'hui          │  │ · 8 min              │
└──────────────────────┘  └──────────────────────┘
         ●  ○              ← dot indicators
```

**Sans deep article :**

```
┌──────────────────────────────────────────────┐
│ ┌──────────────────────────────────────────┐ │
│ │            [thumbnail]                   │ │
│ └──────────────────────────────────────────┘ │
│ 🔴 L'actu du jour                            │
│                                              │
│ "Apple passe à l'USB-C en Europe"            │
│                                              │
│ France Info · 3 min · Aujourd'hui            │
└──────────────────────────────────────────────┘
         (pas de dots — carte unique pleine largeur)
```

**Specs PageView :**
- `viewportFraction: 0.88` (existant — 12% de la carte suivante visible)
- Hauteur fixe : thumbnail 16:9 aspect ratio + 170px body/footer (existant)
- Dot indicators : active = 16px wide, inactive = 6px (existant)
- Animation : 200ms smooth transition (existant)

### 4.4 Badge Article

Nouveau widget. Remplace le `reason` badge actuel par un badge sémantique.

```
┌────────────────────────┐
│ 🔴 L'actu du jour      │    ← mode normal
└────────────────────────┘

┌────────────────────────┐
│ L'actu du jour         │    ← mode serein (pas d'emoji)
└────────────────────────┘

┌────────────────────────┐
│ 🔭 Le pas de recul     │    ← deep article
└────────────────────────┘
```

**Specs :**
- Conteneur : `FacteurRadius.small` (8px), padding 8px horiz / 3px vert (existant)
- Background :
  - 🔴 L'actu du jour : `FacteurColors.primary.withOpacity(0.10)` (light) / `0.15` (dark)
  - 🔭 Le pas de recul : `FacteurColors.info.withOpacity(0.10)` (light) / `0.15` (dark)
  - 🍀 Pépite : `FacteurColors.success.withOpacity(0.10)` (light) / `0.15` (dark)
  - 💚 Coup de cœur : `FacteurColors.success.withOpacity(0.10)` (light) / `0.15` (dark)
- Texte : `FacteurTypography.labelSmall` (11px, w500, 0.5 letter-spacing)
- Couleur texte : même couleur que le background mais pleine opacité

### 4.5 TransitionText

Nouveau widget. Court texte de liaison entre les sujets.

```
───────────────────────────────────────
  Pendant ce temps, côté tech…
───────────────────────────────────────
```

**Specs :**
- Police : `FacteurTypography.bodySmall` (13px, w400) en italique
- Couleur : `FacteurColors.textSecondary`
- Padding : `space6` (24px) vertical
- Séparateur : ligne fine 1px, `FacteurColors.textTertiary.withOpacity(0.2)`, margin `space4` (16px) horizontal
- Le texte est centré

### 4.6 SectionDivider ("Et aussi…")

Marque la transition entre les 3 sujets principaux et les pépites.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Et aussi…
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Specs :**
- Texte : `FacteurTypography.displaySmall` (18px, w600)
- Couleur : `FacteurColors.textPrimary`
- Centré horizontalement
- Padding : `space8` (32px) top, `space4` (16px) bottom
- Ligne décorative : 2px, `FacteurColors.primary.withOpacity(0.3)`, 60px de large, centrée

### 4.7 PepiteBlock

```
┌───────────────────────────────────────────────┐
│                                               │
│  Un prof de maths japonais a résolu un        │
│  problème ouvert depuis 50 ans. La            │
│  démonstration tient en 3 pages. Magnifique.  │
│                                               │
│  ┌───────────────────────────────────────┐    │
│  │ 🍀 Pépite du jour                     │    │
│  │                                       │    │
│  │ "La preuve la plus élégante de        │    │
│  │  l'année"                              │    │
│  │                                       │    │
│  │ Slate · 6 min                          │    │
│  └───────────────────────────────────────┘    │
│                                               │
└───────────────────────────────────────────────┘
```

**Specs :**
- Mini-édito : même style que `IntroText` mais plus court
- Carte : `DigestCard` standard avec badge 🍀
- Pas de swipe — carte unique pleine largeur

### 4.8 CoupDeCoeurBlock

```
┌───────────────────────────────────────────────┐
│                                               │
│  ┌───────────────────────────────────────┐    │
│  │ 💚 Coup de cœur                       │    │
│  │ Gardé par 47 lecteurs                 │    │
│  │                                       │    │
│  │ "Et si on repensait la ville à       │    │
│  │  partir du silence ?"                 │    │
│  │                                       │    │
│  │ Usbek & Rica · 10 min                │    │
│  └───────────────────────────────────────┘    │
│                                               │
└───────────────────────────────────────────────┘
```

**Specs :**
- Badge 💚 + sous-badge "Gardé par {n} lecteurs"
- Sous-badge : `FacteurTypography.labelSmall`, `FacteurColors.textSecondary`
- Carte : `DigestCard` standard avec badge 💚
- Pas de mini-édito (le signal communautaire suffit)

### 4.9 ClosureBlock

```
┌───────────────────────────────────────────────┐
│                                               │
│        ✅ T'es à jour. Bonne journée !        │
│                                               │
│     Un truc t'a marqué ? Dis-moi 👋          │
│                                               │
│         ┌──────────────────────┐              │
│         │   Donner un retour   │              │
│         └──────────────────────┘              │
│                                               │
└───────────────────────────────────────────────┘
```

**Specs :**
- Closure text : `FacteurTypography.displaySmall` (18px, w600), centré
- CTA text : `FacteurTypography.bodySmall` (13px), `FacteurColors.textSecondary`, centré
- Bouton feedback : `OutlinedButton`, `FacteurRadius.pill` (100px), `FacteurColors.primary`
- Padding : `space8` (32px) top, `space6` (24px) bottom
- Animation d'apparition : fade-in 400ms quand le bloc entre dans le viewport

---

## 5. Mode Serein — Ajustements UI

| Élément | Normal | Serein |
|---------|--------|--------|
| Gradient container | Ambre/sunset (existant pourVous) | Vert/lotus (existant serein) |
| Badge 🔴 L'actu | Avec emoji | Sans emoji : "L'actu du jour" |
| Badge 🔭 Le pas de recul | Avec emoji | Sans emoji : "Le pas de recul" |
| Badge 🍀 Pépite | Avec emoji | Avec emoji (pas anxiogène) |
| Badge 💚 Coup de cœur | Avec emoji | Avec emoji (pas anxiogène) |
| Intro text | Ton direct, punchy | Ton calme, neutre |
| Header | "3 sujets à retenir" | "3 sujets pour bien démarrer" |
| Closure | "T'es à jour. Bonne journée !" | "T'es à jour. Prends soin de toi !" |

L'API renvoie le `mode` dans la réponse. Le frontend applique les variations d'affichage en fonction.

---

## 6. Interactions

### 6.1 Swipe actu/deep

- **Swipe horizontal** (PageView existant) : navigation entre carte actu et carte deep
- **Swipe droit** sur une carte (SwipeToOpenCard existant) : ouvrir l'article
- **Swipe gauche** sur une carte : dismiss (existant)
- Les deux directions de swipe coexistent : horizontal = navigation, diagonal/vertical = action

**Gestion du conflit de gestes :**
- Le PageView capte les swipes strictement horizontaux
- Le SwipeToOpenCard capte les swipes avec composante diagonale (existant : seuil 25% largeur écran)
- Pas de conflit si les seuils sont bien calibrés (à tester)

### 6.2 Actions utilisateur

| Action | Geste | Feedback | Backend |
|--------|-------|----------|---------|
| Lire un article | Tap sur carte | Ouvre WebView/in-app | `POST /digest/{id}/action` (read) |
| Ouvrir un article | Swipe droit | Haptic medium | `POST /digest/{id}/action` (read) |
| Dismiss article | Swipe gauche | Slide off + haptic | `POST /digest/{id}/action` (not_interested) |
| Swipe actu → deep | Swipe horizontal | Page snap | Pas d'appel (navigation locale) |
| Donner feedback | Tap bouton closure | Ouvre bottom sheet | Nouveau endpoint ou formulaire |

### 6.3 Progression et completion

- **Compteur** : chaque article lu/sauvé/dismissé compte comme 1 interaction
- **Seuil** : `completionThreshold` (configurable, ex: 5 sur 7 articles potentiels)
- Articles potentiels : 3 actu + jusqu'à 3 deep + pépite + coup de cœur = 5 à 8
- **Completion automatique** quand seuil atteint → closure apparaît avec animation

### 6.4 Feedback CTA

Le bouton "Donner un retour" ouvre un bottom sheet simple :

```
┌───────────────────────────────────────────────┐
│                                               │
│  Comment c'était ce matin ?                   │
│                                               │
│  😍  Top       😊  Bien      😐  Bof         │
│                                               │
│  Un commentaire ? (optionnel)                 │
│  ┌───────────────────────────────────────┐    │
│  │                                       │    │
│  └───────────────────────────────────────┘    │
│                                               │
│         ┌──────────────────────┐              │
│         │      Envoyer         │              │
│         └──────────────────────┘              │
│                                               │
└───────────────────────────────────────────────┘
```

**Specs :**
- 3 emojis tap-to-select (un seul sélectionnable)
- TextField optionnel (max 280 caractères)
- Données envoyées à un endpoint feedback (nouveau) ou stockées localement pour v1

---

## 7. Animations

| Élément | Animation | Durée | Easing |
|---------|-----------|-------|--------|
| Header apparition | Fade-in + slide down | 400ms | easeOutCubic |
| IntroText apparition | Fade-in | 300ms | easeOut |
| Card PageView | Spring snap | 200ms | (existant) |
| TransitionText | Fade-in | 250ms | easeOut |
| ClosureBlock | Fade-in + scale (0.95→1.0) | 400ms | easeOutBack |
| Feedback emoji select | Scale bounce (1.0→1.2→1.0) | 200ms | easeOutBack |
| Badge apparition | Fade-in | `FacteurDurations.fast` (150ms) | linear |

Les animations sont déclenchées au scroll (visibility detection) — pas au chargement initial.

---

## 8. Arbre des widgets (résumé)

```
DigestBriefingSection (existant, étendu)
├── EditorialHeader (nouveau)
│   ├── Text(headerText)
│   └── DigestModeTabSelector (existant, 2 modes)
│
├── ListView.builder(subjects)
│   └── EditorialSubjectBlock (nouveau) ×3
│       ├── IntroText (nouveau)
│       ├── ArticlePairView (nouveau, basé sur TopicSection PageView)
│       │   ├── ActuCard (DigestCard + badge 🔴)
│       │   └── DeepCard? (DigestCard + badge 🔭, nullable)
│       └── TransitionText? (nouveau, nullable pour dernier sujet)
│
├── SectionDivider (nouveau)
│
├── PepiteBlock (nouveau)
│   ├── Text(miniEditorial)
│   └── DigestCard + badge 🍀
│
├── CoupDeCoeurBlock (nouveau)
│   └── DigestCard + badge 💚 + sous-badge saves
│
└── ClosureBlock (nouveau)
    ├── Text(closureText)
    ├── Text(ctaText)
    └── FeedbackButton → FeedbackBottomSheet
```

---

## 9. Compatibilité format_version

Le frontend détecte `format_version` et rend le layout approprié :

```dart
Widget build(BuildContext context) {
  final digest = ref.watch(digestProvider);

  return switch (digest.formatVersion) {
    'editorial_v1' => EditorialDigestLayout(digest: digest),
    'topics_v1' => TopicsDigestLayout(digest: digest), // existant
    'flat_v1' => FlatDigestLayout(digest: digest),     // legacy
    _ => TopicsDigestLayout(digest: digest),            // fallback
  };
}
```

**Rétrocompatibilité totale** : les anciens digests restent affichables.

---

## 10. Fichiers impactés

### Nouveaux widgets

| Fichier | Widget |
|---------|--------|
| `digest/widgets/editorial_header.dart` | EditorialHeader |
| `digest/widgets/editorial_subject_block.dart` | EditorialSubjectBlock |
| `digest/widgets/intro_text.dart` | IntroText |
| `digest/widgets/article_pair_view.dart` | ArticlePairView |
| `digest/widgets/transition_text.dart` | TransitionText |
| `digest/widgets/section_divider.dart` | SectionDivider |
| `digest/widgets/pepite_block.dart` | PepiteBlock |
| `digest/widgets/coup_de_coeur_block.dart` | CoupDeCoeurBlock |
| `digest/widgets/closure_block.dart` | ClosureBlock |
| `digest/widgets/article_badge.dart` | ArticleBadge |
| `digest/widgets/feedback_bottom_sheet.dart` | FeedbackBottomSheet |

### Widgets modifiés

| Fichier | Changement |
|---------|-----------|
| `digest/widgets/digest_briefing_section.dart` | Branchement `editorial_v1` layout |
| `digest/widgets/digest_card.dart` | Support des nouveaux badges |

### Modèles modifiés

| Fichier | Changement |
|---------|-----------|
| `digest/models/digest_models.dart` | Nouveaux modèles editorial_v1 |
| `digest/models/digest_mode.dart` | Retrait mode "perspective" en V1 |

### Providers modifiés

| Fichier | Changement |
|---------|-----------|
| `digest/providers/digest_provider.dart` | Parsing editorial_v1 |

---

*Voir aussi : [01-pipeline.md](01-pipeline.md) — Pipeline backend, [02-editorial.md](02-editorial.md) — Ligne éditoriale*
