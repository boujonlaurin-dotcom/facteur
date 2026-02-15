# Handoff — Polish UX/UI du Digest Mode Selector

> **Date** : 15/02/2026
> **De** : Claude (Dev Agent sessions 1 & 2)
> **Vers** : Prochain agent UX/UI
> **Story** : [[../stories/evolutions/11.1.digest-mode-selector-ux.story.md]]
> **Branche** : `claude/digest-feed-tab-selector-4hQuu`

---

## Contexte

**Facteur** est une app mobile Flutter de consommation intentionnelle d'information. L'utilisateur reçoit un **digest quotidien de 5 articles** curatés. Il peut choisir parmi 3 **modes de digest** qui influencent la sélection algorithmique :

- **Pour vous** (☀️) — sélection personnalisée classique
- **Serein** (🌿) — sans politique ni infos anxiogènes
- **Changer de bord** (🧭) — découvrir l'autre bord politique

Le **mode selector** est le composant clé de cette feature. C'est un vrai levier d'engagement : chaque changement de mode **régénère entièrement le digest** côté backend (DELETE + re-scoring + re-sélection). L'UI doit refléter cette importance.

---

## État actuel du code

### Fichiers à modifier

| Fichier | Rôle | Lignes |
|---------|------|--------|
| `apps/mobile/lib/features/digest/models/digest_mode.dart` | Enum des 3 modes avec couleurs, gradients, icônes, glow | ~140 |
| `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` | Container principal du digest (header + articles), intègre le segmented control | ~400 |
| `apps/mobile/lib/features/digest/widgets/digest_mode_tab_selector.dart` | `DigestModeSegmentedControl` — segmented control compact iOS-style | ~126 |
| `apps/mobile/lib/features/digest/screens/digest_screen.dart` | Écran principal, background animé, overlay régénération | ~620 |

### Fichiers à lire (contexte, ne pas modifier)

| Fichier | Rôle |
|---------|------|
| `apps/mobile/lib/features/digest/providers/digest_mode_provider.dart` | Flow `setMode()` → pref + API regen → UI sync |
| `apps/mobile/lib/features/digest/providers/digest_provider.dart` | Cache digest, `updateFromResponse()` |
| `apps/mobile/lib/config/theme.dart` | Design tokens (couleurs, espacements, typographie) |
| `apps/mobile/lib/features/digest/models/digest_models.dart` | DigestItem, DigestResponse |

### Backend (fonctionnel, ne pas toucher)

Le backend gère déjà la régénération :
- `POST /api/digest/generate?mode=serein&force=true` → supprime le digest existant, re-sélectionne les articles avec les filtres du mode, et renvoie le nouveau digest
- `packages/api/app/services/digest_selector.py` applique des filtres mode-spécifiques (exclusion topics anxiogènes pour "serein", +80pts bias opposé pour "perspective")

---

## Feedback utilisateur (ce qui ne va pas)

### 1. Le composant selector n'est pas assez impactant

**Actuel** : `DigestModeSegmentedControl` compact (132×36px) avec 3 icônes dans un pill. L'indicateur slide de segment en segment.

**Problème** : Le composant est trop discret — il ressemble à un petit toggle utilitaire, pas à un vrai "switch de mode" premium. Il ne communique pas l'importance du choix (qui régénère tout le digest). L'utilisateur ne comprend pas intuitivement qu'il peut changer le "mood" de son digest.

**Attendu** : Un composant qui donne une sensation de **switch de mode premium** avec du poids visuel. Quelque chose qui invite à l'interaction et communique clairement "c'est ici que tu choisis l'ambiance de ton digest". Inspiration : les segmented controls iOS mais avec une touche éditoriale premium. Des icônes + labels courts pourraient aider (pas que des icônes seules). Animation fluide du slide entre modes.

### 2. Les couleurs du container ne sont pas assez marquées

**Actuel** : Gradients dark mode très subtils (ex: `#261C0E → #1A1408` pour "Pour vous"). Le fond d'écran change à peine (`#1A150C` vs `#0C1A10`).

