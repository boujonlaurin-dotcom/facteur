# Bug — « tout en Autres » : la couverture source et les cartes tombent en « Autres » quand la classif est en retard

Type : **Bug prod (mitigation d'affichage)**. Statut : correctif d'affichage
livré. La **cause racine** (worker de classification ML mort depuis le 30/06)
est traitée séparément — cf. [`bug-classification-worker-stopped.md`](bug-classification-worker-stopped.md)
et le plan de redéploiement worker (`.context/handoff_worker_classif_asap.md`).

## Symptôme

Le worker de classification étant à l'arrêt, `content.theme` est **NULL à ~100 %
sur le frais**. Deux surfaces le rendaient visible de façon dégradée :

1. **Fiche source — barres de couverture** (`GET /sources/{id}/coverage`,
   `/profile`) : les articles non classés (`theme IS NULL`) étaient repliés dans
   la ligne agrégée `autres` **et** comptés dans le dénominateur des `pct`. Une
   source dont le frais n'était pas classé s'affichait donc massivement « Autres »,
   écrasant sa vraie couverture historique.
2. **Cartes Flux continu** : la pastille de thème (retirée temporairement en
   Story 10.1) ne montrait plus rien alors que le VM sait retomber sur le
   **thème source** quand le thème ML est absent.

## Correctif (affichage uniquement, zéro migration)

### Backend — `packages/api/app/routers/sources.py`

`_aggregate_source_themes` renvoie désormais `(rows, total_published,
total_classified)` :

- **`total_published`** = tous les articles publiés sur la fenêtre, **NULL
  compris**. Reste la légende « N articles publiés » et le signal de
  volume/fréquence — il ne doit **pas** chuter pendant un backlog de classif.
- **`total_classified`** = articles au `theme` non NULL. C'est le **dénominateur
  des `pct`/`share`** → les barres totalisent 100 % des articles *classés*.
- Les **non classés sont exclus** des barres : ils ne rejoignent plus `autres`
  (qui ne replie plus que la longue traîne des thèmes **nommés** au-delà du
  top-N) ni le dénominateur.
- Tout non classé → `rows` vide (section masquée côté mobile), mais
  `total_count`/`articles_30d` gardent le volume réel.

### Mobile

- `flux_continu_article_card.dart` : la **pastille de thème** est rétablie dans
  le footer, alimentée par `vm.themeLabel` (macro-thème ML granulaire, sinon
  **thème source** en fallback via `Content.progressionTopic`). Masquée si vide.
- `source_profile.dart` / `publication_frequency.dart` : commentaires alignés —
  `share` porte sur les classés, `articles_30d` reste le volume publié (peut
  dépasser la somme de la distribution pendant un backlog).

## Tests

- `tests/test_source_coverage.py` : NULL exclus des barres et des `pct` mais
  comptés dans `total_count` ; tout-NULL → `rows: []` + volume gardé ;
  longue traîne nommée → `autres`.
- `tests/test_source_profile.py` : NULL exclus de `theme_distribution`
  (`share` sur les classés, somme = 1.0) mais comptés dans `articles_30d` ;
  tout-NULL → distribution vide.
- `flux_continu_article_card_test.dart` : pastille rendue via le fallback
  thème source quand les topics ML sont vides ; absente quand rien ne se résout.

## Portée / non-régression

Additif, sans DDL. La correction est purement d'affichage : dès que le worker
reprend et que `theme` se repeuple, les barres se re-remplissent naturellement
(le dénominateur `total_classified` remonte), sans autre changement.
