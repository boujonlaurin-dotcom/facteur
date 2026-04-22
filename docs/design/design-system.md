# 🎨 Facteur — Design System

> Synthèse officielle de la Direction Artistique de l'App Facteur.
> À intégrer dans la page Notion « Identité de marque ».
> Source de vérité : `apps/mobile/lib/config/theme.dart` + `docs/front-end-spec.md`.

---

## 1. Identité de marque

- **Nom** : Facteur *(The Postman)*
- **Concept** : digest quotidien, « moment de fermeture » — clarté apaisante vs. chaos des réseaux
- **Persona** : Crédible (Le Monde) × Accessible (Notion) × Chaleureux (personnel)
- **Palette émotionnelle** : Terracotta (autorité), Crème / Parchemin (éditorial), Charbon doux (lisibilité)
- **Tagline implicite** : « Clarté apaisante »

---

## 2. Couleurs

### ☀️ Light Mode — thème **par défaut**

Ton éditorial, chaleureux, proche du papier. C'est le mode de référence pour toute création.

| Rôle | Nom | Hex |
|---|---|---|
| **Background primary** | Parchemin | `#F2E8D5` |
| **Primary / Accent** | **Ocre** | **`#D35400`** |
| Text primary | Charbon doux | `#2C2A29` |
| Text secondary | Gris sépia (≈ 70 %) | `#6B6866` |
| Text tertiary | Gris doux (≈ 50 %) | `#9C9894` |

> Les tokens Success / Warning / Error / Info reprennent les mêmes hex qu'en Dark Mode (voir ci-dessous) — ils sont pensés pour fonctionner sur les deux fonds.

### 🌑 Dark Mode — variante alternative

| Rôle | Nom | Hex |
|---|---|---|
| Background primary | Noir Charbon | `#101010` |
| Background secondary | Noir Élevé | `#161616` |
| Surface | Gris Ardoise | `#1C1C1C` |
| Surface elevated | Gris Foncé | `#242424` |
| Surface paper (inputs) | Gris Clair | `#2A2A2A` |
| **Primary / Accent** | **Rouge Sceau** | **`#C0392B`** |
| Primary muted | Rouge Sombre | `#5A2A25` |
| Secondary | Bleu Acier | `#5D6D7E` |
| Text primary | Blanc Craie | `#EAEAEA` |
| Text secondary | Gris Clair | `#A6A6A6` |
| Text tertiary | Gris Moyen | `#606060` |
| Border | Gris Sombre | `#333333` |

### 🚦 Couleurs sémantiques (communes aux deux modes)

| Rôle | Nom | Hex |
|---|---|---|
| Success | Vert Émeraude | `#2ECC71` |
| Warning | Orange Ambre | `#F39C12` |
| Error | Rouge Corail | `#E74C3C` |
| Info | Bleu Info | `#3498DB` |

### 🗳️ Spectre politique (Bias palette)

Utilisé par la `BiasSpectrumBar` et les badges de source.

| Polarité | Hex |
|---|---|
| Gauche | `#E53935` |
| Centre-gauche | `#FFCDD2` |
| Centre | `#757575` |
| Centre-droit | `#BBDEFB` |
| Droite | `#1E88E5` |
| Inconnu | `#616161` |

---

## 3. Typographie

### Familles (Google Fonts)

| Usage | Font | Poids |
|---|---|---|
| **Titres / Logo** | **Fraunces** (serif) | 400 · 500 · 600 · 700 |
| **Body / UI** | **DM Sans** (sans) | 400 · 500 · 700 |
| **Tampons / Spécial** | **Courier Prime** (mono) | 400 · 700 |

### Échelle typographique

| Style | Font | Size | Weight | Line-height |
|---|---|---|---|---|
| Display Large | DM Sans | 28 | 700 | 1.25 |
| Display Medium | DM Sans | 22 | 600 | 1.30 |
| Display Small / H3 | DM Sans | 18 | 600 | 1.30 |
| Body Large | DM Sans | 17 | 400 | 1.50 |
| Body Medium | DM Sans | 15 | 400 | 1.50 |
| Body Small | DM Sans | 13 | 400 | 1.40 |
| Label Large | DM Sans | 14 | 500 | 1.30 |
| Label Medium | DM Sans | 12 | 500 | 1.30 |
| Label Small | DM Sans | 11 | 500 | 1.20 |
| Stamp | Courier Prime | 11 | 700 | 1.20 · letter-spacing 0.5 |

