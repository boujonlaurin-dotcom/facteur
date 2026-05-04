# QA Handoff — Lettre 2 « Tes premières lectures » (Story 19.1, PR4)

> Rempli par l'agent dev en fin de développement, après validation du PO.
> Sert d'input à `/validate-feature`.

## Feature développée

Remplace la Lettre 2 placeholder (1 action `set_frequency`) par 5 actions auto-détectées qui marquent un J+1 d'usage naturel : lire L'essentiel, lire Les bonnes nouvelles, lire 3 articles jusqu'au bout, consommer une vidéo/podcast (≥4min), recommander un article (like 🌻). Ajout d'une dimension narrative anti-FOMO : `intro_palier` (lettre), `completion_palier` (toast par action), `completion_voeu` (overlay cachet final). Aucun chiffre, aucune comparaison sociale, un seul toast à la fois.

## PR associée

À créer après validation QA (cible `main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed (carrousel haut) | `/feed` | Modifié — 2è carte « Bonnes nouvelles » émet désormais un event |
| Liste des lettres (Mon Courrier) | `/lettres` | Inchangé visuellement |
| Lettre ouverte (L2) | `/lettres/letter_2` | Modifié — nouveau message, 5 actions, intro_palier, toasts paliers |
| Overlay cachet final | (overlay sur `/lettres/letter_2` quand archivée) | Modifié — affiche `completion_voeu` au lieu du fallback |

## Scénarios de test

### Scénario 1 — Forme de la Lettre 2 ouverte (état initial)
**Parcours** :
1. Provisionner un user avec L2 active (DB ou faire passer par le chaînage L1→L2 standard).
2. Naviguer vers `/lettres` puis ouvrir Lettre 2.
**Résultat attendu** :
- Titre « Tes premières lectures ».
- Message principal en 2 paragraphes.
- Sous le dernier paragraphe : phrase italique secondaire (`intro_palier`) « Ta sélection est posée. Voyons maintenant si tu sais en faire bon usage. »
- 5 actions visibles : Lire L'essentiel / Découvrir Les bonnes nouvelles / Lire 3 articles jusqu'au bout / Écouter un podcast ou regarder une vidéo / Recommander un article.
- Compteur en haut « 0/5 ».

### Scénario 2 — Action « Lire L'essentiel » détectée
**Parcours** :
1. Sur `/lettres/letter_2` ouverte, retour au feed.
2. Tap sur la carte « L'essentiel du jour ».
3. Revenir aux lettres et rouvrir Lettre 2.
**Résultat attendu** :
- L'action « Lire L'essentiel du jour » apparaît cochée (strikethrough).
- Compteur « 1/5 ».
- Toast bottom (Fraunces italique) « Premier rendez-vous tenu. Ça commence ici. » s'affiche brièvement (≈4s).

### Scénario 3 — Action « Bonnes nouvelles » détectée
**Parcours** :
1. Sur le feed, tap sur la 2è carte du carrousel « Les bonnes nouvelles ».
2. Revenir aux lettres et rouvrir Lettre 2.
**Résultat attendu** :
- L'action « Découvrir Les bonnes nouvelles » cochée.
- Toast « Tu sais maintenant que la lecture peut aussi faire du bien. ».

### Scénario 4 — Action « 3 articles jusqu'au bout »
**Parcours** :
1. Lire 3 articles de type `article` jusqu'au bout (scroll ≥90 % et passer ≥60 s sur chacun).
2. Revenir aux lettres et rouvrir Lettre 2.
**Résultat attendu** :
- Action cochée.
- Toast « Trois lectures menées au bout. C'est ce qui te distingue déjà. ».
- Note : si 2 articles seulement OU 1 article avec time_spent <60s → action **non cochée** (régression à éviter).

### Scénario 5 — Action « Vidéo / podcast »
**Parcours** :
1. Ouvrir un contenu de type `youtube` ou `podcast`, le consommer ≥4 minutes (240 s cumulés serveur).
2. Rouvrir Lettre 2.
**Résultat attendu** :
- Action cochée.
- Toast « Tu varies les formats. C'est comme ça qu'on s'enrichit. ».

### Scénario 6 — Action « Recommander un article »
**Parcours** :
1. Sur n'importe quel article, tap sur le bouton like (🌻).
2. Rouvrir Lettre 2.
**Résultat attendu** :
- Action cochée.
- Toast « Un signal envoyé. Le Facteur écoute. ».

### Scénario 7 — Anti-cascade (rafale)
**Parcours** :
1. Pré-remplir 4/5 actions L2 hors session.
2. Ouvrir Lettre 2 (snapshot initial = 4 done).
3. Déclencher la 5è action depuis l'écran.
**Résultat attendu** :
- L'overlay cachet final s'affiche avec `completion_voeu` (« Tu as appris à lire avec attention. C'est déjà beaucoup. La suite peut attendre. »).
- **Aucun toast palier** ne s'affiche en plus (l'overlay remplace le dernier toast).

Variante : 2 actions complétées simultanément (refresh + 2 nouveaux done) → **un seul toast** s'affiche (celui de la dernière action de la rafale), pas 2.

### Scénario 8 — Anti-FOMO (vérification visuelle)
**Parcours** :
1. Inspecter visuellement Lettre 2 dans tous ses états (todo, partiellement done, archivée).
2. Inspecter le toast palier et l'overlay cachet.
**Résultat attendu** :
- **Aucun pourcentage** affiché (pas de « 60 % » ni « top 10 % »).
- **Aucun classement** ni comparaison sociale (pas de « comme 80 % des utilisateurs »).
- **Aucun chiffre de performance** dans les wordings (le « 1/5 » du compteur d'actions reste OK, c'est neutre).
- Grep automatisé : `grep -rE '\b\d+\s?%|percentile|classement|comme \d+%' apps/mobile/lib/features/lettres/ packages/api/app/services/letters/` doit retourner 0 résultat.

## Critères d'acceptation

- [ ] L2 active retourne 5 actions, `intro_palier` non vide, `completion_voeu` non vide.
- [ ] Chaque action a un `completion_palier` non vide.
- [ ] Les 5 détecteurs s'évaluent correctement (cf. tests `TestLetter2Detection`).
- [ ] L1 ne contient PAS les champs narratifs L2 (régression backward-compat).
- [ ] L2 archivée reste archivée après refresh (idempotence).
- [ ] Toast s'affiche bottom 32, fade in/out 250 ms, hold 4 s, max 2 lignes.
- [ ] Anti-cascade : rafale de 2+ actions done = 1 seul toast.
- [ ] Complétion totale : overlay cachet à la place du toast.
- [ ] Aucune stat chiffrée dans les wordings.

## Zones de risque

- **`reading_progress` côté serveur** : la détection « 3 articles jusqu'au bout » dépend du PATCH `POST /contents/{id}/status` (`feed_repository.dart:824`) qui est fire-and-forget. Si l'utilisateur ferme l'app avant le sync, l'action peut tarder à se cocher. Pas un bug — c'est cohérent avec la détection backend.
- **Listener `_seenDoneActionIds`** : le snapshot est par-instance d'écran. Si l'utilisateur quitte puis ré-ouvre Lettre 2, le snapshot est refait → pas de toast pour les actions déjà done avant la session. Comportement voulu.
- **Wording éditorial** : les 7 chaînes (`intro_palier`, `completion_voeu`, 5 × `completion_palier`) sont rédigées par l'agent dans l'esprit Facteur, à valider par PO avant merge.

## Dépendances

- Endpoints réutilisés (aucun nouveau) : `POST /analytics/events`, `POST /contents/{id}/status`, `POST /contents/{id}/like`.
- Migration DB : aucune.
- Models touchés : `Letter`, `LetterAction` (mobile, +3 champs nullable).

## Tests automatisés

- Backend : `pytest tests/routers/test_letters_routes.py` → 20/20.
- Mobile : `flutter test test/features/lettres/` → 34/34 (incluant `palier_toast_test`, `letter_test` backward-compat).
- Suite mobile complète : 543 passed / 37 failed — les 37 failures sont pré-existantes sur staging, sans rapport avec L2 (vérifié par stash + run baseline).
