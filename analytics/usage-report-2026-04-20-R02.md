# Rapport d'usage & valeur — Facteur — R02 (chiffré)

**Date :** 2026-04-20 · **Statut :** premier rapport chiffré · **Base :** 64 users profilés

> Suite du R01 (`usage-report-2026-04-20.md`). Les chiffres viennent des
> requêtes T2/T3 lancées par Laurin sur la prod Supabase.

---

## 0. TL;DR

1. **Facteur a ~64 users profilés, dont 16 actifs / 7 jours (25 %).** Volume beta cohérent, mais l'habitude ne prend pas : **1 seul user avec streak courant ≥ 7 jours**, et 88 % de perte entre J1 et J3 de streak.
2. **Deux bugs d'instrumentation bloquants découverts** : (a) aucun `digest_session` loggé dans `analytics_events` sur 30 jours → le KPI nord du produit est aveugle depuis PostHog ; (b) `time_spent_seconds = 0` partout → la durée de lecture n'est jamais enregistrée.
3. **Deux surprises positives** : (a) 64.5 % des articles sauvegardés finissent lus → bookmarks = vraie valeur, pas cimetière (mon hypothèse R01 est **retournée**) ; (b) la gamification corrèle à streaks ×2 (3.18 vs 1.56).
4. **Une feature morte à trancher** : "Mise en perspective" → 0 vue en 30 jours. Soit instrumentation cassée, soit feature non découverte → décision binaire kill/relancer.
5. **Décision monétisation à armer** : aucun paywall/trial tracké, or l'attrition J1→J3 rend le modèle premium fragile tant qu'on n'a pas identifié le moment de valeur.

---

## 1. Contexte de base (dénominateurs)

| Métrique | Valeur |
|---|---|
| Total profils | **64** users (9 gamif OFF + 55 gamif ON) |
| Users avec au moins 1 streak actif | 51 (80 %) |
| Users actifs 7 jours (lecture contenu) | **16 (25 %)** |
| Users ayant sauvegardé ≥ 1 article | 19 (30 %) |
| Users ayant une fois atteint streak ≥ 7 | 5 (8 %) |

**⚠️ Incohérence détectée** : 51 users avec `current_streak ≥ 1` vs 16 users réellement actifs en 7j.
- Hypothèse : le calcul de streak inclut des events non-contenu (ouverture app sans lecture) ou n'est pas décrémenté correctement → **streaks potentiellement zombies**.
- **Action R03** : auditer le code de `user_streaks` (`packages/api/app/services/streak_service.py` probable) pour vérifier la règle de reset.

---

## 2. Métrique par métrique

### 2.1 Digest completion (KPI nord) — ⛔ AVEUGLE

**T2.1 → 0 rows sur 30 jours.**

Les events `digest_session` ne sont pas loggés dans `analytics_events`. Or la table `digest_completions` existe et est probablement alimentée directement (pas de mirror dans `analytics_events` ni PostHog). Conséquence : **ni le dashboard PostHog documenté dans Story 14.1, ni les funnels d'activation, ne captent la métrique la plus importante du produit.**

**Actions R03 (P0) :**
1. Lancer la variante T2.1b du nouveau `scripts/analytics/run_usage_queries.sh` (lit directement `digest_completions`) pour avoir les chiffres vrais.
2. Patcher le mobile (ou le backend côté `POST /digest/complete`) pour émettre en parallèle un `analytics_events{event_type='digest_session', closure_achieved, articles_read, total_time}` + un `capture('digest_session', ...)` PostHog.
3. Sans ces 2 fixes, **tous les dashboards Tier 2 sont structurellement cassés**.

### 2.2 Streaks — habitude fragile, mais existante

| Seuil streak courant | Users | % base (n=64) |
|---|---|---|
| ≥ 1 | 51 | 80 % |
| ≥ 3 | 6 | 9 % |
| ≥ 7 | 1 | 2 % |
| ≥ 14 | 1 | 2 % |
| *Historique : ≥ 7 jamais atteint* | 5 | 8 % |
| *Record historique* | 32 jours | — |

**Lecture :**
- **Cliff J1 → J3 : –88 %** (51 → 6). C'est LE point bloquant n°1 de l'app.
- Un user a tenu 32 jours → la proposition peut tenir. Le produit est capable, mais le "truc" qui retient n'est pas activé pour la majorité.
- Benchmark rétention daily digest sain : 15–25 % des users forment un rituel hebdo (streak ≥ 7). Ici : **2 %**. Très en-dessous.

