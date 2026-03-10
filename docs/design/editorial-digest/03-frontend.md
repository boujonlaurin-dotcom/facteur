# Design Doc — Frontend : Delta depuis l'existant

**Version:** 2.0
**Date:** 10 mars 2026
**Auteur:** Brainstorm Laurin + Claude
**Statut:** Draft — Chaque modification est challengeable individuellement

---

## Principe

Ce document décrit **uniquement ce qui change** par rapport aux stories existantes de l'Epic 10.
Chaque modification est numérotée et indépendante pour faciliter la validation.

**Convention :** `✅ Conservé` = rien à faire | `🔀 Modifié` = delta | `🆕 Nouveau` = widget/feature à créer

---

## 1. Impact sur Story 10.9 — Écran Digest Flutter

> **Fichier existant :** `digest/widgets/digest_briefing_section.dart`
> **Réf story :** [10.9.ecran-digest-flutter.story.md](10.9.ecran-digest-flutter.story.md)

### ✅ Ce qui ne change pas

- Container `DigestBriefingSection` (gradient animé, border, shadow, border radius 24px)
- Scaffold avec Riverpod consumer
- États gérés : loading (shimmer), error (retry), empty
- Pull-to-refresh
- Scroll vertical (ListView)

### 🔀 Modification D1 — Header dynamique

| Avant | Après |
|-------|-------|
| Texte fixe "L'Essentiel du jour" (23px, w800) + compteur segmenté "3/5" | Texte dynamique venant de l'API (`headerText`), ex: "☀️ Ce matin, 3 sujets à retenir" |

