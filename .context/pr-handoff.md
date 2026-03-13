# Handoff — Section "Tu n'es pas seul·e" : Animation communauté + citations incarnées

## Contexte

La landing page Facteur (`apps/landing/public/`) a une section témoignages (Section 2 — "Tu n'es pas seul·e") qui manque de vie et d'émotion. L'objectif est double :

1. **Animation "communauté"** : quand l'utilisateur scrolle vers cette section, des silhouettes/avatars/icônes de personnes se "peuplent" progressivement, donnant un vrai sentiment de "on est nombreux à ressentir ça". L'effet doit être **moderne, créatif, et marquant** — pas juste des ronds qui pop.
2. **Citations plus incarnées** : les témoignages actuels ont juste un prénom ("Sandrine A."). Ça fait anonyme et détaché. Il faut rattacher chaque citation à un être humain crédible — via un avatar visuel (initiale colorée) et l'âge de la personne (sans métier).

---

## Serveur local

```bash
cd apps/landing/public && python3 -m http.server 8090
```
→ `http://localhost:8090` (un serveur tourne peut-être déjà)

**Branche** : `claude/update-landing-page-2`

---

## 1. Animation communauté au scroll (la partie créative)

**Section cible** : `<section id="testimonials">` (index.html l.63-109)

**Objectif** : à mesure que la section entre dans le viewport, des "personnes" apparaissent progressivement au-dessus du titre, créant un effet de foule qui grandit. L'utilisateur doit *sentir* qu'il n'est pas seul.

**Contraintes techniques** :
- Stack : HTML/CSS/JS vanilla uniquement (pas de librairie externe)
- Le JS existant utilise `IntersectionObserver` pour le reveal (voir `main.js` l.10-23)
- L'animation doit être **scroll-driven** : les éléments se peuplent progressivement à mesure que l'utilisateur scrolle, PAS d'un seul coup quand la section devient visible
- Responsive : doit fonctionner sur mobile (<768px) et desktop
- Performance : pas de jank, utiliser `transform`/`opacity` uniquement

**Direction créative — sois ambitieux** :
- Pense au-delà des simples ronds avec initiales. Explore des idées comme :
  - Des silhouettes SVG minimalistes style "personnages" (tête + épaules) qui montent depuis le bas
  - Un effet "assemblée" où les gens arrivent par groupes, certains plus grands (plus proches), certains plus petits (plus loin) → effet de profondeur
  - Des micro-animations individuelles (un personnage qui tourne légèrement la tête, un qui fait un petit wave)
  - Un compteur subtil "+ de 200 personnes ressentent la même chose" qui s'incrémente pendant le scroll
  - Des positions organiques (pas une grille rigide) pour un rendu naturel
- Utilise la palette Facteur : `--color-accent: #d4652a`, `--color-accent-light: #fdf0e9`, `--color-bg-alt: #f0ece6`
- L'animation doit être **fluide** et donner une émotion — pas un gadget technique

**Fichiers concernés** :
- `apps/landing/public/css/style.css` : nouveaux styles (section Testimonials commence l.412)
- `apps/landing/public/index.html` : nouveau HTML au-dessus du `<h2>` titre (l.64-65)
- `apps/landing/public/js/main.js` : logique scroll-driven (attention à ne pas casser l'IntersectionObserver existant)

---

## 2. Citations plus incarnées (sans métier)

**État actuel** : chaque `.testimonial-card` a un `.testimonial-card__header` avec juste `<span class="testimonial-card__name">Prénom X.</span>`. L'avatar (`.testimonial-card__avatar`) existe dans le CSS mais est `display: none`.

**Changements** :

### HTML (`index.html`)
Transformer chaque header de card pour inclure un avatar initial + l'âge :
```html
<div class="testimonial-card__header">
    <span class="testimonial-card__avatar">S</span>
    <div class="testimonial-card__identity">
        <span class="testimonial-card__name">Sandrine A.</span>
        <span class="testimonial-card__context">34 ans</span>
    </div>
</div>
```

Données pour chaque personne :
- Sandrine A. → initiale S, 34 ans
- Margaux R. → initiale M, 27 ans
- Romain B. → initiale R, 41 ans
- Sana H. → initiale S, 30 ans

### CSS (`style.css`)
- `.testimonial-card__avatar` : afficher comme cercle coloré (36px, `border-radius: 50%`, blanc sur fond `--color-accent`) avec l'initiale centrée. Alterner les couleurs entre les cards pour varier.
- `.testimonial-card__identity` : flex column, contient name + context
- `.testimonial-card__name` : passer en `font-weight: 600`, `font-size: var(--font-size-sm)`, `color: var(--color-text)`. Retirer le `::before` avec le tiret cadratin.
- `.testimonial-card__context` : `font-size: var(--font-size-xs)`, `color: var(--color-text-muted)`

---

## Fichiers concernés (résumé)

| Fichier | Changements |
|---------|------------|
| `apps/landing/public/css/style.css` | #1 animation crowd CSS, #2 avatar + identity styles |
| `apps/landing/public/index.html` | #1 crowd HTML, #2 avatar+age dans headers |
| `apps/landing/public/js/main.js` | #1 scroll-driven logic pour l'animation |

## Vérification

1. Refresh `http://localhost:8090`
2. Scroller lentement vers la section "Tu n'es pas seul·e" — les personnages doivent se peupler **progressivement au scroll**, pas d'un coup
3. Les 4 citations doivent montrer un avatar rond coloré + prénom + âge
4. Tester responsive < 768px
5. Pas de jank visible (ouvrir DevTools Performance si doute)