**Problème** : Le changement de mood est presque imperceptible. On ne "sent" pas la différence entre les modes.

**Attendu** :
- Le changement de **mood doit être immédiatement perceptible** quand on switch
- Le **gradient de la carte** doit avoir plus de contraste et de profondeur
- Le **fond de l'écran** doit avoir une teinte suffisamment marquée
- Effet **premium** : transparence progressive du background de la carte vers le fond de l'écran (la carte "fond" dans le fond)
- Penser à un subtil **vignettage** ou **glow** sur les bords de la carte dans la couleur du mode

**Pistes de palettes** :
- **Pour vous** : tons chauds ambrés/dorés profonds. Think "coucher de soleil éditorial"
- **Serein** : tons verts profonds, forêt. Think "nature apaisante"
- **Changer de bord** : tons bleu nuit/indigo. Think "horizon, ouverture"

### 3. Les icônes ne conviennent pas

**Actuel** : `sunDim` (Pour vous), `flowerLotus` (Serein), `detective` (Perspective)

**Problème** : Les icônes ne communiquent pas clairement les modes. `detective` en particulier est ambigu pour "Changer de bord".

**Attendu** : Choisir des icônes Phosphor qui communiquent immédiatement le concept de chaque mode. Libre choix — explorer le catalogue Phosphor Icons.

### 4. Le sous-texte est difficilement lisible

**Actuel** : 13px, `modeColor.withValues(alpha: 0.85)`, visible 4s après changement puis disparaît.

**Problème** : Trop petit et/ou contraste insuffisant sur certaines couleurs de mode.

**Attendu** : Lisible naturellement, sans effort. Tester sur chaque couleur de fond. 13-14px minimum, opacité 0.9+.

### 5. Feedback visuel lors du changement de mode

**Actuel** : `AnimatedOpacity(opacity: 0.15)` + `_RegenerationOverlay` (pulsing glow + spinner + texte).

**Ce qui fonctionne** : L'overlay est OK conceptuellement.

**Ce qui manque** : Le changement visuel global (couleurs, gradient, fond) n'est pas assez spectaculaire pour donner l'impression que "tout se recompose". La transition devrait être un moment UX marquant, pas juste un chargement.

### 6. Titre : garder "L'Essentiel du jour"

Déjà fait (fontSize 20, w800). Pas de changement nécessaire.

---

## Design system (rappel)

| Token | Valeur |
|-------|--------|
| Background dark | `#101010` |
| Surface dark | `#1C1C1C` |
| Primary (Rouge Sceau) | `#C0392B` |
| Text primary dark | `#EAEAEA` |
| Text secondary dark | `#A6A6A6` |
| Font titres | Fraunces / DM Sans bold |
| Font body | DM Sans |
| Icônes | Phosphor Icons |
| Radius card | 24px |
| Mode dark uniquement | Oui (l'app est dark-only en prod) |

## Contraintes techniques

- **Flutter SDK** >=3.0.0 <4.0.0
- **State** : Riverpod 2.5 (le mode provider est déjà câblé, pas besoin de le refaire)
- **Animations** : Utiliser les animations implicites Flutter (AnimatedContainer, AnimatedSwitcher, TweenAnimationBuilder) — pas de packages externes
- **Pas de code gen** : Les modifications sont purement UI (pas de Freezed/build_runner)
- **Ne pas toucher au backend** (`packages/api/`)
- `isRegenerating` est déjà disponible dans le state (`modeState.isRegenerating`)

---

## Critères de succès

1. Le mode selector donne une sensation **premium et impactante** — pas un petit toggle utilitaire
2. Changer de mode produit un **changement de mood visuel immédiat et clair** (couleurs, gradient, background)
3. Les icônes/visuels des modes sont **cohérents et communiquent clairement** leur concept
4. Le subtitle est **lisible sans effort** sur chaque couleur de fond
5. Pendant la régénération, un **feedback visuel clair** indique que les articles changent
6. L'ensemble donne une sensation **premium, soignée, intentionnelle** — pas "generated by AI"

---

*Handoff créé le 15/02/2026 par Dev Agent (Claude)*
