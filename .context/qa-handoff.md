# QA Handoff — Refonte hi-fi Couverture médiatique (Story 7.4 Sprint 2 front)

> Reconvergence des deux workstreams (`22.1.x-backend-interests` + `flux-continu-v18-refonte` + WIP V10) sur la branche `22.1.1-backend-interests`. UNE PR vers `main`.

## Vue d'ensemble

Deux features shippées ensemble :

1. **Système d'intérêts 4-états unifié + favoris + backfill (Story 22.1)** — Backend (migration + endpoints + services), mobile screens, sync mobile one-shot.
2. **Flux Continu V1.8 + finitions V2.0 (Story 21.1)** — Home Flux Continu, hero Explorer, sticky bascule tab bar ↔ filter bar, fold différé entre sessions.

Refonte hi-fi du panneau « Couverture médiatique » sur l'écran article (front) :
- Bandeau `cm-panel-inline` (hairlines, spectrum 5-segs, "N médias", caret)
- Carte dépliée : bloc référence (wash verbe-pivot gris), 8 lignes variantes avec **diff lexical animé en cascade** (Mode 3 fidèle : shared en tertiary, key en wash bias)
- CTA Analyse Facteur en card dashed déprioritée
- Nouveau badge polarisation (3 niveaux) dans la meta-row des `FeedCard` des articles topicalisés du digest L'Essentiel

L'animation cascade des surlignages se déclenche **1×** à l'ouverture de la carte dépliée. Feeling visé : « Facteur analyse en temps réel les divergences entre sources ».

## PR associée

À créer juste après ce handoff (`gh pr create --base main`).

PO Laurin a signalé : « En scroll-down continu, des "sauts" apparaissent toujours en arrivant à la fin d'une section. » Quatre approches in-session ont échoué (trigger naïf, `userScrollDirection`, `correctBy` post-frame, `SliverList` natif) — toutes laissaient un décalage visible parce qu'un resize de sliver dans un `CustomScrollView` impose mécaniquement de réaligner le contenu en dessous.

**Pivot UX** : abandonner le fold pendant la session active. Le scroll-past est désormais **détecté mais persisté en silence** — la section reste expanded à l'écran jusqu'à ce que le user quitte/relance l'app. Au prochain cold launch, les sections "consommées" lors de la session précédente apparaissent déjà en `FoldedSectionCard` (la transition fold→expanded n'est plus visible parce qu'elle est portée par l'initial layout, pas par un changement en cours de session).

**Critères d'acceptation V2.0** :
1. Pendant une session active, **aucune section ne se replie automatiquement au scroll** — le user voit toujours le hero plein-format, même après l'avoir scrollé.
2. Aucun saut visuel, aucun stutter pendant le scroll continu (puisqu'il n'y a plus aucun resize).
3. Cold-launch d'une nouvelle session (kill + relaunch) → les sections scrollées past lors de la session précédente apparaissent déjà en `FoldedSectionCard` au top du flux.
4. Tap sur folded card → ré-expansion locale (state-only, non persistée, comme avant).
5. La closing card « Vous êtes à jour » suit la même logique.

## Feature développée (21.1)

Six ajustements de la home Flux Continu V1.8 : auto-fold des sections scrollées en cartes-titre compactes (persisté par jour), hero « Explorer » qui sépare la zone éditoriale du feed continu, bascule sticky tab bar ↔ filter bar au passage du hero Explorer, Bonnes Nouvelles en dernière position (non-serein) ou en tête (serein), refinements visuels des heros (texte plus large, illustration plus discrète).

## Écrans impactés (21.1)

| Écran | Route | Modifié / Nouveau |
|---|---|---|
| Détail article (bottom layout) | `/feed/:contentId` | Modifié — `PerspectivesInlineSection` refondu |
| Détail article (top layout) | `/digest/:contentId` | Modifié — idem, 2 call-sites |
| Digest L'Essentiel | `/digest` | Modifié — `FeedCard` accepte `divergenceLevel` ; câblé via `topic_section.dart` |

### Scénario 2 : Tap sur folded card = ré-expansion locale
**Parcours** :
1. Après scénario 1, scroll vers le haut pour revoir les folded cards
2. Tap sur une carte foldée (ex. Essentiel)

**Résultat attendu** :
- La carte se ré-expanse en hero complet (banner + cards + Plus de…)
- Pas de persistance : recharger la page (F5) la laisse foldée à nouveau

### Scénario 1 — Happy path : animation cascade Mode 3

**Parcours** :
1. Ouvrir un article du digest L'Essentiel couvert par ≥5 médias avec topic polarisé (idéalement actu politique récente)
2. Vérifier le bandeau replié sous le titre : `Couverture médiatique` + spectrum 5 segments distincts + `N médias` + caret
3. Tap sur le bandeau → carte se déplie

