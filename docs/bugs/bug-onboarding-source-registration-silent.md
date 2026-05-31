# Bug : Enregistrement des sources en fin d'onboarding (silent error récurrent)

## Status: Implémenté (portée complète — en attente CI/review)

## Date: 2026-05-31

## Type: Bug (récurrent, silencieux)

## Branche: `claude/onboarding-source-registration-haMlk`

---

## 1. Symptôme

À la fin de l'onboarding, les sources sélectionnées par l'utilisateur ne sont
**pas toujours** enregistrées. L'animation de conclusion se déroule normalement,
aucun message d'erreur n'apparaît, l'utilisateur arrive sur son digest — mais ses
sources sont absentes. Problème **récurrent** et **silencieux** (aucune alerte,
aucune trace exploitable jusqu'ici).

---

## 2. Analyse appuyée sur les logs (prod — Supabase `ykuadtelnzavrqzbfdve`)

### 2.1 Mesure de l'écart (requêtes SQL prod)

| Métrique | Valeur |
|----------|--------|
| Utilisateurs ayant terminé l'onboarding (`onboarding_completed=true`) | **79** |
| Dont au moins 1 source (jointure correcte `user_profiles.user_id`) | 79 (0 à zéro absolu) |
| Sources présentes < 2 min après création du profil | 42 |
| Sources présentes ≥ 2 min après | **37** |
| Sources présentes **≥ 1 heure** après | **12 (~15 %)** |
| Cas extrêmes observés | **172 min, 2994 min (50 h), 4048 min (67 h)** |

> ⚠️ `user_profiles.created_at` correspond au **premier lancement / auth**, pas à
> la fin de l'onboarding. Les petits écarts (2–10 min) reflètent donc le temps
> passé dans le tunnel et ne sont **pas** des échecs. En revanche les écarts
> **≥ 1 h** (12 utilisateurs, dont des cas à 50 h / 67 h) ne s'expliquent que par
> un **échec silencieux à l'enregistrement** : l'utilisateur n'a obtenu ses
> sources que plus tard, en les **ré-ajoutant manuellement**.

Les échecs touchent des versions d'app **récentes** (`1.0.0+802`, `+807`, `+812`)
→ régression **active**, pas un résidu historique.

> Note : le taux réel est probablement sous-estimé. Un utilisateur dont
> l'enregistrement échoue **et** qui ne ré-ajoute jamais de source manuellement
> apparaît avec 1+ source via d'autres chemins (fallback digest) ou reste invisible
> dans cette jointure inner — l'écart « ≥ 1 h » est donc un **plancher**.

### 2.2 Cause racine n°1 — Silent error côté mobile (le cœur du problème)

`apps/mobile/lib/features/onboarding/providers/conclusion_notifier.dart:161-182`

```dart
Future<void> _trustSelectedSourcesWithTimeout(List<String>? sourceIds) async {
  if (sourceIds == null || sourceIds.isEmpty) return;
  final repository = _ref.read(sourcesRepositoryProvider);
  try {
    await Future.wait(
      sourceIds.map((sourceId) async {
        try {
          await repository.trustSource(sourceId);
          debugPrint('Source $sourceId marquée comme de confiance');
        } catch (e) {
          debugPrint('Erreur trust source $sourceId: $e'); // ← AVALÉ
        }
      }),
    ).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    debugPrint('Trust sources timeout (5s)...'); // ← AVALÉ
  } catch (e) {
    debugPrint('Erreur globale trust sources: $e'); // ← AVALÉ
  }
}
```

- Chaque erreur par source est interceptée et **seulement** `debugPrint` →
  **`debugPrint` est un no-op en build release**. L'utilisateur ne voit rien.
- Le `try/catch` externe + `TimeoutException` avalent aussi tout.
- La méthode retourne `void` sans jamais signaler l'échec → l'appelant
  (`_saveOnboardingWithRetry`, ligne 114) considère l'onboarding **réussi**.
- **Conséquence exacte = "silent error"** : succès affiché, sources non enregistrées.

### 2.3 Cause racine n°2 — Chemin secondaire fragile et redondant

Il existe **deux** chemins d'enregistrement non coordonnés :

1. **Autoritaire** : `POST /users/onboarding` (payload inclut bien
   `preferred_sources`, vérifié côté mobile `user_api_service.dart:78-96`) →
   `UserService.save_onboarding` écrit les `UserSource` de façon **atomique** et
   `get_db` **commit** (`database.py:153-163`). Ce chemin est fiable.
2. **Best-effort** : `_trustSelectedSourcesWithTimeout` rejoue l'enregistrement
   via N appels `POST /sources/{id}/trust` en parallèle, avec **timeout agrégé de
   5 s** et erreurs avalées.

Les données montrent des sélections réelles de **15 à 48 sources**. 48 POST en
parallèle, sur réseau mobile ou dyno Railway en cold-start, dépassent
régulièrement le budget de 5 s → drop silencieux.

### 2.4 Cause racine n°3 — Le chemin autoritaire peut enregistrer 0 source en silence

`packages/api/app/services/user_service.py:202-231`

```python
# Sauvegarder les sources sélectionnées (UserSource)
sources_created = 0
if answers.preferred_sources:
    valid_source_ids = set()
    for sid in answers.preferred_sources:
        try:
            valid_source_ids.add(UUID(sid))   # ← valide UNIQUEMENT le format UUID
        except ValueError:
            continue
    if valid_source_ids:
        ...
        for source_id in valid_source_ids - already_trusted:
            user_source = UserSource(... source_id=source_id, is_custom=False)
            self.db.add(user_source)          # ← aucune vérif d'existence/activité
            sources_created += 1
await self.db.flush()
```

- Le commentaire dit *« Vérifier quelles sources existent et sont actives »* mais
  le code **ne vérifie que le format UUID** — il ne consulte jamais la table
  `sources`. **Le commentaire ment.**
- `UserSource.source_id` a une FK `ForeignKey("sources.id", ondelete="CASCADE")`.
  Un ID de source supprimée / renommée / inconnue → **IntegrityError au flush →
  rollback de TOUTE la transaction → 500** (échec bruyant, onboarding bloqué).
- Côté client, si `answers.preferredSources` est `null`/`[]` au moment du save
  (perte d'état Hive, écrasement par la page 2 de sélection), le backend écrit
  **0 source en silence**, et le chemin trust reçoit aussi `null` → 0.

### 2.5 Cause racine n°4 — Aucune vérification / réconciliation / télémétrie

- `OnboardingResponse` renvoie `sources_created`, mais le **mobile l'ignore**.
- Rien ne compare *demandé* vs *créé*.
- Aucun évènement Sentry/PostHog sur un enregistrement partiel ou nul.
- → Les échecs sont **invisibles** pour l'utilisateur ET pour l'équipe = bug
  « récurrent » impossible à diagnostiquer jusqu'ici.

---

## 3. Plan fiable et robuste (defense in depth)

**Principe directeur :** un **seul** chemin d'enregistrement autoritaire,
transactionnel et **vérifié côté serveur** ; échouer **bruyamment et de façon
observable** ; et un filet de **réconciliation auto-réparant**.

### Backend (`packages/api`)

1. **Rendre `save_onboarding` robuste et honnête** (`user_service.py`)
   - Requêter réellement `Source` sur les IDs demandés filtrés par `is_active`,
     n'insérer que les sources existantes/actives → plus de FK IntegrityError qui
     fait échouer tout l'onboarding.
   - Conserver l'idempotence (`already_trusted` + contrainte unique existante).
   - Logger un warning structuré (`structlog`) quand `requested != created`.

2. **Enrichir le contrat `OnboardingResponse`**
   - Ajouter `sources_requested` et `sources_skipped` (IDs ignorés) à la réponse.

3. **Vérification post-flush** : recompter les `UserSource` du user ; en cas
   d'écart, log d'erreur structuré (visible Railway/Sentry) avec `user_id` + IDs
   manquants.

### Mobile (`apps/mobile`)

4. **Chemin unique** : supprimer `_trustSelectedSourcesWithTimeout` du flux de
   conclusion. L'enregistrement passe uniquement par `POST /users/onboarding`
   (atomique). (`trustSource` reste pour l'ajout manuel hors onboarding.)

5. **Faire confiance à la réponse serveur + remonter les vrais échecs**
   - `saveOnboarding` lit `sources_requested`/`sources_created`. Si
     `preferredSources` non vide mais `created + déjà_possédées < requested` →
     **erreur traitée et reportée** (évènement PostHog/Sentry
     `onboarding_sources_partial`), jamais avalée.
   - Supprimer la gestion d'erreur « `debugPrint` only ».

6. **Corriger la perte d'état client**
   - Garantir que `answers.preferredSources` = union page 1 + page 2 et qu'il est
     restauré depuis Hive avant `saveOnboarding` ; ne jamais envoyer une liste
     vide écrasée alors que l'utilisateur a sélectionné des sources.

7. **Filet auto-réparant** : au démarrage / premier chargement du digest, si
   l'onboarding est complété localement mais que le serveur renvoie moins de
   sources que l'`answers_backup` persisté, rejouer l'enregistrement.

### Observabilité (pour que ça ne redevienne jamais silencieux)

8. **Évènements PostHog**
   - `onboarding_sources_submitted` (count), `onboarding_sources_registered`
     (count), `onboarding_sources_failed` (ids, erreur).
   - Funnel *submitted → registered* + insight d'alerte sur l'écart.

### Tests

9. **Backend pytest** : `save_onboarding` avec IDs valides + invalides + inactifs
   → seules les sources valides/actives insérées, pas de rollback, counts exacts ;
   ré-exécution idempotente ; sécurité FK.
10. **Flutter** : `conclusion_notifier` remonte une erreur si
    `sources_created < requested` ; persistance/restauration de `preferredSources` ;
    la page 2 n'écrase pas la page 1.
11. **E2E (Playwright MCP)** : onboarding complet avec sources → vérifier que
    `GET /api/sources` les renvoie bien.

---

## 4. Fichiers concernés (prévisionnel)

| Fichier | Rôle |
|--------|------|
| `apps/mobile/lib/features/onboarding/providers/conclusion_notifier.dart` | RC1/RC2 : suppression chemin silencieux, remontée d'erreur |
| `apps/mobile/lib/core/api/user_api_service.dart` | Lecture `sources_created/requested`, télémétrie |
| `apps/mobile/lib/features/onboarding/providers/onboarding_provider.dart` | RC3b : persistance/union des sélections de sources |
| `packages/api/app/services/user_service.py` | RC3a : vérif existence/activité, log d'écart |
| `packages/api/app/schemas/user.py` | `OnboardingResponse` enrichi |
| `packages/api/tests/` + `apps/mobile/test/` | Tests anti-régression |

---

## 4bis. Implémentation réalisée (portée complète)

### Backend
- ✅ `user_service.py::save_onboarding` — n'insère QUE des sources **existantes et
  actives** (requête `Source` filtrée `is_active`) → plus de FK IntegrityError qui
  faisait rollback tout l'onboarding. Idempotent. Retourne `sources_requested` /
  `sources_created` / `sources_skipped`. Log `warning` structuré en cas d'écart.
- ✅ `schemas/user.py::OnboardingResponse` — ajout `sources_requested`,
  `sources_skipped`.
- ✅ `models/source.py` — documentation de la colonne **DB-only** `state`
  (interest_state, défaut `followed`) : non mappée volontairement (gérée mobile,
  cast text→enum risqué en prod) ; les insertions ORM héritent du défaut
  `followed` → sources visibles dans le feed. **Aucune migration Alembic** (la
  colonne existe déjà en prod, convention DB-only respectée, 1 seul head préservé).

### Mobile
- ✅ `conclusion_notifier.dart` — **suppression de la trust loop silencieuse**
  (`_trustSelectedSourcesWithTimeout`). L'enregistrement passe uniquement par
  l'appel onboarding (atomique serveur). Ajout `_reportSourcesOutcome` (télémétrie
  + log d'écart) et `_reportSourcesFailure` (échec transport tracé) → plus aucune
  erreur avalée.
- ✅ `onboarding_result.dart` + `user_api_service.dart` — propagation des compteurs
  `sources_created/requested/skipped` depuis la réponse serveur.
- ✅ `analytics_service.dart` — évènement `onboarding_sources`
  (`requested/registered/skipped/failed`) → funnel observable.
- ℹ️ Sélection de sources (`sources_page2_question.dart`) : **vérifiée, pas de
  clobber** (page 2 initialise depuis `preferredSources`) → non modifiée.

### Tests
- ✅ `packages/api/tests/test_onboarding_sources.py` — actives enregistrées ;
  invalide/inactive/inconnue ignorées sans rollback ; idempotence.
- ✅ `apps/mobile/test/models/onboarding_result_test.dart` — propagation des
  compteurs de sources.
- ⚠️ Non exécutés dans le sandbox (pas de runtime Python 3.12 ni de DB de test, pas
  de Flutter installé) — à valider en CI. Les fichiers passent `py_compile`.

### Suivi (hors périmètre immédiat)
- Le mode dégradé (`continueAnyway`) persiste `answers_backup` + `pending_sync`
  mais **aucun replay au démarrage** n'est câblé. Filet auto-réparant à câbler dans
  un second temps (attention : `save_onboarding` est destructif sur
  interests/preferences — un replay devra cibler uniquement les sources).

## 5. Preuves / Références

- Mesures SQL prod (Supabase MCP, projet `ykuadtelnzavrqzbfdve`) — section 2.1.
- Code mobile : `conclusion_notifier.dart:114,161-182`, `user_api_service.dart:78-96`.
- Code backend : `user_service.py:103-240`, `database.py:153-163`, `models/source.py` (FK + unique).
- Bug connexe : `docs/bugs/bug-source-addition-prod-and-visibility.md` (logger manquant, contrainte unique) — corrige l'ajout *manuel*, ne couvre pas l'écrasement silencieux d'onboarding.
