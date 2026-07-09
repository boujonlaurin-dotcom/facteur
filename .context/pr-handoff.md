## fix(veille): sauver le sujet « Autre », reset propre au changement de thème + réparer changelog.json

Suite front de l'audit veille (PR #941). Couvre §2 (MUST) + §3 (NICE) du plan ; §4 (SHOULD) différé en PR séparée.

### §2 — « mon sujet n'est pas sauvegardé » (root cause soumission)
Sur le chemin thème **« Autre »**/free-text, `mainTopicSlug` restait `null` : `_buildUpsertRequest` n'émettait alors **aucun topic en position 0**, donc aucun sujet principal structuré n'était jamais persisté en DB (seul `editorial_brief` survivait, rien à restaurer au reload).
- `setCustomThemeLabel()` dérive désormais `mainTopicSlug`/`mainTopicLabel` (`custom-<slug>`) du label saisi, et seede le label complet comme mot-clé multi-mots (signal de matching qui échappe au denylist backend).
- `hydrateFromActiveConfig()` restaure `customThemeLabel` depuis `theme_label` pour un thème « Autre » → round-trip complet (le champ du Step 1 ne réapparaît plus vide).
- Effet de bord positif : renforce le gate topic-axis backend (davantage de configs avec un `mainTopicSlug` structuré).

### §3 — changer de thème = décochage manuel pénible (feedback PO)
`selectTheme()` ne réinitialisait que les topics ; angles/sources/mots-clés de l'ancien thème restaient cochés. Étendu pour vider `selectedSuggestions`/`selectedSourceIds`/`sourcesMeta`/`keywords`/`angleKeywords` et réarmer `angle/sourceSuggestionsRequested` (refetch des suggestions du nouveau thème sur Steps 2/3).

### Bonus — changelog.json invalide sur `main`
`assets/changelog.json` était **JSON invalide sur origin/main** (collision de merge #939/#940/#941 : 3 paires tag/summary fusionnées dans un seul objet) → « Quoi de neuf » cassé au runtime, non détecté car la CI ne joue pas `flutter test`. Réparé (3 objets distincts) + entrée Veille pour cette PR.

### Hors scope (suivi)
- §4 (SHOULD) suggérer des sources dans l'empty-state veille : **aucun endpoint d'ajout incrémental de source** n'existe → nécessite un upsert partiel ou provider+`submit()`, PR séparée.

### Vérification
- `flutter test test/features/veille/` OK + `test/features/release_notes/` OK (changelog asset re-valide)
- `veille_config_provider_test.dart` : +5 cas (dérivation slug, effacement, submit topic position-0 custom, hydrate customThemeLabel, reset+réarme au changement de thème) — 34/34 pass
- `flutter analyze` fichiers modifiés : No issues found
