# Bug: coche de lecture non fonctionnelle sur "Ton Essentiel"

## Statut
- [x] En cours de correction
- [x] Corrigé (date: 2026-07-22)

## Sévérité
🟠 Majeur — UX cassée sur la surface la plus vue de l'app (carte "Ton Essentiel"), sans perte
de données (le statut lu est bien persisté côté backend, seul l'affichage/la persistance
visuelle échoue).

## Description

La coche de lecture (checkmark vert, `_ReadCheckBadge`) ne s'active pas — ou disparaît quasi
immédiatement — pour les articles ouverts depuis la carte "Ton Essentiel", alors que le même
indicateur fonctionne correctement sur les autres sections du flux (Tournée, Actus du jour).

## Étapes de reproduction

1. Ouvrir l'app, lire un article depuis la carte "Ton Essentiel" (rester > 1s pour déclencher
   le marquage lu).
2. Revenir au flux — la coche s'affiche correctement en mémoire (comportement attendu, non cassé).
3. Fermer l'app (ou la laisser en arrière-plan assez longtemps pour que l'OS tue le process —
   très courant sur mobile) puis la rouvrir.
4. **Constat** : l'article lu n'est plus visible du tout dans la carte "Ton Essentiel" — il a
   été remplacé par un autre article, non lu, sans coche. L'utilisateur a l'impression que la
   lecture n'a jamais été enregistrée.

## Cause racine

Deux mécanismes se combinent :

1. **Éviction systématique des articles lus côté backend.** `build_essentiel_response_with_supplements`
   (`packages/api/app/services/essentiel_service.py:906-979`, feature "Essentiel vivant", story 9.8)
   évince de la réponse tout article `is_read=True` à **chaque** appel `GET /api/essentiel`
   (`non_read = [a for a in response.articles if not a.is_read]`, ligne 933) et le remplace par
   du contenu frais. Contrairement au digest classique (Tournée/Actus, généré une fois/nuit,
   liste stable, seul le flag `is_read` bascule), Essentiel fait disparaître l'article de la
   réponse dès qu'il est lu.

2. **Ce refetch se produit bien plus souvent que prévu par le design.**
   `fluxContinuProvider.build()` (`apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart:340-386`)
   appelle **inconditionnellement** `_fetchAll()` (ligne 382) après avoir peint le cache du
   jour — donc à **chaque cold start** de l'app (relance après fermeture ou kill OS en
   arrière-plan), **sans aucun cooldown**. Ce chemin contredit l'intention documentée du
   cooldown existant `essentielForegroundRefreshCooldown` (2 min,
   `apps/mobile/lib/features/flux_continu/screens/flux_continu_screen.dart:104-117` : *"un
   aller-retour éclair ... ne DOIT pas recharger le feed et coûter à l'utilisateur le fil de sa
   progression"*) — ce cooldown ne protège que le chemin `didChangeAppLifecycleState`
   (foreground-resume en process vivant), jamais le cold-start SWR de `build()`.

Résultat : dans l'usage réel (app fermée/tuée entre deux sessions, extrêmement fréquent sur
mobile), le premier `GET /api/essentiel` qui suit une lecture évince quasi systématiquement
l'article lu avant que l'utilisateur n'ait l'occasion de revoir sa coche persister.

Le pipeline générique de marquage lu (`ContentDetailScreen` → `ReadSyncService.markConsumed` →
`fluxContinuProvider.markArticleRead()` → `POST /contents/{id}/status` →
`UserContentStatus`) a été vérifié et fonctionne correctement — aucun bug de déclenchement ou
de persistance dans ce pipeline. Un refetch immédiat post-lecture (au retour du reader) a
également été envisagé puis infirmé par le code (`markArticleRead` est une mutation d'état pure
sans effet réseau, aucun provider ne `watch` l'état de lecture pour se relancer).

## Solution

Fenêtre de grâce backend : un article marqué lu il y a moins de
`ESSENTIEL_READ_EVICTION_GRACE` (30 min) reste traité comme non-évictable dans
`build_essentiel_response_with_supplements`, même si `is_read=True` — sa coche reste donc
visible sur les refetch qui suivent une lecture récente (cold start, pull-to-refresh, retour
foreground). Passé ce délai, le comportement actuel (éviction + remplacement par du contenu
frais) reprend, préservant l'intention originale de "Essentiel vivant au retour" pour les
retours après une vraie absence.

Le timestamp `UserContentStatus.seen_at` (déjà posé de façon idempotente à la première
transition vers `CONSUMED`) est remonté jusqu'à `EssentielArticle.read_at` via
`_get_batch_action_states` → `DigestTopicArticle.read_at` → `EssentielArticle.read_at`. Aucune
migration Alembic requise (aucun changement de schéma DB). Aucune modification Flutter requise
(le rendu de la coche fonctionne déjà dès que `is_read=true` est présent dans la réponse).

Détail d'implémentation : voir plan associé (fichiers modifiés : `digest_service.py`,
`schemas/digest.py`, `schemas/essentiel.py`, `essentiel_service.py`, tests dans
`test_essentiel_supplements.py` et `test_digest_service.py`).
