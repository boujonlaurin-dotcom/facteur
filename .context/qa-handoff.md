# QA Handoff — Perf & UX de "Ajout de source custom"

> Feature branch : `boujonlaurin-dotcom/add-source-perf`
> Bug doc : `docs/bugs/bug-add-source-search-perf.md`

## Feature développée

Trois correctifs groupés sur l'écran d'ajout de source custom :
1. **Perf** : short-circuit agressif du pipeline de recherche quand le nom matche fort en DB (catalog seul → <500 ms attendus).
2. **Filtres** : les 5 badges (Médias, Newsletters, YouTube, Reddit, Podcasts) deviennent des `ChoiceChip`s cliquables. Sélection = filtre par type côté backend + skip des layers externes non pertinents.
3. **Élargir la recherche** : bouton qui apparaît sous les résultats quand seul le catalog a répondu → relance le pipeline complet (`expand: true`).
4. **Skeleton** : messages plus lents (800 ms/dot, ~4.8 s/message) et plus variés (6 messages) pour une sensation moins "fake".

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Ajouter une source | `/sources/add` | Modifié |

## Scénarios de test

### Scénario 1 : Recherche rapide d'une source curated (happy path perf)
**Parcours** :
1. Ouvrir "Ajouter une source".
2. Taper "Mediapart" dans le champ de recherche et valider.

**Résultat attendu** :
- Les résultats s'affichent en moins de 500 ms.
- La source "Mediapart" est dans les résultats.
- Un bouton **"Élargir la recherche"** apparaît en bas des résultats.
- Sous le bouton, le texte « Cherche aussi sur YouTube, Reddit et le web. » est visible.

### Scénario 2 : Élargir la recherche
**Parcours** :
1. Après le scénario 1, taper le bouton "Élargir la recherche".

**Résultat attendu** :
- Le skeleton réapparaît brièvement.
- De nouveaux résultats externes s'ajoutent (YouTube / Brave / GoogleNews).
- Le bouton "Élargir la recherche" disparaît après cette relance.

### Scénario 3 : Filtrer par YouTube
**Parcours** :
1. Clear la recherche précédente.
2. Sélectionner la chip **YouTube**.
3. Taper "fireship" et valider.

**Résultat attendu** :
- Seuls des résultats de type YouTube remontent.
- La latence doit être réduite (Brave/Google/Mistral sont skippés).

### Scénario 4 : Médias et Newsletters = même filtre
**Parcours** :
1. Taper "substack" et valider.
2. Sélectionner chip **Médias** → noter les résultats.
3. Sélectionner chip **Newsletters** → noter les résultats.

**Résultat attendu** :
- Les deux filtres donnent exactement les mêmes résultats (tous deux mappent sur `type=article`).
- Chaque chip est visuellement sélectionnée distinctement (on voit laquelle est active).

### Scénario 5 : Skeleton crédible (messages rotating)
**Parcours** :
1. Taper une requête qui va vraiment prendre plusieurs secondes (ex. "xyzzyq1234" qui force tous les layers).
2. Observer le skeleton pendant >10 s.

**Résultat attendu** :
- Les dots animent toutes les 800 ms.
- Les messages changent toutes les ~4.8 s (pas toutes les 1.5 s comme avant).
- Les 6 messages suivants défilent : "Exploration du catalogue", "Analyse de votre recherche", "Interrogation des plateformes", "Scan du web", "Recoupement des sources", "Préparation des suggestions".

### Scénario 6 : Filtre persiste après clear
**Parcours** :
1. Sélectionner chip "Reddit".
2. Taper "r/france", valider.
3. Cliquer sur le bouton clear du champ de recherche.

**Résultat attendu** :
- Le champ est vide.
- La chip "Reddit" reste sélectionnée (volontaire : le filtre persiste pour la prochaine recherche).

## Critères d'acceptation

- [ ] Recherche d'une source curated <500 ms (vs 2-5 s avant).
- [ ] Bouton "Élargir la recherche" visible uniquement si `layers_called == ["catalog"]`.
- [ ] Les 5 chips sont cliquables et mutuellement exclusives.
- [ ] Médias et Newsletters filtrent tous deux sur `article`.
- [ ] Skeleton affiche 6 messages uniques avec rotation lente (~4.8 s/message).
- [ ] Aucune régression sur l'ajout effectif d'une source (flow `trustSource` / `addCustomSource`).

## Zones de risque

- **Changement de family key du `smartSearchProvider`** : de `String` vers un record `({String query, String? contentType, bool expand})`. Vérifier qu'il n'y a pas d'erreur Riverpod au runtime (refresh, invalidate).
- **Cache backend** : la clé inclut désormais `content_type` + `expand`. Les anciennes entrées en DB sont orphelines mais ne causent pas d'erreur — elles expirent en 24 h.
- **Short-circuit agressif** : surveiller qu'un match "substring seulement" (ex. "le" dans "lenny") ne déclenche PAS le short-circuit (tests unitaires couverts).

## Dépendances

- Endpoint modifié : `POST /sources/smart-search` — nouveaux params optionnels `content_type` (article/youtube/reddit/podcast) et `expand` (bool).
- Réponse schema inchangée — `layers_called` reste le signal principal côté client.
- Table `source_search_cache` — aucune migration nécessaire, seule la clé de hash change.