**Résultats attendus** :
- Bloc référence visible (border-left ocre, titre `Fraunces` 16.5/600). Si verbe-pivot retourné par le back, **wash gris apparaît** sur le verbe ~80 ms après l'ouverture, fade-in 300 ms.
- 8 lignes variantes apparaissent (border-left 4 px couleur bias). Sur chaque ligne, les **tokens partagés deviennent gris** et les **tokens divergents reçoivent un wash de la couleur du bias** dans une cascade séquentielle ordonnée par position (gauche → droite), 25 ms entre tokens, 220 ms par token (`easeOutCubic`).
- Toutes les lignes animent **en parallèle** — feeling « scan simultané ».
- CTA `Analyse Facteur` dashed border en bas, déprioritée.

### Scénario 2 — Tap variant ouvre navigateur externe

**Parcours** :
1. Sur la carte dépliée, tap n'importe quelle ligne variante.

**Résultat attendu** : le navigateur in-app/externe s'ouvre sur l'URL du variant. Pas de crash. Le panel reste ouvert au retour.

### Scénario 3 — Tap CTA Analyse Facteur

**Parcours** :
1. Tap sur "Lancer →" dans la card CTA dashed.

**Résultat attendu** : le CTA disparaît, remplacé par `PerspectivesAnalysisZone` (skeleton 3 lignes → résultat Markdown). UI inchangée vs. avant la refonte (mêmes états loading/done/error).

### Scénario 4 — Mode 2 dégradé (back pas encore déployé)

**Parcours** :
1. Si le back ne renvoie pas `shared_tokens` (ancien déploiement), ouvrir un article avec perspectives.

**Résultat attendu** : la carte se déplie. Les variants rendent leur titre avec les `highlight_spans` en wash bias, et le reste en `text_tertiary` (mode 2 fallback automatique, pas de crash). Cascade animée toujours active.

### Scénario 5 — Replier → re-ouvrir relance la cascade

**Parcours** :
1. Carte dépliée avec animation jouée.
2. Tap bandeau → carte se replie.
3. Tap bandeau → carte se déplie de nouveau.

**Résultat attendu** : nouvelle cascade jouée intégralement (animation 1× par expand). Pas de "snap" instantané.

### Scénario 6 — Article hors digest (live path) sans cluster

**Parcours** :
1. Ouvrir un article live (non-digest) qui n'a pas de cluster ou pour lequel le back ne peut pas calculer les annotations.

**Résultats attendus** :
- `highlightSpans` et `sharedTokens` vides sur les variants → DiffTitle rend le titre plein en `text_primary` (pas de wash).
- `referencePivot` null → bloc référence rendu sans wash.
- Aucune erreur console.

> **Regression Bug Couverture (2026-05-18)** : avant fix, ce scénario rendait *tous* les titres en `text_tertiary` (gris pâle uniforme) au lieu de `text_primary`. Couvert par `diff_title_test.dart:122` qui asserte maintenant explicitement la couleur du chunk plain. Cf. `docs/bugs/bug-couverture-mediatique-surlignages.md`.

### Scénario 8 — Bandeau cm-panel-inline en viewport étroit (390px)

**Parcours** :
1. Ouvrir un article avec perspectives en viewport iPhone (390×844).
2. Vérifier le bandeau replié : titre + spectrum + count + caret tous visibles sans clipping ni warning console `RenderFlex overflowed`.

**Résultat attendu** :
- Aucun overflow Flutter dans la console.
- `CoverageSpectrumBar` 5-segs visible entre le titre et le count.
- Si le titre « Couverture médiatique » est trop long (ne devrait pas arriver, mais théoriquement), il s'ellipsis au lieu de pousser le spectrum hors écran.

> **Regression Bug Couverture (2026-05-18)** : avant fix, le `Row` du bandeau débordait de 131 px sur 390 px, repoussant le spectrum hors écran. Couvert par `perspectives_inline_overflow_test.dart` qui pump le bandeau en viewport contraint et vérifie l'absence d'exception. Cf. `docs/bugs/bug-couverture-mediatique-surlignages.md`.

### Scénario 7 — Badge polarisation digest

**Parcours** :
1. Aller sur le digest L'Essentiel du jour.
2. Vérifier la meta-row de chaque article topicalisé.

**Résultats attendus** :
- Sujets `divergenceLevel='high'` → badge `POLARISÉ` (glyphe 2 paires brique+marine, label noir bold)
- Sujets `divergenceLevel='medium'` → badge `AVIS VARIÉS` (5 dots étalés gris, label tertiary)
- Sujets `divergenceLevel='low'` → badge `CONSENSUS` (3 dots groupés gris, label tertiary)
- Articles Pépite, Coup de cœur, actu_decalee → **aucun badge** (silence, conforme au hand-off)

