## Lettres : throttle bandeau + complétion d'action monotone

Deux régressions distinctes de la feature « Lettres du Facteur ».

### 1. Bandeau bruyant (mobile) — throttle 7 jours
`LettresNotificationBanner` réapparaissait à chaque ouverture d'app tant qu'une lettre était
active (dismiss session-only, jamais persisté). Ajout d'une persistance SharedPreferences
(`lettres_banner_last_shown_v1`, epoch ms) : **max 1 affichage / 7 jours**, le timestamp étant
écrit dès le 1er affichage visible de la session (couvre « affiché puis ignoré » ET « affiché
puis dismiss »). Pattern repris de `nudge_storage.dart`.

### 2. Complétion d'action non-monotone (backend) — fix générique
`refresh_letter_status` remplaçait `completed_actions` par le résultat live des détecteurs → une
action déjà validée régressait si l'état live repassait sous le seuil (ex. `_detect_mute_3_sources`
compte `cardinality(muted_sources)` : dé-masquer sous 3 décochait l'action). Fix au **niveau
générique du refresh** : union de l'état persisté (`completed_actions` = « ever reached ») avec le
recompute live → monotone pour **toutes** les actions (mutes, suivis, etc.). Les détecteurs restent
purs. **Aucune migration** (le champ JSONB persiste déjà l'état).

### Diagnostic compte PO (Supabase read-only)
`boujon.laurin@gmail.com` (user `d47836da-9aa9-4235-ac40-061c5c0ead48`) : `muted_sources = []`
(count 0), `letter_3` en statut `upcoming`, `completed_actions = []`. La régression `mute_3_sources`
n'a donc **jamais été déclenchée** sur son compte (letter_3 pas active, 0 mute) : bug latent pour
lui, réel pour tout user qui dé-masque après avoir atteint 3 sources.

### Fichiers
- `packages/api/app/services/letters/service.py` — union monotone dans `refresh_letter_status`
- `packages/api/tests/routers/test_letters_routes.py` — `test_completed_action_is_monotone`
- `apps/mobile/lib/features/lettres/widgets/lettres_notification_banner.dart` — throttle prefs
- `apps/mobile/test/features/lettres/widgets/lettres_notification_banner_test.dart` — 3 tests throttle
- `apps/mobile/assets/changelog.json` — entrée `Lettres` + fix corruption JSON de fusion (#924/#925)

### Vérif
- Mobile : 7/7 tests du bandeau verts + `flutter analyze` clean.
- Backend : syntaxe OK ; tests DB (`test_completed_action_is_monotone` + suite letters) à valider
  en CI — pas de Postgres test local en Conductor (OrbStack down).
- Alembic : 1 head inchangé, aucune migration.
