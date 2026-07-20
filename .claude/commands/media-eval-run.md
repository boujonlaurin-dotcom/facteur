# /media-eval-run — orchestrer un run media-eval

`$ARGUMENTS = <domaine> <run_id>` (ex. `cnews.fr pilote-2026-07`).

Tu orchestres le pipeline media-eval de bout en bout pour **un média**, en
autonomie mais avec **une pause humaine bloquante** (GOLD GATE). Tous les
scripts sont dans `packages/api/scripts/media_eval/` et se lancent depuis
`packages/api` (`DATABASE_URL` explicite). **Dry-run d'abord, `--apply`
ensuite** ; hors DB test, `--apply` exige `--allow-prod` (= GO PO).

## Règles non négociables

- **Aucun agent n'écrit en base** : les collecteurs voie B et l'évaluateur
  produisent des artefacts ; seuls les scripts `ingest_*` écrivent en DB.
- **Ne jamais éditer à la main un artefact évaluateur** (`evaluations_*.json`) —
  c'est le critère de succès n°1 (artefacts valides sans retouche).
- **`.context/` n'est jamais commité** (gitignore). Seuls les livrables
  `docs/media-eval/{golden,fiches,rapports}/*` le sont.
- **Ne pas retoucher `docs/media-eval/rubrics/*.md`** une fois le run commencé
  (leur sha256 = `version_prompt` ; toute retouche invalide la comparabilité).

## 0. Pré-vol

