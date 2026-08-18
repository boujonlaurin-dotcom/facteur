# Maintenance : cold start — ordre de chargement « héros d'abord »

**Date :** 2026-08-18
**Classification :** MAINTENANCE
**Branche :** `boujonlaurin-dotcom/cold-start-load-order`
**Précède :** [#1097](maintenance-tournee-loading-smoothness.md) (gzip + émission anticipée du héros + loader vélo)

---

## Demande PO

1. Un **diagramme complet et vulgarisé** de ce qui charge au cold boot, dans quel
   ordre (ce document).
2. **Revoir l'ordre des appels** pour privilégier au maximum la 1ʳᵉ carte « Ton
   Essentiel » : elle retient désormais l'utilisateur 15-20 s de tri, donc tout
   le reste dispose d'un budget de temps naturel pendant qu'il trie. Et rendre
   **smooth** le chargement des cartes suivantes quand un utilisateur « rush »
   la carte héros sans trier.

---

## Le bureau de poste, vulgarisé

Pour lire les diagrammes : l'app est un **bureau de poste** qui ouvre ses portes
le matin.

- Le **guichet** = le backend (un **seul** guichetier : l'unique worker uvicorn).
  Tout appel réseau fait la queue au même guichet.
- Le **badge** = le JWT. Le matin, le badge de la veille est toujours périmé
  (TTL 1 h) : il faut le renouveler avant de demander quoi que ce soit au
  guichet, sinon c'est un refus (401) puis re-queue garanti.
- La **carte héros** « Ton Essentiel » = le paquet prioritaire (`/api/essentiel`).
  C'est le premier contenu réel que l'utilisateur voit — et depuis la refonte
  du tri, celui qui l'occupe 15-20 secondes.
- La **lettre du jour** (`/api/digest/both`) = le colis le plus lourd (2 digests,
  texte intégral des articles).
- La **tournée** = les ~14 sections thème/source/veille/suggestions, remplies par
  un fan-out de `GET /api/feed` (3 en vol max).

## Aujourd'hui (avant ce lot) : tout le monde fait la queue devant le paquet prioritaire

```mermaid
sequenceDiagram
    autonumber
    participant U as 👤 Utilisateur
    participant E as 🖥 Écran (squelette)
    participant P as 📦 Provider (chef de tournée)
    participant G as 🏤 Guichet unique (backend)

    U->>E: ouvre l'app (cold boot du matin)
    E->>P: build()
    Note over P: peint le squelette<br/>(en-têtes réels, cartes vides,<br/>héros = silhouette statique)
    Note over P: ⚠️ dès build(), 7-9 demandes annexes<br/>partent en douce : intérêts, sources,<br/>grille, thèmes suivis, alertes, veille…
    P->>P: renouvelle le badge (JWT, ≤3 s)
    P->>G: réconciliation placement (2 GETs)
    par les 3 appels de base, ensemble
        P->>G: /api/essentiel (le paquet prioritaire)
        P->>G: /api/digest/both (le colis lourd)
        P->>G: /api/feed/top-themes
    end
    Note over G: 1 seul guichetier :<br/>les annexes se mêlent à la queue<br/>et retardent le paquet prioritaire
    G-->>P: /api/essentiel répond
    Note over P: le héros est prêt côté données…<br/>❌ mais l'écran squelette rend une<br/>silhouette STATIQUE : rien ne change
    G-->>P: /api/digest/both répond (le plus lent)
    Note over E: Phase 1 : le squelette bascule<br/>vers le vrai contenu — le héros<br/>n'apparaît QUE maintenant
    par fan-out (3 en vol), ordre favoris ≠ ordre d'affichage
        P->>G: ~14 × /api/feed (thèmes, sources, veille, suggestions)
    end
    G-->>P: sections remplies une à une
    Note over E: des suggestions au-delà du cap<br/>de 13 sont fetchées… jamais affichées
```

### Diagnostic (vérifié dans le code)

- **D1 — Le gain n°1 est un trou de peinture, pas un problème réseau.**
  L'émission anticipée de #1097 publie bien le héros hydraté dans l'état
  squelette (`flux_continu_provider.dart`, early-emit sur `essentielFuture`),
  mais `_FluxContinuSkeleton` rend un `_HeroSkeleton` statique inconditionnel et
  **saute** l'`EssentielSection`. La pile ne devient visible qu'à la Phase 1 =
  max des 3 appels de base, en pratique `/api/digest/both` (le plus lourd).
- **D2 — 7 à 9 appels annexes partent avant/avec le héros.** Les `ref.listen` de
  `build()` initialisent immédiatement `userInterestsProvider`,
  `userSourcesStateProvider`, `grilleProvider`, `themesFollowedProvider`,
  `alertsProvider` (réseau) ; `_reconcilePlacementThenSync` ajoute 2 GETs et
  peut publier un état non-squelette mi-bootstrap. Des `ref.read` dans la
  composition du squelette initialisent aussi ces providers en douce
  (`_pickFavorites`, `veilleActiveConfigProvider`, `_pickFavoriteSources`,
  grille, alertes, `_stampFollowedCounts`). Tout ça concurrence `/api/essentiel`
  sur le pool Dio et l'unique worker uvicorn.
- **D3 — Le fan-out (~14 GET `/api/feed`, concurrence 3) part dans l'ordre
  favoris, pas l'ordre d'affichage** (veille avant sources, bias/ordre
  custom/score ignorés), et fetch des suggestions au-delà du cap de 13 jamais
  affichées.
- **Le gate JWT ≤3 s est le chemin rapide, pas l'ennemi** : le token du matin
  est toujours mort (TTL 1 h), tirer avant = 401→refresh→retry garanti. On le
  garde.

---

## Instrumentation `[PERF]` (commit 1 — capture l'avant)

Grammaire existante (`[PERF] fluxContinu.<metric>=<ms>`), origine = entrée de
`build()` du provider (sauf `hero_paint_ms`, origine = montage de l'écran) :

| Métrique | Où | Sens |
|---|---|---|
| `gate_ms` | provider | fin du gate JWT (refresh initial borné 3 s) |
| `essentiel_dispatch_ms` | provider | départ de la requête `/api/essentiel` |
| `essentiel_resolved_ms` | provider | réponse de `/api/essentiel` |
| `hero_emit_ms` | provider | émission de l'état squelette portant le héros hydraté |
| `phase1_ms` | provider | émission Phase 1 (haut de page réel : héros+Actus+Bonnes) |
| `fanout_done_ms tasks=N dropped=M` | provider | fin du fan-out des sections (M = suggestions non fetchées) |
| `hero_paint_ms` | écran | **la** métrique avant/après : premier frame qui peint la carte héros hydratée |

Protocole de mesure : kill app + purge du snapshot Hive (simule le matin),
3 runs avant/après sur staging.

## Après (ce lot) : le paquet prioritaire passe devant — à compléter

_Sera complété en fin de lot : diagramme « après » + chiffres mesurés._

## Étapes du lot

1. Instrumentation `[PERF]` + ce document (l'« avant »').
2. **B0+C1** — peindre le héros dès qu'il atterrit (vraie carte interactive dans
   le squelette) + squelette scrollable qui conserve l'offset au flip Phase 1.
3. **B1+B2** — 3 vagues d'appels (essentiel seul → digest/top-thèmes après
   `min(essentiel résolu, 600 ms)` → providers annexes après la Phase 1) + fin
   des initialisations furtives (`_peek`).
4. **B3** — fan-out dans l'ordre d'affichage + cap des suggestions fetchées
   (+1 de réserve pour `dismissSuggestion`).
5. _(droppée si besoin)_ Cache local des noms de coquilles.
6. Doc « après » + chiffres.
