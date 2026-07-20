# Maintenance — Media-eval : harness batch 2 (critères sur corpus + double évaluation)

> **Type** : Maintenance (outillage). **PR C** de la trajectoire media-eval, base
> `main`, stackée logiquement sur #989 (grille v1.3). Périmètre = **Phase 4** du
> hand-off (`.context/media-eval-handoff-CEA.md`) : écrire l'outillage du batch 2
> **avant** toute collecte. STOP après revue du harness ; la collecte CNEWS
> (Phase 5) + le gold gate D4 restent des étapes humaines séparées.

## Contexte

Le batch 1 (#989) n'a activé en v1.3 que les 5 critères **hors corpus**
(C1/C6/C8/C9/C10). Les 5 manquants (C2 sourçage, C3 correction, C4 info/opinion,
C5 diversité, C7 auteurs) reposent tous sur un **échantillon d'articles** (§5.4)
qui n'était ni collecté ni injecté. Cette PR livre l'outillage qui rend ces
critères évaluables, plus la double évaluation des critères à 3 niveaux et le
recall des débunkages C1.

## Ce que livre la PR (Phase 4)

1. **Corpus d'articles (C2/C3/C4/C5/C7)**
   - `schemas.py` : `_CRITERES_VAGUE_1_V13` étendu aux **10 critères** ;
     `_TYPE_SIGNAUX_V13` étendu (`articles` pour C2/C4/C5/C7 ; `page_corrections`,
     `canal_signalement`, `reponse_evaluation_externe` + `articles` pour C3) ;
     nouveau champ `Grille.criteres_corpus` (v1.3 = C2/C3/C4/C5/C7 ; v1.2 = ∅).
   - `collect_corpus_articles.py` (**nouveau**, voie A) : découvre des articles
     récents (home + sitemap), snapshote leur texte dans
     `media_eval_corpus_articles` et calcule des **pré-métriques mécaniques**
     (signature ? label d'opinion ? liens sortants ?). N'émet **aucun signal** :
     la qualification est voie B. Idempotent, ne lève jamais sur fetch bloqué.
     S'appuie sur le harnais CLI commun de `collect_common` (`_run` : garde
     `--apply`/`--allow-prod`, dry-run, rollback) au lieu de le dupliquer.
   - `build_eval_input.py` : joint un bloc **`corpus_articles`** (contexte non
     citable, borné) aux eval_inputs des critères sur corpus.
   - Agent voie B **`media-eval-collecteur-corpus`** (nouveau) : qualifie le
     corpus exporté → un signal `articles` agrégé par critère.

2. **Double évaluation C5/C9/C10 (décision PO 18/07)**
   - `export_evaluations.py` : le `raise` sur doublon (média, critère) devient un
     **mode consensus** — accord → conservé ; désaccord → `revue_requise` avec les
     deux verdicts documentés (jamais une moyenne). Rendu **version-aware**
     (chaque entrée porte `version_methodo` du run → les critères v1.3 valident).
     Héberge aussi la métrique **accord inter-évaluateurs** (même règle d'accord,
     même groupement que le consensus).
   - `evaluate_golden_agreement.py` : `_paire_accord` résout la grille depuis la
     version du gold (C2..C7 comparés à niveaux en v1.3, pas en tolérance
     continue).
   - `/media-eval-run` §6 : deux évaluateurs indépendants `…@v1-a` / `…@v1-b`.

3. **Débunkages C1 — recall + dédup par affaire**
   - `DebunkageArtifact.cle_affaire` (nouveau champ) → écrit dans le `valeur` du
     signal C1 (repli sur l'URL). `build_eval_input._nb_debunkages_frais` compte
     désormais des **affaires distinctes** dans la fenêtre (un événement très
     couvert = un litige), ce qui pilote correctement le fallback C1.
   - Agent `media-eval-collecteur-debunkages` : requêtes élargies (Les
     Surligneurs, ARCOM, CDJM), fenêtre **36 mois** (v1.3), `cle_affaire` par
     litige.

4. **Pappers** : inchangé côté code (repli gratuit
   `recherche-entreprises.api.gouv.fr`). Recharger les crédits = action Laurin
   avant le run (hors PR).

## Décisions & garde-fous

- **Aucune migration.** Le corpus vit dans la table `media_eval_corpus_articles`
  (déjà créée par `me01`) et la `cle_affaire` dans le JSONB `valeur` du signal :
  **additif, expand-safe**, 1 seul head Alembic. Un resserrement futur du CHECK
  reste un `me03` en semaine N+1.
- **Version portée par run.** Le code neuf passe par `grille(version)` ; les alias
  plats du module restent v1.2 (batch 1). Un run v1.3 ne réécrit aucun run v1.2.
- **Les agents n'écrivent jamais en DB** : `collect_corpus_articles` (voie A,
  code) écrit la table corpus ; l'agent corpus (voie B) produit des artefacts
  ingérés par `ingest_artifacts`.

## Explicitement hors périmètre (suivi séparé)

- **Threading de la synthèse sur la version** (`synthese_fiche.py`,
  `rapport_pilote.py`, `ingest_artifacts.rapport_couverture`/`CRITERES_GOUVERNANCE`)
  — **Phase 6**, différé de #989 ; lit encore les constantes plates v1.2. Requis
  avant la fiche CNEWS publiable, pas avant la collecte.
- **Re-mapping des codes de critère voie A pour un run v1.3.** Les collecteurs
  voie A structurels (`collect_pages_types`, `collect_cppap`, `collect_pappers`…)
  posent encore des critères **v1.2** (C5/C7/C8/C11) via `Collecteur.signal`
  (validation en `VERSION_METHODO` = v1.2). Pour un run v1.3, ces codes ne
  correspondent plus (v1.3 C5 = diversité, C6 = mentions…). **À traiter avant la
  collecte batch 2 hors CNEWS** ; signalé en WARNING dans `/media-eval-run` §3.

## Tests

- `test_schemas.py` : vague-1 à 10 critères, registre `articles`, `criteres_corpus`.
- `test_collect_corpus_articles.py` (**nouveau**) : détection d'URL d'article,
  rubrique/date, pré-métriques, sélection ; bout-en-bout DB avec fetcher injecté
  (idempotence, home bloquée → corpus vide). Correctifs de revue : filtre
  same-domain tolérant `www.` (appliqué aussi au sitemap — sinon corpus quasi
  vide pour un site canonique `www.` comme CNEWS), `liens_sortants` ne compte
  que les liens vers un **autre** domaine, `date_depuis_url` lit `/AAAA-MM-JJ/`.
- `test_build_eval_input.py` : injection du bloc corpus (présent pour C2, absent
  pour C1), dédup débunkages par affaire (2 affaires sur 3 débunkages).
- `test_export_evaluations.py` : consensus accord / désaccord → revue_requise.
- `test_evaluate_golden_agreement.py` : accord inter-évaluateurs, C2 à niveaux en v1.3.
- `test_ingest_artifacts.py` : `cle_affaire` propagée dans le `valeur`.
- Suite `tests/scripts/media_eval/` : **260 passent** (en série, cf. fixture
  `create_tables` qui DROP le schéma). 1 head Alembic. `ruff check` OK.

## Suite

STOP → revue du harness. Ensuite : Phase 5 (run `pilote-2026-08` CNEWS, collecte
voie A+B, build eval_inputs des 10 critères) puis **gold gate D4** (notation
aveugle Laurin dans `gold_v1_3.json`) avant tout évaluateur.
