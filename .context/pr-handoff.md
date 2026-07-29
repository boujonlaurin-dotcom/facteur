# feat(activation): onboarding sans compte — session anonyme convertie à `finalize` (story 31.1)

## Pourquoi

Funnel prod 90 j : **37 % seulement des installs créent un compte**. 82 installs sur 130 (63 %)
n'émettent aucun event produit — médiane 162 secondes, 1 jour d'activité, **0 % de rétention à J1,
J7 et J30**. En face, les 48 activés se rétiennent très bien (J7 77 %, J30 67 %) et l'onboarding
lui-même se termine à 91 %. Le produit ne perd pas ses utilisateurs à l'usage, il les perd avant :
un nouvel install tombait **directement sur `/login`**, zéro exposition produit avant de devoir
créer un compte puis confirmer son email.

Doc : `docs/stories/core/31.1.onboarding-sans-compte.md`. C'est la PR 1 sur 3 du plan d'activation,
celle qui porte l'essentiel du gain ; à mesurer seule avant les deux autres.

## Ce que fait la PR

Le premier lancement ouvre une **session anonyme Supabase** au lieu de rediriger vers `/login`.
L'utilisateur déroule les 13 étapes, et le compte se crée à `finalize` — sur le **même `user.id`**,
donc thèmes, sous-sujets et sources choisis avant le compte restent attachés. Aucun endpoint
dupliqué, aucun buffer local : les écrans `sources` / `swipe` / `subtopics` continuent d'appeler les
endpoints authentifiés existants avec un vrai JWT.

**Mobile**
- `auth_state.dart` : `isAnonymous`, `signInAnonymously()` au cold boot, `convertAnonymousToAccount()`
  (password puis email, sans jamais vider les box locales), `pendingEmailConfirmation` persisté en
  Hive pour survivre à un kill entre conversion et confirmation.
- `routes.dart` : la garde « email non confirmé » se tait pour une session anonyme (et, après
  conversion, le temps que l'écran de conclusion enregistre le profil) ; `/login` reste accessible
  via « J'ai déjà un compte ». Gardes 2b (splash / FLUTTER-2), 5 et 6 intactes.
- `finalize_question.dart` : création de compte (email + mot de passe) ou lien vers `/login`.
- **Instrumentation** : `onboarding_started` / `step_viewed` / `step_completed` / `completed` sur les
  13 étapes (une seule en émettait un jusqu'ici). `$identify` n'est plus émis pour une session
  anonyme — un event `account_created` porte désormais la mesure d'activation.

**Backend**
- `dependencies.py` : accepte le claim `is_anonymous` (et le lit en fallback DB). La garde 403
  historique est inchangée pour un compte réel non confirmé.
- `jobs/purge_anonymous_users.py` (+ scheduler, 4h15 Paris) : supprime les anonymes dont l'onboarding
  n'a pas abouti et inactifs > 30 j, sinon `auth.users` enfle d'une ligne par install.

**Aucune migration Alembic.**

## Points d'attention pour la review

- **Le critère de purge n'est pas « aucun profil »** : les endpoints d'onboarding appellent déjà
  `get_or_create_profile` (c'est ce qui satisfait les FK de `user_subtopics` / `user_interests`), donc
  un profil existe souvent bien avant la fin du parcours. Seul `onboarding_completed = false`
  distingue un abandon.
- **Garde anti-régression** : `_noteRealAccount()` coupe l'auto-signin anonyme dès qu'un vrai compte
  est observé (boot + listener Supabase), pas seulement aux chemins explicites — sinon un login OAuth
  ou une session expirée renverrait un utilisateur historique dans un onboarding vierge.
- `is_anonymous` reste `true` entre la conversion et la confirmation de l'adresse : c'est
  `pendingEmailConfirmation`, persisté, qui marque « le compte existe ».

## À faire côté PO avant merge (dashboard Supabase, hors repo)

1. Activer les **anonymous sign-ins** (Authentication → Providers → Anonymous). Sans ça, le boot
   retombe proprement sur `/login` (comportement actuel), mais la PR n'a aucun effet.
2. Vérifier qu'aucune policy RLS n'expose de données à une session anonyme au-delà de son `auth.uid()`.

## Vérification

- `pytest` (backend) et `flutter test` / `flutter analyze` (mobile) au vert ; baseline mobile connue
  de ~27 échecs préexistants inchangée.
- Nouveaux tests : `tests/test_auth_anonymous_sessions.py`, `tests/test_purge_anonymous_users.py`,
  `test/features/onboarding/onboarding_sans_compte_test.dart`.
- Parcours web complet (premier lancement sans compte → 13 étapes → création du compte → thèmes,
  sous-sujets et sources bien présents après) : à repasser sur staging une fois les anonymous
  sign-ins activés.

**Mesure de succès (6 semaines)** : install → `account_created` de 37 % à 60 %, et apparition d'un
funnel d'étapes exploitable dans PostHog.