### Scénario 9 — Refinements post-merge (2026-05-18)

**R1 — Un seul CTA Analyse Facteur**

**Parcours** :
1. Ouvrir un article in-app du digest L'Essentiel.
2. Déplier `Couverture médiatique`.

**Résultat attendu** : le bouton flottant « Lancer l'analyse Facteur » en bas-droit a disparu. Seul reste le **CTA dashed** en bas du bloc déplié, qui déclenche correctement l'analyse.

**R2 — Bandeau compact avec compteur dans le titre**

**Parcours** :
1. Sur le bandeau replié, observer la composition du Row.

**Résultat attendu** : titre `Couverture médiatique (N)` à gauche, spectrum 5-segs, caret. **Le `Text "N médias"` séparé n'existe plus**. Aucun overflow en 390 px (couvert par `perspectives_inline_overflow_test.dart` mis à jour).

**R3 — L'article courant n'apparaît jamais comme variant**

**Parcours** :
1. Ouvrir un article du digest dont la couverture inclut au moins 3-4 variants.
2. Déplier la section, scroller la liste des variants.

**Résultat attendu** : aucune card de variant ne pointe vers l'URL de l'article actuellement lu (pas de doublon avec le bloc `CET ARTICLE`). Le compteur `(N)` reflète la liste filtrée (1 entrée de moins par rapport à avant le fix). Le spectrum reste cohérent avec la liste affichée.

**R4 — Label CET ARTICLE + divider sous bloc + dividers entre variants renforcés**

**Parcours** :
1. Déplier `Couverture médiatique` sur un article avec cluster.

**Résultat attendu** :
- Le label en haut du bloc référence affiche `CET ARTICLE` (et non plus `VOTRE ARTICLE`).
- Un **divider gris** (alpha 0.18, marges latérales 16 px) sépare clairement le bloc référence du premier variant.
- Les dividers entre variants sont **légèrement plus visibles** qu'avant (alpha 0.08 vs. 0.05). Pas d'effet agressif, juste un cran de plus.

## Critères d'acceptation (21.1)

- [ ] Bandeau hairlines + spectrum 5-segs distincts + count + caret rendus correctement (replié)
- [ ] Bloc référence + 8 lignes variantes + CTA dashed (déplié)
- [ ] Animation cascade des surlignages déclenchée 1× à l'expand, fade-in fluide
- [ ] Tap variant → navigateur externe, pas de crash
- [ ] Mode 2 dégradé fonctionne si back n'expose pas `shared_tokens`
- [ ] Badge polarisation sur articles topicalisés du digest seulement
- [ ] Zéro régression sur la suite Flutter (`flutter test` 619/619 ou plus selon parent)

## Zones de risque (21.1)

1. **Timing animation** : la cascade utilise un `Future.delayed(80 ms)` avant de démarrer. Si la frame de l'expand prend > 80 ms (jank initial), l'animation peut paraître saccadée. Tester sur device réel iOS et Android.
2. **Titres très longs** : `DiffTitle` est en `maxLines: 2 ellipsis`. Un titre avec beaucoup de spans après la troncature pourrait avoir des spans visuellement absents (le wash est attaché à un `WidgetSpan` qui peut wrapper différemment). Vérifier sur titres > 100 caractères.
3. **GoogleFonts.fraunces / GoogleFonts.courierPrime** : chargement réseau au premier render. Vérifier qu'il n'y a pas de flash de fallback (fontStyle.italic Times New Roman) — sur Android cold start spécifiquement.
4. **Spectrum bar** : avec une distribution totalement vide `{}` (back KO), tous les segments rendus avec floor=1. C'est lu visuellement comme « répartition uniforme » — confirmer que ce fallback est OK ou s'il faut masquer le spectrum (actuellement pas masqué).
5. **Polarisé bicolore (brique+marine)** : vérifier le contraste WCAG du label noir bold sur fond carte ; la couleur des dots utilise `biasLeft`/`biasRight` qui peuvent être proches en thème sombre.

## Dépendances (21.1)

- **Back** : `GET /contents/{id}/perspectives` doit retourner `highlight_spans` (PR #616, déjà mergée) + `shared_tokens` + `reference_pivot` (PR #618, en review). Tant que PR #618 n'est pas mergée + déployée Railway, le front rend en Mode 2 dégradé (pas de Mode 3 fidèle).
- **GoogleFonts** : `fraunces` et `courierPrime` (déjà utilisés ailleurs dans l'app, pas de nouvel asset à déclarer).
- **Aucun changement de DB / migration**.