**Fichier impacté :** `digest_briefing_section.dart` (header section)
**Ce qui change :** le titre statique est remplacé par `digest.headerText` (String renvoyé par l'API).
**Typo :** même `FacteurTypography.displayLarge` (28px, w700) — pas de changement de style.

### 🔀 Modification D2 — Mode selector réduit à 2 modes

| Avant | Après |
|-------|-------|
| 3 modes : Pour vous / Serein / Ouvrir son point de vue | 2 modes : Pour vous / Serein |

**Fichier impacté :** `digest_mode_tab_selector.dart`, `digest_mode.dart`
**Ce qui change :** retrait du mode `perspective` de l'enum et du segmented control.

### 🔀 Modification D3 — Layout branche sur `format_version`

| Avant | Après |
|-------|-------|
| Branchement `flat_v1` / `topics_v1` | Ajout branche `editorial_v1` |

**Fichier impacté :** `digest_briefing_section.dart`
**Ce qui change :** un `switch` sur `formatVersion` rend le layout `editorial_v1` si présent, sinon fallback sur `topics_v1` existant. **Rétrocompatibilité totale.**

---

## 2. Impact sur Story 10.10 — Carte Digest

> **Fichier existant :** `digest/widgets/digest_card.dart`
> **Réf story :** [10.10.carte-digest.story.md](10.10.carte-digest.story.md)

### ✅ Ce qui ne change pas

- Layout carte : thumbnail (FacteurThumbnail) + body (titre, description, durée) + footer (source logo, nom, recency)
- FacteurCard wrapper (tap scale animation, no shadow)
- Overlays de statut (top-right : "Lu"/"Masqué")
- Interaction : tap = ouvrir article
- Swipe droit/gauche (SwipeToOpenCard) avec haptic feedback

### 🔀 Modification D4 — Badge sémantique remplace le reason badge

| Avant | Après |
|-------|-------|
| Badge `reason` algorithmique en body ("Sujet tendance", "À la Une", "Thème favori") | Badge sémantique éditorial |
| Couleur dynamique par type de reason | 4 badges fixes avec couleurs définies |

**Badges :**

| Badge | Label | Couleur background |
|-------|-------|--------------------|
| 🔴 | L'actu du jour | `FacteurColors.primary` @ 10% (light) / 15% (dark) |
| 🔭 | Le pas de recul | `FacteurColors.info` @ 10% / 15% |
| 🍀 | Pépite du jour | `FacteurColors.success` @ 10% / 15% |
| 💚 | Coup de cœur | `FacteurColors.success` @ 10% / 15% |

**Fichier impacté :** `digest_card.dart` (section reason badge)
**Ce qui change :** le badge `reason` affiche un des 4 badges fixes au lieu d'un texte algorithmique. Le badge est un champ `badge` (enum) dans le modèle `DigestItem`. Style existant (`FacteurTypography.labelSmall`, `FacteurRadius.small`, padding 8h/3v) conservé.

**Mode serein :** les badges 🔴 et 🔭 perdent leur emoji (juste le texte). Badges 🍀 et 💚 inchangés.

### 🔀 Modification D5 — Rank badge retiré

| Avant | Après |
|-------|-------|
| Cercle 28x28 top-left avec "#1", "#2", etc. | Pas de rank badge — le contexte est donné par l'édito |

**Fichier impacté :** `digest_card.dart` (overlay top-left)
**Ce qui change :** le rank badge n'est pas affiché en mode `editorial_v1`. Conservé pour les anciens formats.

---

## 3. Impact sur Story 10.11 — Barre de progression

> **Fichier existant :** `digest/widgets/digest_briefing_section.dart` (progress segmenté dans le header)
> **Réf story :** [10.11.barre-progression.story.md](10.11.barre-progression.story.md)

### 🔀 Modification D6 — Progression simplifiée

| Avant | Après |
|-------|-------|
| Barre segmentée "3/5" dans le header + messages contextuels ("Bon début", "Encore un peu...") | Indicateur discret intégré dans le header (ex: 3 dots remplis / 5 total) |

**Rationale :** la progression numérique "3/5" entre en conflit avec l'expérience éditoriale. Le digest doit se lire comme un journal, pas comme une checklist. L'indicateur reste présent mais plus subtil.

**Ce qui change :** le `DigestProgressBar` segmenté est remplacé par des dots discrets sous le header en mode `editorial_v1`. Le seuil de completion (`completionThreshold`) reste identique côté backend.

**Fichier impacté :** header section de `digest_briefing_section.dart`

---

## 4. Impact sur Story 10.12 — Closure

> **Fichier existant :** closure intégrée dans le digest flow
> **Réf story :** [10.12.ecran-closure.story.md](10.12.ecran-closure.story.md)

### 🔀 Modification D7 — Closure inline au lieu de full-screen

| Avant | Après |
|-------|-------|
| Full-screen overlay ClosureScreen (confettis, stats, "Tu es informé !") | Bloc inline en bas du digest (texte closure + CTA feedback) |

**Rationale :** la closure full-screen casse le flow de lecture. En mode éditorial, le digest se finit naturellement par le texte de closure généré par le LLM — c'est un paragraphe, pas un écran.

**Ce qui change :**
- Le `ClosureBlock` est un widget inline en fin de scroll (pas un écran séparé)
- Texte : `closureText` de l'API ("✅ T'es à jour. Bonne journée !")
- CTA : `ctaText` de l'API ("Un truc t'a marqué ? Dis-moi 👋")
- Un bouton "Donner un retour" (OutlinedButton, pill radius)
- Animation : fade-in + scale léger quand le bloc entre dans le viewport
- **Les stats (streak, articles lus) et confettis sont retirés** de ce flow — le streak reste visible dans le profil/settings

**Impact fichiers :** nouveau widget `closure_block.dart`, modification du flow de completion dans `digest_provider.dart` (ne navigue plus vers un écran séparé)

---

## 5. Impact sur Story 10.15 — Push notification

> **Réf story :** [10.15.notification-push.story.md](10.15.notification-push.story.md)

### 🔀 Modification D8 — Texte de push revu

| Avant | Après |
|-------|-------|
| "Ton essentiel du jour est prêt" | "Ton Essentiel est prêt — 5 min pour être à jour" |

**Ce qui change :** juste le texte. Logique de scheduling identique.

---

## 6. Widgets entièrement nouveaux (pas de delta)

Ces widgets n'existaient pas. Ils sont créés from scratch pour le format `editorial_v1`.

### 🆕 N1 — IntroText

Affiche le texte éditorial (2-3 phrases) au-dessus des cartes pour chaque sujet.

- **Contenu :** `subject.introText` (String venant de l'API, généré par LLM)
- **Typo :** `FacteurTypography.bodyLarge` (17px, w400), line height 1.5
- **Couleur :** `FacteurColors.textPrimary`
- **Padding :** 16px horizontal, 8px top, 12px bottom
- **Fichier :** `digest/widgets/intro_text.dart`

### 🆕 N2 — TransitionText

Court texte de liaison entre 2 sujets ("Pendant ce temps, côté tech…").

- **Contenu :** `subject.transitionText` (nullable — absent après le dernier sujet)
- **Typo :** `FacteurTypography.bodySmall` (13px, w400), italique
- **Couleur :** `FacteurColors.textSecondary`
- **Séparateur :** ligne 1px `textTertiary @ 20%` au-dessus et en-dessous
- **Padding :** 24px vertical
- **Fichier :** `digest/widgets/transition_text.dart`

### 🆕 N3 — ArticlePairView

Conteneur PageView pour le swipe horizontal entre carte actu et carte deep.

- **Basé sur :** la mécanique `PageView` existante de `TopicSection` (viewportFraction: 0.88, dot indicators, 200ms animation)
- **Comportement :**
  - Si deep article présent : 2 pages (actu → deep), dot indicators
  - Si pas de deep : 1 page, pleine largeur, pas de dots
- **Fichier :** `digest/widgets/article_pair_view.dart`
- **Conflit de gestes :** le swipe horizontal (PageView) coexiste avec le swipe droit/gauche (SwipeToOpenCard). À tester : le PageView capte les gestes strictement horizontaux, le SwipeToOpenCard les gestes diagonaux (seuil 25% existant).

### 🆕 N4 — SectionDivider

Séparateur visuel "Et aussi…" entre les 3 sujets et les pépites.

- **Typo :** `FacteurTypography.displaySmall` (18px, w600), centré
- **Décor :** ligne 2px `primary @ 30%`, 60px, centrée
- **Padding :** 32px top, 16px bottom
- **Fichier :** `digest/widgets/section_divider.dart`

### 🆕 N5 — PepiteBlock & CoupDeCoeurBlock

Wrappers simples autour de `DigestCard` avec contexte éditorial.

- **PepiteBlock :** `IntroText` (mini-édito 1 phrase) + `DigestCard` badge 🍀
- **CoupDeCoeurBlock :** `DigestCard` badge 💚 + sous-badge "Gardé par {n} lecteurs" (`labelSmall`, `textSecondary`)
- **Fichiers :** `digest/widgets/pepite_block.dart`, `digest/widgets/coup_de_coeur_block.dart`

### 🆕 N6 — FeedbackBottomSheet

Bottom sheet post-closure pour le CTA feedback.

- 3 emojis sélectionnables (😍 Top / 😊 Bien / 😐 Bof)
- TextField optionnel (280 chars max)
- Bouton "Envoyer"
- **Fichier :** `digest/widgets/feedback_bottom_sheet.dart`
- **Backend :** endpoint feedback à définir (ou stockage local en V1)

---

## 7. Impact sur les modèles de données

### 🔀 Modification D9 — DigestResponse étendu

**Fichier :** `digest/models/digest_models.dart`

Ajout de champs au modèle existant `DigestResponse` (ou sous-modèle conditionnel si `format_version == "editorial_v1"`) :

| Champ nouveau | Type | Description |
|---------------|------|-------------|
| `headerText` | `String` | Titre éditorialisé du digest |
| `closureText` | `String` | Texte de closure LLM |
| `ctaText` | `String` | CTA feedback |
| `subjects` | `List<EditorialSubject>` | 3 blocs sujet (intro + actu + deep) |
| `pepite` | `EditorialSlot?` | Slot pépite avec mini-édito |
| `coupDeCoeur` | `EditorialSlot?` | Slot coup de cœur avec community_saves |

**`EditorialSubject`** (nouveau) :
- `topicId`, `label`, `rank`
- `introText` (2-3 phrases)
- `transitionText?` (null pour le dernier)
- `actuArticle` (DigestItem existant + `badge: "actu"`)
- `deepArticle?` (DigestItem existant + `badge: "pas_de_recul"`, nullable)
- `isUserSource` (bool)

**`EditorialSlot`** (nouveau) :
- `article` (DigestItem)
- `badge` ("pepite" | "coup_de_coeur")
- `miniEditorial?` (String, pépite uniquement)
- `communitySaves?` (int, coup de cœur uniquement)

### 🔀 Modification D10 — DigestMode réduit

**Fichier :** `digest/models/digest_mode.dart`

Retrait de `perspective` de l'enum `DigestMode`. Seuls `pourVous` et `serein` restent.

---

## 8. Récapitulatif des modifications (checklist challengeable)

### Modifications de l'existant (deltas)

| # | Story impactée | Modification | Fichier(s) | Challengeable ? |
|---|---------------|-------------|-----------|:---:|
| D1 | 10.9 | Header dynamique (API text) | `digest_briefing_section.dart` | Oui |
| D2 | 10.9 | Mode selector 3→2 modes | `digest_mode_tab_selector.dart`, `digest_mode.dart` | Oui |
| D3 | 10.9 | Branchement `editorial_v1` layout | `digest_briefing_section.dart` | Non (structurel) |
| D4 | 10.10 | Badge sémantique remplace reason | `digest_card.dart` | Oui |
| D5 | 10.10 | Rank badge retiré | `digest_card.dart` | Oui |
| D6 | 10.11 | Progression simplifiée (dots) | `digest_briefing_section.dart` | Oui |
| D7 | 10.12 | Closure inline vs full-screen | Nouveau `closure_block.dart` | Oui |
| D8 | 10.15 | Texte push revu | Config notification | Oui |
| D9 | Modèles | DigestResponse + nouveaux types | `digest_models.dart` | Non (structurel) |
| D10 | Modèles | DigestMode 3→2 | `digest_mode.dart` | Oui |

### Nouveaux widgets

| # | Widget | Dépend de |
|---|--------|-----------|
| N1 | IntroText | D3 (layout editorial) |
| N2 | TransitionText | D3 |
| N3 | ArticlePairView | D3, D4 (badges) |
| N4 | SectionDivider | D3 |
| N5 | PepiteBlock + CoupDeCoeurBlock | D3, D4 |
| N6 | FeedbackBottomSheet | D7 (closure inline) |

---

## 9. Arbre widget final (editorial_v1)

```
DigestBriefingSection (existant, modifié D1/D3)
├── EditorialHeader (D1: headerText dynamique + D2: 2 modes)
│   ├── Text(digest.headerText)              ← D1
│   ├── ProgressDots(3/5)                    ← D6
│   └── DigestModeTabSelector(2 modes)       ← D2
│
├── for subject in subjects:                 ← D3 branchement
│   └── Column
│       ├── IntroText(subject.introText)     ← N1
│       ├── ArticlePairView                  ← N3
│       │   ├── DigestCard(actu, badge 🔴)   ← D4
│       │   └── DigestCard(deep?, badge 🔭)  ← D4
│       └── TransitionText?(...)             ← N2
│
├── SectionDivider("Et aussi…")              ← N4
│
├── PepiteBlock                              ← N5
│   ├── IntroText(pepite.miniEditorial)
│   └── DigestCard(badge 🍀)                 ← D4
│
├── CoupDeCoeurBlock                         ← N5
│   └── DigestCard(badge 💚) + saves count   ← D4
│
└── ClosureBlock                             ← D7
    ├── Text(digest.closureText)
    ├── Text(digest.ctaText)
    └── FeedbackButton → FeedbackBottomSheet ← N6
```

---

*Réf design : [01-pipeline.md](01-pipeline.md) (backend), [02-editorial.md](02-editorial.md) (ton & prompts)*
