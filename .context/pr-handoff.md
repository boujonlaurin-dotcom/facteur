## Veille — ajustements finaux (« released »)

Rend la Veille « release-ready » en corrigeant les 3 griefs PO (compte NBA,
`laurin_boujon@proton.me`) : faux-positifs massifs, point d'entrée disparu,
veille éparpillée + bouton hors design-system.

### Partie 1 — [critical] Fix des faux-positifs + banc de mesure (backend)

**Cause racine.** Le **Bloc A « Tes sources »** de `fetch_veille_feed` était en
**laisser-passer total** (`apply_floor=False`) : tout article récent (30 j) d'une
source configurée entrait sans filtre de pertinence. Une source large (The
Athletic, tous les sports) inondait une veille étroite (NBA) de
cricket/hockey/baseball. Le floor « la source est un boost, pas un free-pass » ne
tournait jamais en prod pour les sources configurées.

**Fix (gate-all, décision PO « le plus strict »).**
- `feed_filter.py` Bloc A : `apply_floor=True, apply_threshold=True`. Le floor ne
  mord que si la config a un axe topic/mot-clé (`floor_active`) → une config
  **purement source** garde le laisser-passer (fallback voulu).
- `_matched_axes` : matching mot-entier (`matches_word_boundary`) au lieu de
  sous-chaîne — aligne l'axe `keyword` exposé sur le scoring/prédicat SQL et
  empêche un mot-clé générique de survivre sur un fragment (« nets » ⊂
  « internets ») dans le Bloc A.

**Banc de mesure (le « dataset de test » demandé, sans LLM).**
- `tests/fixtures/veille_curation_gold.json` — gold écrit à la main (27 articles,
  configs NBA topic-ML-mort + IA topic-ML-vivant), encode le repro.
- `scripts/evaluate_veille_curation.py` — rejoue la **vraie** porte
  (`_score_block`/`_matched_axes`, anti-drift) : P/R/F1, FP par bloc/chemin, FN
  par raison, couverture d'axe, `--sweep`, `--compare`.
- `tests/scripts/test_evaluate_veille_curation.py` + toy fixture — anti-drift +
  confusion connue (FP Bloc A `source_only` planté tué par le floor ; FN
  mot-clé-absent ; mot-entier « agentic »).
- `docs/maintenance/maintenance-veille-curation-calibration.md` — doc + journal.

**Résultat mesuré (baseline laisser-passer → gate-all) :** précision **0.786 →
1.000** (+0.214), **FP Bloc A `source_only` 3 → 0**, **rappel inchangé** (0.846 ;
les 2 FN paraphrases étaient déjà perdues au cap de diversité). La config IA
(topic ML vivant) reste à P=R=1.0 — le gate ne coûte rien quand le topic porte le
rappel.

### Partie 2 — Onglet veille dédié dans les réglages

`settings_sheet.dart` : nouvelle tuile **« Ma veille »** (icône jumelles), état
adaptatif (veille active → menu modifier/archiver ; sinon → « Crée ta veille » →
flow de création). Restaure le point d'entrée découvrable retiré au commit
`dbb6aa20`. Le menu modifier/**archiver** (seul chemin d'archivage de l'app) est
**déplacé** ici depuis Mes intérêts (pas perdu).

### Partie 3 — Cleanup « Mes intérêts » + alignement bouton

- `my_interests_screen.dart` : retrait des CTAs veille autonomes
  (`_CreateVeilleCta` + bouton/menu « Gérer ma veille ») qui doublonnaient.
- `tournee_composer_sheet.dart` : `ComposeTourneeButton` passe au composant
  canonique **`PrimaryButton`** (terracotta plein, `elevation:0`) au lieu de la
  tuile teintée + ombre (« dégradé étrange »). Haptique conservée.
- Libellé section : `VeilleConfigDto.sectionLabel` = **premier angle** (topic
  granulaire « NBA ») au lieu du thème macro (« Sport »). Appliqué aux 4 sites
  (`flux_continu_provider.dart`, `manage_favorites_sheet.dart`).

### Tests / vérif

- Backend : suite complète verte (**1617 passed**, 1 skipped, 2 xfailed) ;
  `prove_veille_curation.py` → VERDICT GLOBAL OK ; ruff clean.
  `test_feed_pagination_across_block_boundary` mis à jour (comportement gate-all
  assumé). Les DB tests exigent `DATABASE_URL` vers `facteur_test`.
- Mobile : `flutter analyze` clean (info-only, déjà présents) ; tests veille DTO
  (+ `sectionLabel`), flux_continu, manage_favorites, my_interests, settings
  verts. Le test de régression #639 (CTA my_interests) est retiré (CTA déplacé
  vers les réglages) ; un test `sectionLabel` est ajouté. **À valider via
  `/validate-feature`** (onglet « Ma veille », bouton primary, section « Ma
  veille — NBA »).

**Aucune migration Alembic** (pas de changement de schéma).

Changelog : entrée `unreleased` « Veille ».
