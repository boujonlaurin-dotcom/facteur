# QA Handoff — L'Essentiel : cartes ≤ écran + footer auto-hide

> Story `docs/stories/core/9.5.essentiel-cards-fit-screen.md`. UI/visuel + feel
> de scroll → validation Chrome obligatoire (viewport mobile, **2 tailles**).

## Feature développée
Aucune carte du Flux Continu ne dépasse la hauteur utile de l'écran (héros trimmé
3→2→1, sections cap dynamique, bouton « Tout lire » inclus) ; le footer
(MainBottomNav) se masque au scroll vers le bas et revient au scroll vers le haut
(comportement LinkedIn), partout dans l'app.

## PR associée
À créer (`/go`). Base **main**.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| L'Essentiel (Flux Continu) | `/flux-continu` | Modifié |
| Flâner | `/flaner` | Modifié (footer auto-hide uniquement) |

## Scénarios de test (viewport **390×844** ET **360×640**)

### Scénario 1 : Héros & sections ne dépassent jamais l'écran (happy path)
1. Ouvrir L'Essentiel.
2. Scroller carte par carte (snap).
**Attendu** : chaque pile (héros « Ton Essentiel », Actus du jour, thèmes…) tient
dans la hauteur utile, bouton « Lire plus / Tout lire » **visible et non couvert**.
Aucune zone de **lecture libre interne** (pas de scroll fin *dans* une carte),
aucun `_FreeReadEdgeFade` (dégradé bas) sur ces sections. Snap = 1 section/écran,
haptique au franchissement (non régressée).

### Scénario 2 : Trim du héros + réapparition aval
1. Sur petit écran (360×640), observer le héros.
**Attendu** : le héros affiche le lead + 1–2 médiums (pas 5). Les articles éjectés
réapparaissent plus bas (digest/thème) si le même article y figure — jamais
perdus.

### Scénario 3 : Footer auto-hide (LinkedIn)
1. Scroller vers le **bas** → le footer glisse hors écran (~50px regagnés).
2. Scroller vers le **haut** → le footer revient.
3. Revenir tout en haut **ou** changer d'onglet → footer visible.
**Attendu** : transition douce (220 ms), pas de footer « collé » masqué, le bas de
carte (« Lire plus ») n'est jamais couvert. Même comportement sur Flâner.

### Scénario 4 : Console / réseau
**Attendu** : pas d'erreur console, pas de 4xx/5xx inattendu. En debug, surveiller
le log `[fit-net] section "…" dépasse l'écran` : **aucune occurrence** sur héros /
digest / thème (sinon estimation `section_fit` à régler).

## Critères d'acceptation
- [ ] Aucune carte (héros inclus) ne dépasse la hauteur utile, bouton « Lire plus » dégagé.
- [ ] `_tallSections` vide pour héros/digest/thème (pas de free-scroll interne / fade).
- [ ] Héros trimmé sur petit écran ; article éjecté visible plus bas.
- [ ] Footer glisse au scroll down, revient au scroll up / changement d'onglet.
- [ ] Snap 1 section/écran + haptique non régressés.
- [ ] Pastille date/météo du héros intacte.

## Zones de risque
- **Constantes d'estimation** `section_fit.dart` : si une section reste « tall »
  (log `[fit-net]`) ou si le 3ᵉ est masqué alors qu'il y avait la place → régler
  les constantes, **pas** les call sites.
- **`_kStickyBarHeight = 50`** doit refléter la hauteur réelle du sticky (rangée
  44 + track 4 + strip 2). S'il change, re-synchroniser.
- Footer auto-hide partagé entre L'Essentiel et Flâner (même `StatefulShellRoute`).

## Dépendances
Aucun endpoint backend touché. 100 % frontend (Flutter).
