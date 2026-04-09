# PR — Personnalisation des sujets sensibles (mode Serein)

## Quoi
Permet à chaque utilisateur de définir ses propres "sujets sensibles" dans le mode Serein, en plus des 4 thèmes exclus par défaut (society, international, economy, politics). L'UI est exposée à deux endroits : une étape conditionnelle dans l'onboarding (si et seulement si l'utilisateur choisit "Rester serein") et une section dans l'écran Mes Intérêts des settings.

## Pourquoi
Le filtre Serein était identique pour tous les utilisateurs. Certains veulent éviter la tech, le sport ou l'économie — sujets non anxiogènes par défaut mais qui peuvent l'être selon le contexte personnel. Cette feature donne à l'utilisateur le contrôle sur ce qu'il considère "stressant".

## Fichiers modifiés

### Backend
- `packages/api/app/schemas/user.py` — Ajout champ `sensitive_themes: list[str] | None` dans `OnboardingAnswers`
- `packages/api/app/services/user_service.py` — Persistance de `sensitive_themes` (JSON serialize) dans la boucle upsert de préférences onboarding
- `packages/api/app/services/recommendation/filter_presets.py` — `apply_serein_filter()`, `_legacy_serein_keyword_filter()`, `is_cluster_serein_compatible()` acceptent `sensitive_themes` (union avec `SEREIN_EXCLUDED_THEMES`)
- `packages/api/app/services/recommendation_service.py` — Charge `sensitive_themes` depuis `user_prefs` et passe au filtre (feed)
- `packages/api/app/services/digest_selector.py` — Param propagé dans `select_for_user()` → `_get_candidates()` → 2 appels `apply_serein_filter`
- `packages/api/app/services/digest_service.py` — Charge `sensitive_themes` (requête DB) dans `get_or_create_digest()`, passe à `select_for_user()` et `_get_emergency_candidates()` (3 appels)
- `packages/api/app/services/topic_selector.py` — Param propagé jusqu'à `is_cluster_serein_compatible()`
- `packages/api/tests/test_serein_filter.py` — 9 nouveaux tests (4 DB-backed + 5 unitaires)

### Mobile
- `apps/mobile/lib/features/onboarding/providers/onboarding_provider.dart` — Champ `sensitiveThemes` dans `OnboardingAnswers`, enum `Section2Question.sensitiveThemes`, navigation conditionnelle dans `selectDigestMode()`, méthode `selectSensitiveThemes()`, back navigation ajustée
- `apps/mobile/lib/features/onboarding/screens/questions/sensitive_themes_question.dart` (**NOUVEAU**) — Écran chips thèmes, bouton "Continuer sans filtrer" / "Filtrer N thèmes"
- `apps/mobile/lib/features/onboarding/screens/onboarding_screen.dart` — Case `sensitiveThemes` dans `_buildSection2Content()`
- `apps/mobile/lib/features/onboarding/onboarding_strings.dart` — 4 nouvelles constantes
- `apps/mobile/lib/core/api/user_api_service.dart` — `sensitive_themes` dans `_formatAnswersForApi()`
- `apps/mobile/lib/features/digest/providers/sensitive_themes_provider.dart` (**NOUVEAU**) — StateNotifier fire-and-forget avec `toggle()`, `loadIfNeeded()`, `initFromApi()`
- `apps/mobile/lib/features/digest/repositories/digest_repository.dart` — Ajout `getPreferences()` (GET /users/preferences)
- `apps/mobile/lib/features/custom_topics/screens/my_interests_screen.dart` — Section `_SensitiveThemesSection` (visible uniquement si serein activé)

## Zones à risque

- **`apply_serein_filter()`** — Appelé dans 6 endroits distincts (feed + digest + emergency candidates). La signature a changé mais tous les callers ont été mis à jour avec `sensitive_themes=None` par défaut (rétro-compatible).
- **`digest_service.py` `get_or_create_digest()`** — Ajoute une requête DB supplémentaire par digest pour charger `sensitive_themes`. Faible impact (requête sur index primaire `user_id + preference_key`), mais à noter si la latence du digest devient sensible.
- **Navigation onboarding conditionnelle** — `section2QuestionCount` passe de 5 à 6, ce qui affecte la barre de progression (légère). La question `sensitiveThemes` ne s'affiche qu'en mode serein ; en mode "pour_vous", l'utilisateur passe de `digestMode` directement à Section 3 (comme avant). Le back-navigation depuis Section 3 est ajusté en conséquence.

## Points d'attention pour le reviewer

1. **Stockage JSON dans une colonne `string`** — `sensitive_themes` est sérialisé en `'["tech","sport"]'` dans `user_preferences` (key-value existant). Pas de migration Alembic. Cohérent avec le pattern existant, mais le parsing JSON doit être robuste si la valeur est corrompue — actuellement un `json.loads()` non protégé côté backend dans `digest_service.py`. Edge case si la préférence est malformée.

2. **`loadIfNeeded()` dans le provider mobile** — La première ouverture de "Mes Intérêts" en mode serein déclenche un GET `/users/preferences` en background. Pas de loading state affiché (chips restent vides jusqu'au retour API). Choix délibéré pour ne pas bloquer l'UI (same pattern que serein toggle).

3. **Section2Question count = 6 mais totalSteps = 16** — Les non-serein utilisateurs sautent `sensitiveThemes`, donc ils ont un total effectif de 15 étapes, mais `totalSteps` est 16. La barre de progression fait un micro-saut entre `digestMode` et Section 3. Acceptable UX, mais à valider visuellement.

4. **`is_cluster_serein_compatible()`** — La fonction est appelée synchroniquement dans `_score_clusters()` avec `sensitive_themes` passé en paramètre. Le param est propagé depuis `select_for_user()` mais n'est pas chargé à l'intérieur du `TopicSelector` lui-même — il dépend du caller (`DigestSelector`) pour le passer correctement.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`SEREIN_EXCLUDED_THEMES`** — Liste hardcodée inchangée. Les `sensitive_themes` s'y ajoutent par union, ne la remplacent pas.
- **`SEREIN_KEYWORDS`** — Inchangé. Les mots-clés anxiogènes sont toujours appliqués indépendamment des thèmes.
- **`Content.is_serene`** — La priorité LLM (is_serene=True passe toujours, is_serene=False est toujours exclu) est inchangée. `sensitive_themes` n'affecte que le fallback legacy (is_serene=NULL).
- **`DualDigestResponse`** — Pas modifié. `sensitive_themes` n'est pas retourné dans la réponse du digest (chargé séparément côté mobile via `loadIfNeeded()`).
- **Alembic** — Aucune migration. La table `user_preferences` existante est réutilisée (key-value).

## Comment tester

### Backend
```bash
cd packages/api

# Tests unitaires (sans DB)
.venv/bin/python -m pytest tests/test_serein_filter.py::TestIsClusterSereinCompatibleSensitiveThemes -v
# → 5 tests doivent passer

# Tests d'intégration (nécessite Supabase local)
.venv/bin/python -m pytest tests/test_serein_filter.py -v
```

**Test manuel API :**
```bash
# 1. Mettre à jour les sujets sensibles
curl -X PUT /api/users/preferences \
  -H "Authorization: Bearer <token>" \
  -d '{"key": "sensitive_themes", "value": "[\"tech\",\"sport\"]"}'

# 2. Vérifier GET /api/users/preferences contient sensitive_themes
curl /api/users/preferences -H "Authorization: Bearer <token>"

# 3. Vérifier que le digest serein exclut les articles tech/sport
#    (appeler GET /api/digest?serein=true et inspecter les sources des articles retournés)
```

### Mobile

**Onboarding serein :**
1. Lancer l'app → Refaire l'onboarding (Settings → Refaire le questionnaire)
2. Section 2 → choisir "Oui, rester serein"
3. L'écran "Sujets sensibles" doit apparaître avec 9 chips
4. Sélectionner quelques thèmes → bouton "Filtrer N thèmes"
5. Vérifier que `PUT /api/users/preferences` avec `key=sensitive_themes` est appelé (Charles/Proxyman)

**Onboarding non-serein :**
1. Même flow → choisir "Non, tout voir"
2. L'écran "Sujets sensibles" NE DOIT PAS apparaître
3. Navigation directe vers Section 3 (thèmes)

**Back navigation :**
1. Onboarding serein → arriver sur l'écran thèmes (Section 3, index 0)
2. Appuyer retour → doit revenir sur "Sujets sensibles", PAS "digestMode"

**Settings Mes Intérêts :**
1. Activer le mode serein (toggle dans le digest)
2. Aller dans Settings → Mes Intérêts
3. Section "SUJETS SENSIBLES" doit apparaître en bas (avec icône serein verte)
4. Chips pré-remplies avec les préférences existantes (GET `/users/preferences` appelé)
5. Toggler un thème → `PUT /api/users/preferences` avec `sensitive_themes` mis à jour (fire-and-forget)
6. Désactiver le mode serein → Section disparaît
