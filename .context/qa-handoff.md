# QA Handoff — Sources favorites dans la Tournée (PR 1)

> Rempli par l'agent dev. Input de `/validate-feature` (Chrome 390×844).

## Feature développée
Une source favorite s'affiche désormais comme une **vraie section de la Tournée** (Flux
Continu) : hero avec **nom + grand logo de la source**, **top-3 articles classés** par les mêmes
piliers de scoring que les sections thème (fenêtre 24→48→72h), dédup inter-sections, et un
**« Lire plus »** ouvrant la **curation complète** de la source. PR 1 = le contenu, via le mécanisme
de favori existant (favoriser depuis Flâner / Mes sources). L'ordre unifié + cap-5 + modal de
composition arrivent en PR 2.

## PR associée
À créer (`gh pr create --base main`) — voir `.context/pr-handoff.md`.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Tournée (Flux Continu) | `/flux-continu` | Modifié — sections source insérées entre thèmes et veille |
| Détail source | `/flux-continu/source/:id` | **Nouveau** — curation complète + carrousels source |

## Scénarios de test

### Scénario 1 : Happy path — une source favorite devient une section
1. Aller dans Flâner / Mes sources, **favoriser** une source active (ex. Le Monde).
2. Revenir sur la **Tournée**.
**Attendu** : une section apparaît avec le **logo** de la source à droite du hero (net, pas
d'illustration thème), le **nom** de la source comme titre, et **3 articles** classés (ordre ≠ pur
chronologique). La section se place **après les thèmes favoris** et **avant la veille**.

### Scénario 2 : Dédup — pas de doublon avec l'Essentiel / un thème
1. Avec une source favorite dont un article est déjà dans l'Essentiel ou une section thème au-dessus.
**Attendu** : l'article n'apparaît **qu'une seule fois** (la section au-dessus gagne) ; la section
source ne le ré-affiche pas.

### Scénario 3 : « Lire plus » → curation complète
1. Sur une section source, taper **« Tout lire »**.
**Attendu** : écran détail source = **toute la curation** de la source (chronologique, paginée à
l'infini), carrousels filtrés sur la source (affichés seulement si ≥ 2 items), **aucun bloc
« Explorer de nouvelles sources »**, footer « Retour à la Tournée » / « suivant ».

### Scénario 4 : Edge — source sans article frais
1. Source favorite n'ayant aucun article récent dans la fenêtre.
**Attendu** : la section **reste visible** (jamais masquée) avec un **état vide** : « Rien de neuf
récemment chez <source>. » + CTA **« Voir toute la curation »** (ouvre le détail).

### Scénario 5 : Non-régression Flâner
1. Dans Flâner, épingler/filtrer la même source.
**Attendu** : le feed Flâner reste **chronologique** (inchangé) — seul le contexte Tournée est classé.

## Critères d'acceptation
- [ ] Section source = hero logo + nom + top-3 classé (≠ pur chrono).
- [ ] Dédup inter-sections respectée (pas de doublon avec Essentiel/thèmes).
- [ ] « Lire plus » → curation complète + carrousels source (si ≥2) + **pas** d'« Explorer ».
- [ ] Source vide → section toujours visible + CTA « Voir toute la curation ».
- [ ] Flâner reste chronologique (non-régression).
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## Zones de risque
- **Logo réseau** : fallback initiales si l'URL échoue (SourceLogoAvatar).
- **Détail source** : peinture instantanée du top-3 classé puis remplacement par la 1ʳᵉ page
  chronologique → léger reflow attendu au chargement.
- **Cap intérimaire** : jusqu'à 3 sources (parité thèmes) → total possible 3 thèmes + 3 sources +
  veille (le cap-5 unifié est PR 2).

## Dépendances
- Backend `/api/feed?source_id=<id>&personalized=true` → top classé 24h (mêmes piliers que thèmes).
- Backend `/api/feed?source_id=<id>` (sans personalized) → curation complète chronologique.
- Providers : `userSourcesStateProvider` (favoris) + `userSourcesProvider` (catalogue) déjà en place.
- **Aucune migration DB** (changement logique seul, 1 head Alembic).
