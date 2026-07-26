# feat(lecture-aboutie): rendre la complétion visible, durable et non rejouable (Epic 30)

Epic 30 « La lecture aboutie », base `main`. **Aucune migration** (1 head Alembic,
`mg04_merge_pt01_rd01`, inchangé).

L'audit fichier par fichier de `main` a établi que la moitié visible de la demande
d'origine n'était jamais montée à l'écran, que la complétion ne survivait pas au
redémarrage, et que deux bugs backend restaient ouverts, dont un que #1007 avait
aggravé.

## A. Backend

- **`_update_closure_streak(user_id, target_date)` estampille l'édition close**,
  plus une notion de « aujourd'hui ». Le correctif de #1007 avait remplacé une
  frontière UTC (00h→02h Paris) par la frontière éditoriale 07h30 alors que ses
  deux appelants cherchent le digest via `today_paris()` (minuit) : la fenêtre de
  divergence avait *grandi*. Un lecteur qui clôturait l'édition D à 01h se voyait
  estampiller D-1, puis sa série remise à 1 le lendemain. **Zéro test ne couvrait
  la méthode** (mockée dans les 3 fichiers qui l'approchent) ; elle l'est
  maintenant, démockée, contre une vraie base.
- **Garde-fou édition passée** : `complete_digest` accepte n'importe quel
  `digest_id` et le sélecteur de date sert les éditions J-7. Un `days_since`
  négatif tombait dans la branche « série cassée » (reset à 1) *et* ramenait
  `last_closure_date` en arrière, cassant aussi la clôture du lendemain.
- **`week_start_paris()`** dans `app/utils/time.py` : la règle « semaine = lundi,
  heure de Paris » était recopiée 3 fois sur un `date.today()` UTC (reset hebdo
  une à deux heures trop tôt le lundi côté lecteur).
- **`DAILY_COMPLETION_GOAL`** descend dans `app.schemas.streak` : le
  `daily_goal: int = 2` du schéma était un doublon en dur, libre de diverger.
  Sens de dépendance `services → schemas` conservé.
- **`count_completed_today`** (le compteur exposé à l'UI) a enfin des tests
  (J-3, frontière 07h30 des deux côtés, scope utilisateur).
- **`EssentielArticle.completed_at`** est servi : la carte héros de la Tournée ne
  pouvait pas connaître la complétion, alors que `_to_essentiel_article` recevait
  déjà le champ.

## B. Mobile — durabilité

- **`CompletedReadsStore`** (box Hive `completed_reads` dédiée, purge 30 j, cap
  1000). Box séparée de `pending_reads` : cette dernière est une file de synchro
  qui *supprime* l'entrée au succès. `markCompleted` écrit le registre d'abord,
  puis l'état, comme `markConsumed`.
- **Hydratation poussée** au démarrage (one-shot, post-frame), pas watchée :
  faire dépendre `completedContentIdsProvider` de `readSyncUserIdProvider`
  remonterait à `Supabase.instance` et casserait tout widget test montant une carte.
- **Fuite inter-comptes** : `completedContentIdsProvider` est vidé au logout.

## C. Mobile — visible

- **`ReadStateMark`** partagé remplace 2 des 3 copies privées : celle de la carte
  Essentiel codait `check` en dur, donc était *structurellement* incapable
  d'afficher une complétion. `_ReadStatusPill` (timeline d'éditions) n'est pas
  touchée : elle décrit l'état d'une *édition*, pas d'un article.
- **`AnimatedFeedCard`** était restée orpheline (0 référence dans `lib/`) : le
  filet vert n'existait pas à l'écran. Elle est montée sur les 3 familles de
  cartes en `animate: false` (un état au montage, une animation seulement sur la
  transition de retour d'article). Son `AnimationController` était `late final`
  et n'était instancié qu'au `dispose()` d'une carte non aboutie : inoffensif
  tant qu'elle était du code mort, systématique dès qu'elle est montée partout.
- **Mapping** : `FluxArticleVM.from(DigestItem)` et `articleToContent` jetaient
  `completedAt` ; le modèle mobile `EssentielArticle` ne le parsait pas.
- **Layout du cachet** : sorti de la `Column` du pied de page (il y ajoutait
  ~34 px alors que `_kFooterContentHeight` sert de spacer à 9 endroits) et rendu
  **frère** du pill via `Stack` + `FractionalTranslation(0, -1)`. Aucune mesure,
  les 9 usages inchangés.

## D. Mobile — réouverture

- **`ArticleCompletionLatch`** (Dart pur, testé) sépare l'état connu à l'ouverture
  de l'événement de session. Rouvrir un article terminé ne rejoue plus haptique +
  POST + `article_finished` — l'événement même qui doit servir à calibrer
  l'objectif journalier, jusqu'ici gonflé par les relectures.

## E. Silences

- Le `catch (_)` du flush de la file de lectures remonte à Sentry, hors erreurs de
  connectivité (cas nominal de cette file, `isOfflineError`).
- L'opt-out gamification n'échoue plus en silence (relit la vérité serveur + le dit).

## Vérification

- Backend : `pytest` — **2514 passed**, 18 skipped, 2 xfailed, 0 échec.
  1 head Alembic, aucune migration ajoutée.
- Mobile : `flutter test` — **+1747 / -28**, les 28 échecs dans 8 fichiers
  qu'aucun commit de cette PR ne touche (baseline documentée ~27 :
  `auth/router_redirection`, `custom_topics`, `digest/bookmark`,
  `detail/notification_test`, `feed_sources`, `perspectives_*`, `settings/*`,
  `widget_test`). Les 53 tests des fichiers touchés/ajoutés passent.
- `flutter analyze` : **0 erreur**.
- Changelog in-app : entrée « Lecture » ajoutée (impact visible).

## Zones à risque

`digest_service._update_closure_streak` (série de clôture), `read_sync_service`
(file de synchro des lectures), boot Hive (`main.dart`, 7e box), et les 3 familles
de cartes du feed.

Story : `docs/stories/core/30.lecture-aboutie/README.md` (§11 journal
d'implémentation).

## Reste ouvert

- Fenêtre de 14 j de collecte `article_finished` (PostHog) avant d'arrêter
  `DAILY_COMPLETION_GOAL` sur P50/P75/P90. La correction de la réouverture est ce
  qui rend cette distribution exploitable.
- `/validate-feature` (parcours visuels : cachet, filet, anneau) non exécuté —
  Flutter web n'était pas lancé dans cet environnement.
