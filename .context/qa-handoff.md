# QA Handoff — Veille V3 PR2 « Sources quality + custom sources »

## Feature développée

PR2 du V3 veille : refonte du suggesteur de sources (le LLM produit
maintenant **une seule liste rankée par pertinence**, plus la séparation
followed/niche), nouveau wording « Connecter / Connectée », badge
« CONFIANCE » sur les sources déjà suivies, et bouton « + Ajouter une
source » dans Step 3 qui ouvre un sheet de recherche réutilisant le moteur
de `add_source_screen`. Badge RSS (vert / orange) ajouté sur la preview
d'ajout d'une source.

## PR associée

À créer via `/go` — base = `main`, branche
`boujonlaurin-dotcom/veille-v3-pr2-sources-quality`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Veille flow Step 3 (sélection sources) | `/veille/config` (étape 3) | Modifié |
| Sheet « Ajouter une source » (depuis Step 3) | (sheet) | Nouveau |
| Add source (catalogue global) | `/sources/add` | Refacto interne (UI ≃ inchangée) |
| Source detail modal (preview avant ajout) | (modale) | Modifié — badge RSS |

## Scénarios de test

### Scénario 1 : Step 3 — liste flat triée par pertinence (happy path)

1. Démarrer un nouveau flow Veille → choisir un thème (ex. « Tech »).
2. Step 2 : cocher quelques topics, optionnellement remplir un brief.
3. Step 3 : attendre le chargement des suggestions.

**Résultat attendu** :
- Une seule liste de sources (8–12 items typiquement), pas de section.
- Sous-titre « Classées par pertinence pour ta veille ».
- Les sources que l'utilisateur suit déjà ont un badge **CONFIANCE**.
- Toutes les cards ont un CTA « Connecter » (ou « Connectée » si pré-cochée).
- Pas d'overflow sur le bouton « Connectée » (viewport 390x844).

### Scénario 2 : Toggle Connecter / Connectée

1. Sur Step 3, tap sur « Connecter » d'une source non sélectionnée → devient
   « Connectée ».
2. Re-tap → repasse à « Connecter ».

**Résultat attendu** : compteur de sources reflète l'état, pas de glitch.

### Scénario 3 : Ajouter une source custom depuis Step 3 (happy path)

1. Sur Step 3, scroller jusqu'au bouton **« Ajouter une source »**.
2. Tap → un sheet s'ouvre (≈92% de la hauteur) avec champ de recherche +
   drag handle + bouton close.
3. Taper « next inpact » → résultats apparaissent.
4. Tap résultat → modale détail s'ouvre avec badge RSS.
5. Tap « Ajouter ».

**Résultat attendu** :
- Modale fermée, sheet fermé.
- La nouvelle source apparaît dans la liste Step 3, **pré-cochée**
  (« Connectée »).
- Pas de duplication si la source était déjà dans la liste.

### Scénario 4 : Badge RSS sur la preview

**Parcours A — RSS détecté** :
1. Step 3 → bouton « Ajouter une source ».
2. Coller une URL d'un média avec flux RSS (ex. `https://www.lemonde.fr`).
3. Tap résultat → preview.

**Résultat A** : pill **verte** « RSS détecté ».

**Parcours B — Pas de flux RSS** :
1. Idem avec une URL sans RSS.

**Résultat B** : pill **orange** « Pas de flux RSS — articles peuvent manquer ».

### Scénario 5 : Edge — fallback mock si API down

1. Couper la connexion / faire échouer `/veille/suggestions/sources`.
2. Atteindre Step 3.

**Résultat attendu** : message « Suggestions indisponibles, conserve ta
sélection. » + liste mock unique (followed + niche fusionnés). Les sources
mock followed (`s-lm`, `s-cp`, `s-tc`) ont un badge CONFIANCE.

### Scénario 6 : Add source screen catalogue (régression)

1. Ouvrir l'écran catalogue `/sources/add`.
2. Effectuer une recherche, ajouter une source.

**Résultat attendu** : comportement identique à avant la refacto. Le badge
RSS apparaît sur la preview.

## Critères d'acceptation

- [ ] Liste unique flat sur Step 3 (pas de section followed/niche).
- [ ] Sources `is_already_followed=true` → badge CONFIANCE.
- [ ] CTA « Connecter / Connectée » sans overflow.
- [ ] Bouton « Ajouter une source » ouvre un sheet avec drag handle + close.
- [ ] Source ajoutée via le sheet → pré-cochée dans Step 3.
- [ ] Badge RSS visible sur la preview source detail (vert ou orange).
- [ ] AddSourceScreen catalogue : aucune régression.

## Zones de risque

1. **State migration** : les tests `step1_5_preset_preview_screen_test`,
   `veille_config_provider_test`, `veille_models_test`,
   `veille_source_card_test` ont été adaptés. Le feed
   (`compact_source_chip.dart`, `feed_screen.dart`) utilise un nom homonyme
   `followedSources` mais NON-relié au state veille — vérifier en QA visuel
   que le feed n'est pas cassé.
2. **Preset application** : `applyPreset` place toutes les sources d'un
   preset dans `selectedSourceIds`, avec `kind='followed'` dans `sourcesMeta`.
   Le wire backend reste identique.
3. **Hydratation édition** : `hydrateFromActiveConfig` (mode édition d'une
   veille existante) préserve le `kind` côté `sourcesMeta`, donc
   l'aller-retour API doit rester stable.
4. **Bordure card Step 3** : la couleur dépend maintenant de
   `isAlreadyFollowed` (avant : `isNiche`).

## Dépendances

- API endpoint :
  - `POST /veille/suggestions/sources` — réponse changée
    `{sources: [...]}` (au lieu de `{followed, niche}`). Chaque item porte
    `is_already_followed: bool` + `relevance_score: float | None`.
- Backend tests : `test_veille_source_ingestion.py` +
  `test_veille_source_suggester_eval.py` (10 fixtures structurelles).
- Mobile tests : `flutter test` — 51 tests passants.