**Hypothèses causales (à tester R03) :**
1. **La notif 8h ne ramène pas** (pas d'instrumentation → on ne sait pas si elle est ouverte) → ajouter `notification_opened`.
2. **L'onboarding promet un truc que le digest ne tient pas** → ajouter un funnel `signup → first_digest_completed` pour voir où le match casse.
3. **Le digest arrive à 8h mais beaucoup ouvrent le soir** → mesurer la distribution horaire de `session_start` les jours de digest.

### 2.3 Activité 7j — volume correct, mais métrique durée KO

| Métrique | Valeur | Verdict |
|---|---|---|
| Users actifs 7j | 16 | cohérent avec beta |
| Articles consommés (7j) | 276 | 17/user/sem = **2.5/jour** → bon |
| Temps total lecture | **0.0 min** | ⛔ BUG — `time_spent_seconds` jamais écrit |
| Articles / user | 17.3 | ok |

**Bug critique :** `user_content_status.time_spent_seconds` retourne 0 partout. Soit le mobile ne le remonte pas, soit l'endpoint qui met à jour le statut ignore le champ. **Toute la narration "temps passé sur Facteur" est fausse tant que ce n'est pas corrigé.**

**Action R03 (P0) :** grep côté API pour l'endpoint de maj de statut et vérifier que `time_spent_seconds` est bien persisté. Probablement une route `PATCH /contents/{id}/status` ou similaire.

### 2.4 Bookmarks — 🎯 signal PMF caché (hypothèse R01 inversée)

| Métrique | Valeur |
|---|---|
| Articles sauvegardés (total) | **301** |
| Users avec ≥ 1 save | 19 (30 % base) |
| Articles sauvés + consommés | 194 |
| **Taux de lecture des articles sauvés** | **64.5 %** |

**Lecture :**
- Hypothèse R01 ("cimetière, < 15 %") **complètement fausse**. 64.5 % est **exceptionnellement haut** (benchmark read-later apps : 15–30 %).
- ~16 articles sauvés / user / 30j → **le bookmark est une habitude active**, pas passive.
- Caveat : il faut vérifier la **causalité** (saved→read ou read→saved) via `collection_items.added_at` vs `user_content_status.updated_at`. Si majoritairement "read-then-save", c'est un signal de **valeur rétrospective** (archiver ce qui a compté), très fort pour le positionnement "slow media".

**Verdict :** **GARDER et mettre en avant.** Envisager :
- Widget "3 articles vous attendent" sur l'écran d'accueil.
- Push hebdo "Vos pépites de la semaine" récapitulant les saves.
- Tracker `bookmark_opened` et `bookmark_revisited` pour confirmer R03.

### 2.5 Mise en perspective — 💀 feature morte

**T3.1 → 0 vues, 0 users uniques sur 30 jours.**

Deux scénarios :
1. **Instrumentation cassée** : le bouton "Mise en perspective" existe dans l'UI mais ne déclenche pas l'event `comparison_viewed` → test manuel à faire (5 min dans l'app avec ouverture dashboard PostHog live).
2. **Feature réellement invisible/inutilisée** : les users n'ont pas de point d'entrée ou la feature ne répond pas à un besoin concret.

Epic 7 est à 40 % d'avancement. Continuer à investir dedans sans signal d'usage = risque fort.

**Décision R03 :**
- D'abord : test manuel (30 min) pour distinguer les 2 hypothèses.
- Si instrumentation OK et toujours 0 usage → **déprioriser Epic 7, concentrer sur la formation d'habitude (§2.2)**.
- Si instrumentation KO → fixer, attendre 7 jours, re-mesurer.

### 2.6 Gamification — signal positif mais biaisé

| Cohorte | N | Streak courant moyen | Streak longest moyen |
|---|---|---|---|
| Gamif OFF | 9 | 1.22 | 1.56 |
| Gamif ON | 55 | 1.84 | **3.18 (×2)** |

**Lecture :**
- Corrélation nette. **MAIS** 86 % des users ont gamif ON → c'est le défaut probable → biais de self-selection quasi total (le groupe OFF est composé de users qui ont activement désactivé, donc probablement des utilisateurs plus sceptiques/rationnels).
- N=9 sur le groupe OFF est trop petit pour conclure.

**Verdict intermédiaire :** **garder la gamif, mais ne pas prétendre qu'elle est "prouvée"**.

**Action R03 :** A/B test propre (50/50, assignment à l'onboarding), ou mesurer différentiel de complétion digest entre les deux cohortes (dès que T2.1 fonctionne).

---

## 3. Synthèse — verdicts provisoires par feature

| Feature | Statut | Signal | Décision |
|---|---|---|---|
| **Digest quotidien** | Aveugle (instrumentation KO) | ❓ | **P0 : fixer tracking, ré-évaluer R03** |
| **Streaks** | Fonctionnel | ⚠️ Faible adoption profonde (2 % ≥7j) | Garder, enquêter causes cliff J1→J3 |
| **Bookmarks / "À consulter plus tard"** | Fonctionnel | ✅ **Fort** (64.5 % lus) | **Mettre en avant, investir** |
| **Feed infini** | Fonctionnel | ⚠️ Durée inconnue (bug) | Fixer durée, re-mesurer |
| **Mise en perspective** | Aveugle OU morte | 💀 0 vue | Test manuel P0 puis kill ou fix |
| **Gamification** | Fonctionnel | 🟡 Corrélation biaisée | Garder, A/B test R03 |
| **Onboarding** | Aveugle (funnel non granulaire) | ❓ | Instrumenter R03 |
| **Push 8h** | Aveugle | ❓ | Instrumenter R03 |
| **Paywall / monétisation** | Non existant ou non tracké | ❓ | Attendre PMF avant instrumenter |
| **Collections custom** | Aveugle | ❓ | Instrumenter ou deprioriser |

---

## 4. Bugs & angles morts critiques identifiés (ordre P0)

| # | Bug / gap | Impact | Fix estimé |
|---|---|---|---|
| 1 | `digest_session` non loggé dans `analytics_events` / PostHog | KPI nord invisible | 2h (backend) |
| 2 | `time_spent_seconds = 0` partout | Métrique temps fausse | 2h (mobile + API) |
| 3 | `comparison_viewed` absent (0 row 30j) | Epic 7 ingérable | 30 min diagnostic |
| 4 | Streaks "zombies" (80 % streak≥1 vs 25 % actifs 7j) | Métrique habitude surestimée | 1h audit + fix |
| 5 | Funnel onboarding non granulaire | Drop-off inconnu | 2h mobile |
| 6 | `notification_opened` absent | Utilité push inconnue | 1h mobile |
| 7 | Causalité bookmark (save→read vs read→save) | Narration marketing ambiguë | 30 min requête SQL |

---

## 5. Actions R03 (sous 2 semaines)

### P0 — Débloquer le monitoring
- [ ] Fixer emission `digest_session` event (backend + mobile) — debloquer closure_rate
- [ ] Fixer persistence `time_spent_seconds` — debloquer métrique temps
- [ ] Diagnostiquer `comparison_viewed` (test manuel 30 min)
- [ ] Audit streak reset logic (éviter streaks zombies)

### P1 — Combler les angles morts
- [ ] Funnel onboarding granulaire (`onboarding_step_viewed` avec `step_index`)
- [ ] Notification open tracking (`notification_opened{digest_date}`)
- [ ] Requête causalité bookmark (save→read vs read→save via timestamps)
- [ ] Dashboard PostHog Story 14.1 réellement créé et partagé

### P2 — Actions produit data-informed
- [ ] Widget "3 articles sauvés vous attendent" (ride le signal bookmarks §2.4)
- [ ] Enquête qualitative 5 users du cliff J1→J3 : pourquoi pas J2 ?
- [ ] Décision Epic 7 "Mise en perspective" après diagnostic (§2.5)

---

## 6. Benchmarks pour cadrer les prochains rapports

| Métrique | Facteur R02 | Seuil "app vivante" | Seuil "PMF partiel" |
|---|---|---|---|
| Users actifs 7j / base | 25 % | 20 % | 40 % |
| Streak ≥ 7 jours actuel | **2 %** | 10 % | 20 % |
| Closure rate digest | N/A | 40 % | 60 % |
| Articles / user / semaine | **17.3** | 10 | 25 |
| Saved→read rate | **64.5 %** ✅ | 20 % | 40 % |
| D7 retention (PostHog) | N/A | 15 % | 25 % |

**Où Facteur est bon :** bookmarks, volume de lecture.
**Où Facteur saigne :** formation d'habitude profonde (streak ≥ 7).

---

## 7. Note méthodo pour le R03

Toutes les requêtes sont maintenant dans `scripts/analytics/run_usage_queries.sh`. Dès que `DATABASE_URL_RO` est injectée dans la session Claude (cf. `docs/infra/claude-access-setup.md`), Claude pourra relancer le rapport en autonomie, sans copier-coller de JSON.

Complément PostHog (DAU/MAU/rétention/funnel) à ajouter dans R03 via `scripts/analytics/posthog_query.py` (à créer).