- Affiche `DATABASE_URL` (host + base). Confirme la cible (test vs prod).
- `alembic heads` = **1** (sinon stop : régler la chaîne d'abord).
- Si cible prod : rappelle que chaque `--apply` portera `--allow-prod` (GO PO).
- **`PAPPERS_API_TOKEN`** : vérifie présence + 1 requête test (ou lance
  `bash scripts/healthcheck-agent-secrets.sh` qui le teste). Absent/épuisé n'est
  **pas bloquant** : `collect_pappers` bascule sur l'API publique gratuite
  `recherche-entreprises.api.gouv.fr` (identification `present` + actionnariat
  `partiel`). Note-le pour l'interprétation de C5/C9.

## 1. Run + référentiel (idempotents, une fois par run)

```
python3 scripts/media_eval/create_run.py --run-id <run_id> \
    --date-reference <YYYY-MM-DD> --medias <domaines…> [--apply --allow-prod]
python3 scripts/media_eval/seed_medias.py [--apply --allow-prod]
```

`create_run` **refuse** de changer une `date_reference` existante (elle pilote
la fraîcheur) : si conflit, supprimer/recréer le run explicitement.

## 2. Voie A — 6 collecteurs code (dry-run puis `--apply`)

Dans cet ordre, pour `<domaine>`. **Un collecteur bloqué n'arrête pas la
chaîne** (il émet des `bloque_acces` honnêtes) :

```
collect_pages_types.py  --media <domaine> --run-id <run_id>   # découverte + détection
collect_cdjm.py         --media <domaine> --run-id <run_id>   # adhésion + avis fondés
collect_jti.py          --media <domaine> --run-id <run_id>   # certification (souvent absente)
collect_cppap.py        --media <domaine> --run-id <run_id>   # open data (jamais le form POST)
collect_pappers.py      --media <domaine> --run-id <run_id>   # ⚠ exige PAPPERS_API_TOKEN ;
                                                              #   sinon 3 bloque_acces + WARNING (exit 0)
collect_arcom.py        --media <domaine> --run-id <run_id>   # auto-désactivé si non audiovisuel (0 signal)
collect_corpus_articles.py --media <domaine> --run-id <run_id> [--max-articles 40]
                                                              # v1.3 : échantillon d'articles (§5.4) → table corpus,
                                                              #   0 signal (la qualification est voie B). Ignore si run v1.2.
```

Chacun : d'abord sans `--apply` (inspecte le plan), puis `--apply [--allow-prod]`.
`collect_corpus_articles` n'émet **aucun signal** : il remplit
`media_eval_corpus_articles` (texte + pré-métriques mécaniques) que
`build_eval_input` joindra en contexte des critères C2/C3/C4/C5/C7.

### 2bis. Export des snapshots (voie A → fichiers)

**Avant** la voie B, dump les snapshots vers des fichiers — c'est le levier
principal contre les 403 anti-bot : les agents lisent le contenu déjà obtenu par
`curl_cffi` au lieu de re-fetcher.

```
python3 scripts/media_eval/export_snapshots.py --run-id <run_id> --media <domaine>
```

Récupère la liste des chemins écrits (`.context/media_eval/<run_id>/snapshots/*.txt`) :
tu les passeras **explicitement** aux agents voie B.

## 3. Voie B — collecteurs agents (en parallèle)

Spawn en parallèle (Task tool), sortie dans `.context/media_eval/<run_id>/`.
Passe à chacun les **chemins des snapshots exportés** (étape 2bis) — WebSearch /
WebFetch en **complément seulement** :

- `media-eval-collecteur-debunkages` (C1) — `media_domaine`, `media_nom`,
  `run_id`, **`date_reference`** (fenêtre **1095 j / 36 mois** en v1.3 ; 730 j en
  v1.2). Recall élargi (Les Surligneurs, ARCOM, CDJM) + **`cle_affaire`** par
  litige (le code dédupe par affaire avant le comptage fallback).
- `media-eval-collecteur-gouvernance-transparence` — substance propriété /
  financement / publicité (v1.2 : C5 + C7 ; **v1.3 : C6 + C8**).
- `media-eval-collecteur-gouvernance-independance` — déontologie / indépendance /
  positionnement (v1.2 : C8 + C9 + C11 ; **v1.3 : C9 + C10**).
- `media-eval-collecteur-corpus` (**v1.3 seulement**, critères sur corpus §5.4) —
  qualifie l'échantillon d'articles instrumenté par `collect_corpus_articles`
  (voie A) et produit un signal `articles` agrégé par critère (C2/C3/C4/C5/C7).
  Passe-lui les chemins du corpus exporté + `version_methodo=v1.3`.

> ⚠ **Codes de critère par version** : les collecteurs voie A (pages_types,
> cppap, pappers…) posent encore des critères **v1.2** (C5/C7/C8/C11). Pour un
> run **v1.3**, vérifie le mapping avant `--apply` (cf. table de correspondance
> `methodologie-v1.3.md`) — un signal mal étiqueté fausse l'assiette. Traiter ce
> re-mapping voie A est un pré-requis du batch 2 hors CNEWS (suivi séparé).

**Couverture** : chaque agent gouvernance doit rendre **une entrée par
`type_signal` de son registre** (pas de silence). Si un registre CDJM/JTI est
resté `bloque_acces` en voie A, l'agent independance corrobore par WebSearch
(≥ 2 sources) plutôt que de deviner.

**Politique de mort d'agent** : si un agent voie B meurt (session-limit), **respawn
avec périmètre réduit** (la moitié de ses critères). Le repli « l'orchestrateur
écrit lui-même l'artefact » est **interdit sauf accord PO explicite**, et doit
alors être marqué (`agent: "humain:laurin"` → voie HUMAIN).

Puis ingère (validation Pydantic → rejet en bloc si invalide) :

```
python3 scripts/media_eval/ingest_artifacts.py \
    --artifact .context/media_eval/<run_id>/         # dry-run
python3 scripts/media_eval/ingest_artifacts.py \
    --artifact .context/media_eval/<run_id>/ --apply [--allow-prod]
```

L'ingestion émet un **WARNING de couverture** listant tout `type_signal`
gouvernance sans signal (voie A + B) : traite chaque manquant (respawn ciblé ou
`absent_verifie` sourcé) avant le GOLD GATE.

## 4. Entrées évaluateur

```
python3 scripts/media_eval/build_eval_input.py --media <domaine> --run-id <run_id> \
    [--apply --allow-prod]   # --apply seulement pour écrire l'éval C8 du raccourci JTI
```

Génère `.context/media_eval/<run_id>/eval_inputs/<media>_<critere>.json`. Note
les garde-fous journalisés (fraîcheur, fallback C1, raccourci JTI).

> **Répète les étapes 2→4 pour chaque média du run** avant le GOLD GATE.

## 5. 🛑 GOLD GATE — STOP (D4)

**Arrête-toi et notifie Laurin.** Il note **en aveugle**, depuis les **mêmes**
`eval_inputs/*.json` + rubriques, dans le gold de la version du run
(**v1.3 → `docs/media-eval/golden/gold_v1_3.json`** ; v1.2 → `gold_v0.json`),
`note_at` = maintenant UTC. Les évaluateurs ne sont spawnés **qu'après** que le
gold est figé — c'est la preuve mécanique D4 (`rapport_pilote.py` WARNING si le
gold ne précède pas les évaluations). En v1.3, le gold couvre les **10 critères**
(dont C2/C3/C4/C5/C7 sur corpus, notés en aveugle avant tout évaluateur).

