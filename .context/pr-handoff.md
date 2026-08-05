# feat(essentiel) : le tri dans le feed — carte « Ton Essentiel » triable au swipe (33.1)

Base `main`. **Une migration Alembic** (`tr01_essentiel_triage_decisions`, additive).
Backend + mobile. Story : `docs/stories/core/33.1.tri-dans-le-feed.md`.

## Quoi

La carte « Ton Essentiel » en tête du Flux continu n'est plus une liste passive :
elle devient une **pile à trier**. Un article à la fois — swipe droite « Je
garde », swipe gauche « Pas pour moi », bouton signet « Plus tard ». La liste des
gardés se construit sous la pile, dans le feed, sans écran supplémentaire.

La PR embarque aussi deux décisions PO prises pendant la construction :

1. **La vue finale, c'est ce qu'on a gardé.** Le plan V0 rendait la liste
   inchangée une fois le tri fini — les rejetés réapparaissaient. À la relecture,
   la liste finale ne correspondait pas aux choix. En état `done`, la carte ne
   rend plus que `keptContentIds` (« Je garde » + « Plus tard »), dans l'ordre du
   slate ; état vide sobre si rien n'a été gardé. **Rien n'est retiré du digest
   côté données** : le slate reste figé pour la journée et « Trier à nouveau » le
   rejoue en entier. C'est purement l'affichage final.
2. **La « Lettre du jour » ne gate plus l'accès à L'Essentiel.** Cold-open, tap
   d'onglet et tap de push atterrissent directement sur le feed. La lettre reste
   jouée **une fois**, en fin d'onboarding, et le rewind des éditions passées
   subsiste dans le feed.

## Pourquoi

**V0 en collecte seule.** Chaque décision est enregistrée avec son rang dans le
slate figé, mais **aucun poids de reco ne bouge**. Le but n'est pas de
personnaliser tout de suite : c'est de produire le jeu de données que la jauge
CTR ne peut pas produire — des **négatifs explicites sur des articles réellement
vus**, avec leur position. C'est l'angle mort n°1 de
`maintenance-feed-ranking-gauge.md`. Seule exception actée par le PO : « Plus
tard » déclenche le save existant, exactement comme le bouton signet de la carte.

Le piège que le code garde activement : l'action `not_interested` existante est à
un enum de distance, et elle ajouterait la **source entière** à
`user_personalization.muted_sources`, sans expiration. Un test de non-régression
négative verrouille ça (voir plus bas).

## Comment ça a été vérifié

- [x] **Backend** — `pytest` : **2913 passed, 18 skipped, 2 xfailed**. `ruff check` OK.
      Tests neufs sur le routeur de tri : idempotence de l'upsert sur
      `(user, article, jour)`, batch partiel, `slate_size` incohérent rejeté, et
      surtout la **non-régression négative** — `POST /essentiel/triage` avec
      `decision=pass` ne modifie ni `user_subtopics.weight`, ni
      `user_entity_affinity`, ni `user_personalization.muted_sources`.
- [x] **API locale** — `uvicorn` + `curl` : `GET /api/essentiel` et
      `POST /api/essentiel/triage` répondent `403` sans auth (cas limite), et
      `divergence_level` est bien exposé dans l'OpenAPI (`string | null`).
- [x] **Alembic** — exactement **1 head** (`tr01_essentiel_triage`), `upgrade head`
      local contre une DB vide. Migration **purement additive** (nouvelle table,
      aucun `DROP`/rename/`NOT NULL`-sur-peuplé) ⇒ conforme expand-contract sur
      la DB partagée staging/prod.
- [x] **Mobile** — `flutter test` : **2011 passed**, 26 échecs **strictement
      identiques à la baseline `main`** (topic_chip, bookmark, feed_sources,
      notification, perspectives, theme_section, subscriptions, settings_sheet,
      widget_test — aucun dans le périmètre touché). `flutter analyze` : **526
      issues, exactement la baseline**, zéro `error`, zéro `warning` neuf.
- [x] **Build web** — `flutter build web --release` (garde-fou de compilation, cf.
      l'incident `firstPreparingIndex` d'un build rouge passé inaperçu).
- [x] **`/simplify`** — 4 relectures parallèles, findings appliqués (détail dans la
      story, section « Passe SIMPLIFY »), puis re-run complet de VERIFY.
- [ ] **Playwright / `/validate-feature`** — **non exécuté** : chaque scénario de
      tri exige un compte connecté avec un digest du jour, et je n'ai pas de
      credentials. `.context/qa-handoff.md` est à jour ; à lancer avant merge.

## Zones à risque

- **Router (zone à risque déclarée).** Le gate quotidien `/flux-continu → /edition`
  est retiré du `redirect`, et `PushNotificationService.openRoute` ne dé-route plus
  les push. C'étaient les deux seuls points d'application, coupés ensemble ; le
  test de redirection le verrouille dans les deux sens. La sortie d'onboarding
  passe toujours délibérément par `/edition?from=onboarding`.
- **Migration sur DB partagée.** `tr01` est additive et idempotente, donc sans
  risque pour le backend `production` qui tourne encore sur l'ancien code jusqu'à
  la release hebdo suivante.
- **Budget de hauteur du feed.** Le pic de tri passe de 542 à **628 px** pour un
  slate de 5 (bandeau image 96 + titre 4 lignes + compteur). Si la vérification à
  390×844 montre un débordement, les leviers de repli sont, dans cet ordre :
  bandeau 96 → 80, puis `kTriageKeptSlotHeight` 64 → 56. **Ne pas réduire le
  slate** — le verrouiller à 5 est une doctrine produit.
- **Clés `SharedPreferences`.** Le compteur du nudge auto-grow change de mécanique
  de purge (il fuyait une clé par jour ; il purge maintenant). Les **noms** de
  clés persistées sont inchangés, donc aucune perte d'état à la mise à jour.

## Ce que cette PR ne fait pas

- Ne bouge **aucun poids de reco** : la V0 collecte, elle ne personnalise pas.
- Ne retire rien du digest côté données — seul l'affichage final reflète les choix.
- N'unifie pas le fait « l'utilisateur a découvert l'aperçu au long-press » entre
  les trois surfaces qui le stockent aujourd'hui (décision produit, signalée dans
  la story).
