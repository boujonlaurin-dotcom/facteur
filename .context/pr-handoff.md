# feat(media-eval): harness batch 2 — critères sur corpus + double évaluation + recall C1 (Phase 4)

**PR C** de la trajectoire media-eval (base `main`). Outillage du batch 2 CNEWS,
**avant** toute collecte. Aucune migration (additif / expand-safe, 1 head).

## Ce que ça livre

**1. Corpus d'articles (C2/C3/C4/C5/C7)**
- `schemas.py` : vague-1 v1.3 étendue aux **10 critères** ; registre `articles`
  (+ structurels C3 `page_corrections`/`canal_signalement`/`reponse_evaluation_externe`) ;
  `Grille.criteres_corpus` (v1.3 = C2/C3/C4/C5/C7 ; v1.2 = ∅).
- **`collect_corpus_articles.py`** (nouveau, voie A) : échantillonne + snapshote
  des articles récents (home + sitemap) dans `media_eval_corpus_articles` +
  pré-métriques mécaniques (signature ? label d'opinion ? liens sortants ?).
  N'émet **aucun signal** (la qualification est voie B). Idempotent.
- `build_eval_input.py` : joint un bloc `corpus_articles` (contexte non citable,
  borné) aux eval_inputs des critères sur corpus.
- Agent **`media-eval-collecteur-corpus`** (nouveau, voie B) : qualifie le corpus
  → un signal `articles` agrégé par critère.

**2. Double évaluation C5/C9/C10 (décision PO 18/07)**
- `export_evaluations.py` : le `raise` sur doublon (média, critère) devient un
  **consensus** — accord conservé ; désaccord → `revue_requise` documenté (jamais
  moyenné). Rendu **version-aware** (chaque entrée porte `version_methodo`).
  Héberge aussi la métrique **accord inter-évaluateurs** (même règle d'accord).
- `evaluate_golden_agreement.py` : `_paire_accord` compare C2..C7 à niveaux en
  v1.3 (pas en tolérance continue), grille résolue depuis la version du gold.
- `/media-eval-run` §6 : deux évaluateurs indépendants `…@v1-a` / `…@v1-b`.

**3. Débunkages C1 — recall + dédup par affaire**
- `DebunkageArtifact.cle_affaire` → écrit dans le `valeur` du signal C1 (repli
  sur l'URL) ; `_nb_debunkages_frais` compte des **affaires distinctes** (fallback
  C1 correct : un événement très couvert = un litige).
- Agent débunkages : requêtes élargies (Les Surligneurs, ARCOM, CDJM), fenêtre
  **36 mois** (v1.3), `cle_affaire` par litige.

**4. Pappers** : inchangé (repli gratuit). Recharger les crédits = action Laurin.

## Hors périmètre (suivi séparé)
- Threading de la synthèse sur la version (`synthese_fiche`/`rapport_pilote`/
  `ingest_artifacts.rapport_couverture`) — **Phase 6**, avant la fiche publiable.
- Re-mapping des codes de critère **voie A** pour un run v1.3 (les collecteurs
  structurels posent encore C5/C7/C8/C11 v1.2) — signalé WARNING dans
  `/media-eval-run` §3, à traiter avant la collecte batch 2 hors CNEWS.

## Correctifs de revue (harness)
`collect_corpus_articles.py` : filtre same-domain tolérant `www.` (appliqué aussi
aux URLs sitemap — sinon corpus quasi vide pour un site canonique `www.` comme
CNEWS) ; `liens_sortants` ne compte que les liens vers un **autre** domaine
(pré-métrique C2 sinon gonflée par les liens internes absolus) ;
`date_depuis_url` lit le format `/AAAA-MM-JJ/` (pattern CNEWS).

## Simplify
`accord_inter_evaluateurs` déplacé dans `export_evaluations.py` (supprime le
cycle d'import différé + `_verdict` dupliqué) ; `collect_corpus_articles` porté
sur le harnais CLI commun `collect_common._run` (garde `--apply`, dry-run,
rollback — plus de copie) + helpers partagés (`meme_domaine`, `_RE_HREF_ARTICLE`,
`FetchResult` en test) ; `cle_affaire_signal` rangé dans `schemas.py` à côté du
contrat d'écriture ; paramètre mort `version_methodo` retiré de
`evaluations_to_goldenset`.

## Tests
`tests/scripts/media_eval/` : **260 passent** (en série ; fixture `create_tables`
DROP le schéma). 1 head Alembic. `ruff check` OK. Aucune migration.

Doc : `docs/maintenance/maintenance-media-eval-harness-batch2.md`.
Pas d'entrée changelog (outillage interne).
