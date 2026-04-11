# QA Handoff — Digest UI/UX Adjustments (Glass effect + Special blocks redesign)

> Ce fichier est rempli par l'agent dev à la fin du développement.
> Il sert d'input à la commande /validate-feature de l'agent QA.

## Feature développée

Ajustements UI/UX du digest editorial : (1) effet liquidglass sur la carte "L'Essentiel du jour", (2) teinte renforcée sur les cartes topics, (3) header sticky sur carte ouverte, (4) citation Serein repositionnée en premier + redesign card, (5) Pépite/CoupDeCoeur/ActuDécalée dans des containers styled cohérents.

## PR associée

Branche : `claude/digest-card-glass-effect-vzYe2`

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Digest (mode standard) | `/digest` | Modifié |
| Digest (mode Serein) | `/digest` (toggle Serein) | Modifié |
| Digest editorial ouvert | `/digest` (card expanded) | Modifié |

## Scénarios de test

### Scénario 1 : Liquid glass sur la carte principale (mode clair)

**Parcours** :
1. Ouvrir l'écran `/digest`
2. Thème clair activé
3. Faire défiler lentement le scroll vers le bas

**Résultat attendu** :
- La carte "L'Essentiel du jour" a un effet de flou derrière elle (backdrop blur)
- Le fond crème de l'app est légèrement visible à travers le dégradé de la carte
- Un fin bord blanc semi-transparent encadre la carte (effet glass edge)
- Une ombre plus prononcée que l'ancienne version

---

### Scénario 2 : Liquid glass sur la carte principale (mode sombre)

**Parcours** :
1. Ouvrir l'écran `/digest`
2. Activer le thème sombre
3. Observer la carte

**Résultat attendu** :
- Même effet de flou, mais avec un fond sombre translucide (gradient 72-78% alpha)
- Bord subtil blanc (14% alpha)
- Shadow plus prononcée sur fond sombre

---

### Scénario 3 : Teinte plus marquée sur les cartes topic

**Parcours** :
1. Ouvrir l'écran `/digest` en mode editorial
2. Observer les cartes de topics (avant l'ouverture)

**Résultat attendu** :
- En mode sombre : fond légèrement plus prononcé (white 11% vs 6% avant)
- En mode clair : teinte légèrement plus foncée (black 7% vs 3% avant)
- La distinction visuelle entre la carte mère et les cartes topic est plus nette

---

### Scénario 4 : Header sticky sur carte ouverte

**Parcours** :
1. Ouvrir l'écran `/digest` en mode editorial
2. Appuyer sur une carte topic pour l'ouvrir (expand)
3. Scroller vers le bas jusqu'à ce que le contenu de la carte dépasse le haut de l'écran

**Résultat attendu** :
- Le header de la carte (titre du topic + badge) se "colle" en haut de l'écran visible de la carte
- Le header naturel (dans le contenu) disparaît par fade quand le sticky prend le relais
- En continuant à scroller, quand le bas de la carte dépasse le sticky, le sticky disparaît
- Pas de doublon header visible à aucun moment

**Edge case** : La carte ne doit PAS avoir de sticky quand elle n'est pas ouverte (compacte)

---

### Scénario 5 : Citation Serein en première position

**Parcours** :
1. Ouvrir `/digest`
2. Activer le mode Serein (toggle en haut à droite)
3. Observer le contenu de la carte principale

**Résultat attendu** :
- La citation (QuoteBlock) apparaît **avant** le premier topic (Bonne Nouvelle)
- La citation est présentée dans une card élégante avec :
  - Un grand guillemet décoratif `«` en haut
  - Le texte en italique centré, hauteur de ligne 1.55
  - Une fine ligne horizontale accent sous le texte
  - L'auteur en semi-gras en dessous
  - Fond teinté subtil (primary 5% en clair, white 6% en sombre)

**Edge case** : Si le digest n'a pas de citation (quote null), rien ne s'affiche en première position

---

### Scénario 6 : Pépite du jour styled

**Parcours** :
1. Ouvrir `/digest` (un digest qui a une Pépite du jour)
2. Scroller jusqu'au bloc "Pépite du jour"

**Résultat attendu** :
- Le bloc est dans un container encadré (border radius 16, tint, ombre)
- Le badge "🌿 Pépite du jour" et le mini-éditorial apparaissent en header interne (padding 12px)
- La FeedCard est à l'intérieur du container (padding 10px)
- Visuellement cohérent avec les cartes topics

---

### Scénario 7 : Coup de cœur styled

**Parcours** :
1. Ouvrir `/digest` (digest avec Coup de cœur)
2. Scroller jusqu'au bloc "Coup de cœur"

**Résultat attendu** :
- Même container styled que la Pépite
- Le texte d'intro ("L'article le plus gardé hier...") dans le header interne
- Cohérence visuelle avec le reste du flow

---

### Scénario 8 : Toggle Serein ↔ Standard (animation)

**Parcours** :
1. Activer mode Serein → observer la citation en premier
2. Désactiver mode Serein → la citation disparaît, layout standard
3. Réactiver → citation réapparaît en premier

**Résultat attendu** :
- AnimatedSwitcher cross-fade de 300ms entre les deux layouts
- Pas de flash / layout jump visible

---

### Scénario 9 : Sticky header — transition vers le topic suivant

**Parcours** :
1. Ouvrir le premier topic (expand)
2. Scroller jusqu'à voir la fin du premier topic et le début du deuxième
3. Ouvrir également le deuxième topic

**Résultat attendu** :
- Quand le premier topic scroll hors de vue, son sticky header disparaît proprement
- Le sticky du deuxième topic fonctionne indépendamment
- Jamais deux sticky headers simultanément visibles

---

## Critères d'acceptation

- [ ] BackdropFilter blur visible sur la carte mère (effet glass)
- [ ] Gradient semi-transparent (app background visible à travers)
- [ ] Teinte cards topics plus prononcée en dark et light mode
- [ ] Header sticky activé uniquement sur card ouverte (expanded)
- [ ] Header sticky release quand la card scroll hors de vue
- [ ] Opacity fade du header naturel quand sticky actif
- [ ] QuoteBlock affiché EN PREMIER en mode Serein (avant topics)
- [ ] QuoteBlock design : guillemet décoratif + ligne accent + auteur stylé
- [ ] QuoteBlock invisible si quote.text vide
- [ ] PépiteBlock dans container styled (cohérent avec topics)
- [ ] CoupDeCoeurBlock dans container styled (cohérent avec topics)
- [ ] ActuDécalée dans container styled (cohérent avec topics)
- [ ] Aucune régression en mode standard (non-serein)
- [ ] flutter analyze : 0 errors, 0 warnings sur les fichiers modifiés

## Zones de risque

- **BackdropFilter** : peut être ignoré silencieusement sur certains devices Android anciens (API < 23) — l'app doit rester lisible sans le flou
- **Sticky header** : la translation est calculée à partir de `localToGlobal` — à vérifier que le pin line est correct avec et sans notch/safe area
- **Quote first position** : si `widget.digest?.quote == null`, rien ne doit s'afficher — vérifier que le layout ne laisse pas d'espace vide
- **AnimatedSwitcher** + QuoteBlock en premier : vérifier que le cross-fade ne fait pas "sauter" le scroll position

## Dépendances

- Aucun endpoint API modifié — les données (quote, pepite, coupDeCoeur) sont existantes
- Nécessite un digest avec mode editorial activé (flag `usesEditorial`)
- La citation Serein nécessite `digest.quote != null` (présent dans les vraies données API)
- Tests sur device physique recommandés pour valider le backdrop blur