> Les titres éditoriaux de couverture / hero peuvent basculer en **Fraunces** 700 pour renforcer l'ancrage « postal / éditorial ».

---

## 4. Espacement · Rayons · Élévation

### Spacing (base 4 px)

`4 · 8 · 12 · 16 · 24 · 32`

### Border Radius

| Élément | Rayon |
|---|---|
| Buttons, Inputs, Thumbnails | 8 px |
| Cards | 12 px |
| Chips (pill) | 20 px |

### Shadow & élévation

- **Ombre carte par défaut** : `rgba(0,0,0,0.1) · blur 4 · offset (0, 2)`
- **Élévation Material 3** : **0** (flat design assumé)

---

## 5. Composants clés

### Button
- 3 variantes : **Primary** (solide ocre / rouge sceau), **Secondary** (outlined), **Text**
- Padding `16h × 12v`, radius 8
- Pressed : scale 0.98 + opacity 0.8 (150 ms)
- Haptique : heavy impact
- États : default · pressed · disabled (opacity 0.4) · loading (spinner 2 px)

### Card (`FacteurCard`)
- Surface sobre (parchemin crémé / ardoise), radius 12, padding 16, sans bordure
- Tap : scale 1.0 → 0.98 (down 150 ms, up 250 ms), haptique medium
- Ombre portée très légère

### Input
- Fill surface elevated, radius 8, padding `16h × 12v`
- Focus : bordure 1.5 px primary
- Placeholder : text tertiary

### Digest Card
- Thumbnail 16:9, radius 8, shimmer skeleton en chargement
- Titre 3 lignes max, 20 px bold
- Badges : « Lu » / « Vu » / « Masqué » (opacity 0.6 si consommé)
- Overlay vidéo : cercle 52 px blanc (opacity 0.85) + play
- Liseré vidéo : `#FF0000`, 3 px en haut

### Digest Progress Bar
- Barre continue 6 px (**pas** de dots)
- Couleur : primary (0-60 %) → warning (60 %+) → success (100 %)
- Animation pulse sur incrément (scale 1.03, 300 ms)
- Message contextuel : « C'est parti ! », « Bon début », « Presque fini »…

### Bias Spectrum Bar
- Barre 6 px, 3 segments proportionnels (Gauche / Centre / Droite)
- Labels optionnels 8 px en dessous

### FacteurStamp (tampon postal)
- Courier Prime 11 / 700 uppercase, border 1.5 px
- Rotation pseudo-aléatoire 2–4°
- Usage : badges « NEW », marques archivées, tampons rétro

### Priority Slider
- 3 crans, blocs 28 × 12, gap 3 px
- Remplissage proportionnel à l'usage appris
- Bouton reset si drift > 0.15 vs. réglage

### Bottom Tab Bar
- 4 onglets : Feed · Saved · Sources · Profile
- Fond adapté au thème, sélectionné = primary, inactif = text tertiary
- Icônes Phosphor 24 px, labels toujours visibles

### FacteurLogo
- Mot « Facteur » en Fraunces 700 + icône thématique (light / dark auto)
- Icône dimensionnée à 1.7× la taille de base

---

## 6. Iconographie

**Librairie** : **Phosphor Icons v2**
- Tailles : **24 px** (navigation), **20 px** (contenu), **16 px** (petit)
- Variante **Regular** (outline) par défaut, **Fill** si actif / sélectionné

| Contexte | Icônes |
|---|---|
| Feed · Saved · Sources · Profile | `house` · `bookmark-simple` · `books` · `gear` |
| Article · Podcast · Vidéo | `article` · `headphones` · `video` |
| Like · Save · Share · More | `heart` · `bookmark` · `share-network` · `dots-three-vertical` |
| Navigation · Close · Verified | `arrow-left/right` · `x` · `checks` |
| Streak | `fire` (fill) |

