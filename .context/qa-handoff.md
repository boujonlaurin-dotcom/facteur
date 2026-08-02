# QA Handoff — Story 33.1 : le tri dans le feed (carte « Ton Essentiel » triable)

> Rempli par l'agent dev. Input de /validate-feature. Story :
> `docs/stories/core/33.1.tri-dans-le-feed.md`.

## Feature développée

La carte « Ton Essentiel » en tête du Flux continu n'est plus une liste passive :
elle devient une **pile à trier**. Un article à la fois, swipe droite « Je lis »,
swipe gauche « Pas pour moi », bouton signet « Plus tard ». La liste des gardés se
construit sous la pile, dans le feed, sans écran supplémentaire.

**V0 en collecte seule** : chaque décision est enregistrée avec son rang dans le
slate figé, mais **aucun poids de reco ne bouge**. Seule exception actée par le
PO : « Plus tard » déclenche le save existant, exactement comme le bouton signet
de la carte.

## PR associée

À créer (`--base main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flux continu (carte « Ton Essentiel ») | `/flux-continu` | Modifié |
| Lettre passée (rewind J-7) | `/flux-continu` + timeline | Modifié (doit **rester** passive) |

## Scénarios de test

### Scénario 1 — Happy path : trier les 5
**Parcours** :
1. Ouvrir l'app sur le Flux continu, édition du jour.
2. La carte affiche la pile : progression « 0 sur N triés », un article, la barre
   d'actions (✕ · signet · « Je lis »).
3. Swiper à droite → tampon « JE LIS », la carte part, l'article apparaît dans la
   liste sous la pile, la progression avance.
4. Swiper à gauche → tampon « PAS POUR MOI », l'article ne rejoint pas la liste.
5. Trier tous les articles.

**Résultat attendu** : au dernier geste, la carte reprend sa liste habituelle
(lead + médiums, **tous** les articles, rejetés compris) et affiche « Trier à
nouveau » en pied. Aucun 4xx/5xx, un seul `POST /api/essentiel/triage` (batché).

### Scénario 2 — Le feed ne saute pas
**Parcours** :
1. Repérer un point de repère visuel juste sous la carte Essentiel.
2. Trier les articles un par un en observant ce repère.

**Résultat attendu** : la carte **ne change pas de hauteur** entre le premier et
le dernier geste — la hauteur est réservée d'avance (`triageReservedHeight`).
Vérifier aussi que les ancres de snap du scroll restent correctes.

### Scénario 3 — Mode boutons seuls (accessibilité)
**Parcours** :
1. Sans jamais swiper, utiliser uniquement ✕ / signet / « Je lis ».

**Résultat attendu** : même mouvement de sortie que le swipe. Les 3 boutons
portent un label sémantique (`Pas pour moi`, `Plus tard`, `Je lis`).

### Scénario 4 — Tri partiel puis kill/relaunch
**Parcours** :
1. Trier 2 articles sur 5.
2. Tuer l'app, la relancer.

**Résultat attendu** : la pile **reprend au 3ᵉ article**, les décisions déjà
prises sont conservées, l'ordre de la pile est **identique**.

### Scénario 5 — Refetch en cours de tri (piège n°3)
**Parcours** :
1. Commencer à trier.
2. Provoquer un refetch de l'Essentiel (pull-to-refresh, ou retour foreground).

**Résultat attendu** : **le slate ne bouge pas**. Ni l'ordre, ni la carte du
dessus, ni la progression. `GET /api/essentiel` re-ranke à chaque requête ; le
gel est ce qui empêche la pile de changer sous le doigt.

### Scénario 6 — « Trier à nouveau »
**Parcours** :
1. Terminer un tri, taper « Trier à nouveau ».

**Résultat attendu** : la pile repart au 1ᵉʳ article, **avec le même ordre** (le
slate est figé pour la journée). Le backend écrase par upsert, sans dupliquer.

### Scénario 7 — Lettre passée
**Parcours** :
1. Ouvrir le rewind, sélectionner l'édition d'hier.

**Résultat attendu** : **aucune pile**. La lettre passée reste passive.

### Scénario 8 — Réseau coupé
**Parcours** :
1. Passer en mode avion, trier les 5, revenir en ligne.

**Résultat attendu** : le tri **n'attend jamais le réseau** (aucun spinner,
aucun blocage). Les décisions repartent au flush suivant.

## Critères d'acceptation

- [ ] La pile remplace la liste passive sur l'édition du jour, pas ailleurs
- [ ] Swipe droite/gauche et les 3 boutons produisent la bonne décision
- [ ] La carte ne change pas de hauteur pendant le tri (feed stable)
- [ ] Le slate survit à un kill/relaunch et ne bouge pas au refetch
- [ ] « Trier à nouveau » réinitialise sans rebattre l'ordre
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus
- [ ] Copy : aucun em-dash, ton sobre (pas de facteur personnifié)

## Garde-fous à vérifier côté données (le cœur de la V0)

Après un tri contenant au moins un « Pas pour moi » :

```sql
-- Les décisions sont écrites avec leur rang et la taille du slate
SELECT decision, rank, slate_size, decided_via, latency_ms
  FROM essentiel_triage_decisions WHERE digest_date = CURRENT_DATE;

-- GARDE-FOU n°1 : aucune source mutée. `not_interested` ajouterait la source
-- entière à muted_sources, sans expiration. Le tri ne doit JAMAIS y toucher.
SELECT user_id, muted_sources FROM user_personalization
 WHERE cardinality(muted_sources) > 0;

-- GARDE-FOU n°2 : aucun poids bougé par le tri
SELECT count(*) FROM user_subtopics WHERE updated_at > now() - interval '5 min';
SELECT count(*) FROM user_entity_affinity WHERE updated_at > now() - interval '5 min';

-- Seul effet attendu : les « Plus tard » sont mis de côté
SELECT content_id, is_saved FROM user_content_status WHERE is_saved IS TRUE;
```

Script E2E de l'endpoint : `bash docs/qa/scripts/verify_essentiel_triage.sh`
(exige `API_URL` + `JWT`).

## Notes pour l'agent QA

- Viewport 390×844, sémantique activée au boot (skill `facteur-qa-web`).
- La pile n'apparaît qu'après l'hydratation SharedPreferences (quelques frames) :
  laisser la page se poser avant d'asserter.
- Le tri est **fire-and-forget batché** (debounce 2 s, flush à la fin du tri et
  au passage en arrière-plan) : ne pas s'attendre à un POST par swipe.
