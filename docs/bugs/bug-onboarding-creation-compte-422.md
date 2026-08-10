# Bug onboarding : création de compte refusée en 422

## Symptôme

La création du compte à la fin de l'onboarding échouait sur iOS et sur le web
avec le message générique « Une erreur est survenue ».

Les logs Supabase Auth montraient un `PUT /user` en 422 :

```text
Updating password of an anonymous user without an email or phone is not allowed
```

## Cause

L'onboarding utilise une session Supabase anonyme, ensuite convertie en compte
réel. La conversion envoyait d'abord le mot de passe, puis l'email. GoTrue
refuse de définir un mot de passe pour un utilisateur anonyme qui n'a encore ni
email ni téléphone. Le premier appel échouait donc systématiquement et le
second n'était jamais exécuté.

## Correction

La conversion suit désormais cet ordre :

1. ajout de l'email avec l'URL de redirection ;
2. ajout du mot de passe ;
3. persistance de `pending_email_confirmation` uniquement si
   `email_confirmed_at` est encore nul.

Avec `mailer_autoconfirm = true`, aucun marqueur d'attente n'est créé et
l'utilisateur continue directement vers la conclusion de l'onboarding. Avec
la confirmation activée, le marqueur reste persisté et le routage existant
conduit vers l'écran de confirmation.

Si l'email est ajouté mais que le mot de passe échoue, aucun marqueur de
confirmation n'est écrit, l'auto-création d'une nouvelle session anonyme est
désactivée, et un message explique que le mot de passe doit être réessayé ou
réinitialisé. Une nouvelle tentative détecte l'email déjà attaché et reprend
directement à l'ajout du mot de passe. L'erreur est aussi envoyée à Sentry avec
le tag `auth_event=anonymous_conversion_failed` et l'étape de conversion.

## Régression couverte

Les tests vérifient l'ordre email puis mot de passe, l'état après un échec
partiel et les traductions des erreurs GoTrue pertinentes, dont le message 422
exact, les variantes d'email déjà utilisé et la limite d'envoi d'emails.