### Assets logo

| Fichier | Usage |
|---|---|
| `assets/icons/logo facteur fond_clair.png` | Fond clair (light mode, défaut) |
| `assets/icons/logo facteur fond_sombre.png` | Fond sombre (dark mode) |
| `assets/icons/facteur_logo.png` | Fallback |
| `assets/icons/logo_facteur_app_icon.png` | App icon iOS / Android |

---

## 7. Motion

| Token | Durée | Easing | Usage |
|---|---|---|---|
| `fast` | 150 ms | easeInOut | Press feedback |
| `medium` | 250 ms | easeInOut | Release, modals |
| `slow` | 400 ms | easeOutCubic | Progress bar fill |
| Pulse | 300 ms | default | Incrément progression (scale 1.03) |
| Shimmer | 1500 ms | linear | Skeleton loop |

**Haptique** : Heavy (boutons CTA) · Medium (cards, long-press)
**Accessibilité** : respecte `prefers-reduced-motion` (toutes les animations peuvent être désactivées).

---

## 8. Accessibilité

- Contraste **WCAG AA** : 4.5:1 (texte) · 3:1 (texte large)
- Touch target minimum : **44 × 44 pt**
- Focus ring : 2 px primary visible sur tout élément interactif
- Haptique systématique sur éléments interactifs
- Labels sémantiques obligatoires (VoiceOver / TalkBack)

---

## 9. Layout responsive

- **Plateforme cible** : iOS (iPhone SE 375 → Pro Max 430)
- Marges latérales : **16 px**
- Safe areas respectées (notch + home indicator)
- Images : ratio 16:9 fluide
- Bottom tab bar : fixe, 4 tabs équi-répartis, au-dessus du home indicator

---

## 10. Patterns de design

### Gamification
- **Streak** : fire icon + compteur
- **Badges** : stamps rotés (tampons postaux Courier Prime)
- **Progression** : barre continue (pas de dots) + message contextuel
- **Célébration** : pulse + haptique + confetti aux jalons

### Langage éditorial
- Badges sémantiques : « Coup de cœur », « Pépite », « Avis divergents »
- Spectre politique : barre 3 segments colorés

### Boucle de feedback interactive
Visuel (opacity + scale) + Haptique (vibration) + Temporel (150–250 ms)

---

## 11. Dépendances techniques

| Librairie | Version | Usage |
|---|---|---|
| `google_fonts` | ^7.0.0 | Fraunces · DM Sans · Courier Prime |
| `phosphor_flutter` | ^2.1.0 | Iconographie |
| `flutter_animate` | ^4.5.2 | Animations |
| `shimmer` | ^3.0.0 | Skeleton loading |
| `lottie` | ^3.1.2 | Animations complexes (loader) |
| `confetti` | ^0.7.0 | Célébrations (streak) |
| `haptic_feedback` | ^0.6.4+3 | Retours haptiques |
| `cached_network_image` | ^3.3.1 | Chargement images |

---

## 12. Fichiers de référence

| Source | Chemin |
|---|---|
| Thème global | `apps/mobile/lib/config/theme.dart` |
| Composants design | `apps/mobile/lib/widgets/design/` |
| Widgets digest | `apps/mobile/lib/features/digest/widgets/` |
| Spec front-end | `docs/front-end-spec.md` |
| PRD | `docs/prd.md` |

---

## TL;DR (pour un outil de design)

Thème **light-first éditorial** (parchemin `#F2E8D5` + ocre `#D35400` + charbon doux `#2C2A29`), variante dark alternative (charbon `#101010` + rouge sceau `#C0392B`). Typographie **Fraunces** (serif, titres) + **DM Sans** (body / UI) + **Courier Prime** (tampons). Composants animés en **150 / 250 / 400 ms** avec haptique, iconographie **Phosphor**, spacing base **4 px**, radius **8 / 12 / 20**, accessibilité **WCAG AA**. Ton *postal* (tampons, badges rotés) × *éditorial* (parchemin, bias bar).