## 6. Évaluateurs (1 par critère, après le gold)

Pour chaque `eval_inputs/<media>_<critere>.json` (C8 **sauté** si le raccourci
JTI a produit l'éval) : spawn `media-eval-evaluateur` (tools `Read`). Sa
réponse finale **EST** le JSON brut — **écris-le toi-même** dans
`.context/media_eval/<run_id>/evaluations_<slug>_<critere>.json` (jamais
l'agent, jamais d'édition manuelle du contenu).

**Double évaluation (critères à 3 niveaux : v1.3 = C5/C9/C10).** Pour ces
critères, spawn **deux** évaluateurs indépendants — l'un ne voit jamais la
sortie de l'autre — et écris **deux** artefacts distincts avec des évaluateurs
préfixés `…@v1-a` / `…@v1-b` :
`evaluations_<slug>_<critere>_a.json` et `…_b.json`. À l'export (§7), le
consensus est appliqué par le code : accord → conservé ; **désaccord →
`revue_requise`** avec les deux verdicts documentés (jamais une moyenne). Les
autres critères restent à **un** évaluateur. Puis :

```
python3 scripts/media_eval/ingest_evaluations.py \
    --artifact .context/media_eval/<run_id>/          # dry-run → --apply [--allow-prod]
python3 scripts/media_eval/synthese_fiche.py --media <domaine> --run-id <run_id> \
    [--apply --allow-prod]
```

## 7. Livrables (lecture seule DB + gold)

Le gold est celui de la version du run (`<gold>` = `gold_v1_3.json` en v1.3,
`gold_v0.json` en v1.2). `export_evaluations` applique le **consensus double
évaluation** et imprime l'**accord inter-évaluateurs** sur C5/C9/C10.

```
python3 scripts/media_eval/export_evaluations.py --run-id <run_id> \
    --out .context/media_eval/<run_id>/evaluations_export.json
python3 scripts/media_eval/evaluate_golden_agreement.py \
    --gold ../../docs/media-eval/golden/<gold> \
    --generated .context/media_eval/<run_id>/evaluations_export.json \
    --out-dir ../../docs/media-eval/rapports --slug <run_id>
python3 scripts/media_eval/rapport_pilote.py --run-id <run_id> \
    --gold ../../docs/media-eval/golden/<gold> \
    --out ../../docs/media-eval/rapports/<run_id>.md
```

`rapport_pilote.py` écrit **deux** rendus depuis une unique collecte DB :
`<run_id>.md` (ASCII git-diffable, audit) **et** `<run_id>.html` (rapport propre
autonome, single-file — deux lentilles : propreté des données puis accord des
évaluations + verdict V0). Ouvre le `.html` dans un navigateur pour la revue.

Commite : `docs/media-eval/golden/<gold>`, `docs/media-eval/fiches/*.md`,
`docs/media-eval/rapports/*.{md,html}`. **Jamais** `.context/`.

## 8. Verdict

Lis le verdict V0 (4 critères) dans `rapports/<run_id>.md`. Rapporte PASS/FAIL
avec les preuves chiffrées ; ne conclus « V0 validé » que si les 4 sont PASS.
