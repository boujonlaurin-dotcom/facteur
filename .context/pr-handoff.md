feat(tournée): sources favorites en sections dédiées (hero logo + top-3 classé + curation)

PR 1 de « Sources dans la Tournée ». Une source favorite devient une **vraie section de la
Tournée** (Flux Continu), cohérente avec les sections thème : hero **nom + grand logo source**,
**top-3 articles classés** par les mêmes piliers de scoring que les thèmes (fenêtre adaptative
24→48→72h), dédup inter-sections, et **« Lire plus »** → **curation complète** de la source.

## Pourquoi
La Tournée reflétait les thèmes/sujets favoris mais **jamais les sources favorites** (provider
séparé, consommé seulement par Flâner). Le PO veut des sections source premium dans la Tournée,
alimentées via le mécanisme de favori existant.

## Ce que fait la PR
**Backend** (`recommendation_service.py`, logique seule, **aucune migration**)
- Élargit le dispatch `is_personalized_theme_mode` (+ son recompute inline dans `_get_candidates`)
  pour accepter `source_uuid` : `source_id + personalized=true` passe par le PillarScoringEngine
  (fenêtre adaptative), au lieu de l'early-return chronologique. Le filtre `source_id` restreint déjà
  le pool à une source, donc la stratification two-phase reste inerte.
- **Non-régression Flâner** : Flâner appelle `source_id` **sans** `personalized` → reste chronologique.

**Mobile**
- Modèle : `SectionKind.source` + champs `sourceId`/`sourceLogoUrl` sur `FeedThemeSection`
  (réutilisé → dédup + rendu cartes + see-all gratuits) ; `sectionKey` → `source:<id>`.
- Provider : `_pickFavoriteSources` / `_fetchSourceSections` / `_buildSourceSection`
  (`getFeed(sourceId, personalized:true)`), résolution `Source` via `userSourcesProvider`, compose
  **thèmes → sources → veille**, refetch sur changement de favoris source. Source vide → section
  **toujours visible** (parité veille).
- UI : hero logo **net** (`SourceLogoAvatar.fromUrl`, sans fadeout) ; état vide source + CTA
  « Voir toute la curation ».
- Écran détail `/flux-continu/source/:id` : clone de l'écran thème avec **pagination chronologique
  locale** (curation complète, `personalized:false`), carrousels filtrés `source.id`, **sans** bloc
  « Explorer de nouvelles sources ».

## Décisions PO
- Jusqu'à **3 sources** (parité thèmes) — cap intérimaire ; cap-5 unifié + ordre libre = PR 2.
- Source pauvre → **toujours visible** (état vide), jamais masquée.
- « Lire plus » = **curation complète chronologique** (pas le top-3 classé).

## Tests
- Backend : `tests/test_personalized_theme_mode.py` — dispatch source, SQL `source_id =` + fenêtre
  24h en mode scoring, absence de two-phase, source seule reste chronologique. **20 passés.**
  Suite recommandation : **83 passés.**
- Mobile : provider (composition/ordre/dédup/empty/cap), widget (hero logo + état vide), modèle
  (`sectionKey`). **59 passés** ; **143 passés** en non-régression (widgets/models/sources).
- `flutter analyze` : **0 erreur**.

## Hors scope (PR 2)
Modal unifié de composition de la Tournée + cap 5 total (veille incluse) + ordre 100 % libre.

## Limite de vérif locale
Docker/DB indispo dans ce workspace → curl `/api/feed` live + validation Chrome non exécutés ici
(à faire via `/validate-feature`). Backend couvert au niveau unitaire (capture SQL).
