# CTO H3 — Note CPO : ajustements produits pour la scalabilité (J+30)

> Horizon 3 / 3 du handoff CTO 2026-04-17. Lecture cible : CPO + Laurin (PO).
> Format tradeoffs, pas diagnostic technique. Les détails d'impl pour chaque
> option sont référencés mais pas développés ici.

## Pourquoi cette note

Quatre rounds de fixes en 5 jours sur le même pool Supabase
(`docs/bugs/bug-infinite-load-requests.md` R1→R4). Chaque round tient 4-24h
avant qu'un nouveau burst n'expose un angle non couvert. Les fixes sont bons
techniquement (moins de sessions/req, short sessions, listener disconnect,
per-user isolation) mais on tape contre un **plafond structurel de 20
connexions partagées**. Certaines régressions sont amplifiées par des choix
produit qu'un ajustement UX pourrait alléger sans rouvrir pool_size.

---

## Tradeoff 1 — Burst concurrent à l'ouverture app web

| Champ | Contenu |
|-------|---------|
| **Problème technique** | Chrome déclenche ~6 requêtes **en parallèle** à l'ouverture : `/api/feed/`, `/api/users/streak`, `/api/digest/both`, `/api/sources/`, `/api/collections/`, `/api/custom-topics/` (bug doc §Round 4). À 1-3 connexions/req, un seul user sature 6-10 slots sur 20 disponibles. Round 4 a réduit `/api/feed/` 3→2 sessions (PR #417), mais la parallélisation côté client n'a pas changé. |
| **Option A** | **Endpoint unique `/api/bootstrap`** qui renvoie en un appel l'état initial app shell (feed initial + streak + sources count + collections count + custom topics). Implémentable en ~2-3 jours côté API. Mobile + web : un seul appel au démarrage. |
| **Option B** | **Séquentialiser côté client** : web charge d'abord `/feed/` + `/digest/both`, puis au second tick les 4 appels "chrome" (streak, sources, collections, custom topics). Implémentable en ~½ jour côté mobile/web. |
| **Option C** (status quo) | Laisser la parallélisation, compter sur les fixes backend round par round. |
| **Impact scalabilité** | A : réduit le pic de conn/user de ~6-10 à ~2-3 → **~3× de marge**. B : réduit de ~6-10 à ~3-5 → ~2× de marge. C : aucun gain, on continue à rejouer R5, R6, R7. |
| **Coût UX** | A : aucun (transparent). B : légère latence sur l'affichage du streak / badges secondaires (~500ms perçus). C : risque récurrent de "tout charge à l'infini" en prod. |
| **Recommandation CTO** | **A** prioritaire, **B** en filet intermédiaire si A prend > 1 sprint. C inacceptable au-delà de 2 semaines. |

---

## Tradeoff 2 — Pyramide de retries mobile (zombies backend)

| Champ | Contenu |
|-------|---------|
| **Problème technique** | `retry_interceptor.dart` (maxRetries=2) × 4 tentatives digest × 45s timeout ≈ **9 min worst case** côté UX, pendant lesquels le backend accumule des sessions zombies si un upstream lent + un cancel mal propagé. PR #422 a même **augmenté** les retries 202 à 5 (5/10/15/20/30s ≈ 80s) pour supporter l'onboarding pré-gen, mais cette générosité ne cible que le code 202. |
| **Option A** | **Erreur visible à 30s** : réduire la pyramide à 1 tentative + un timeout global de 30s après lequel on montre "Le service est lent, réessaie dans un instant" avec un CTA retry manuel. Assumé UX-cassant ; transparent techniquement. |
| **Option B** | **Pyramide courte + long-polling côté serveur** : 1 retry côté mobile max, mais le backend ouvre un channel SSE/WebSocket pour pousser le digest dès qu'il est prêt. Coût implémentation important (~1 sprint). |
| **Option C** (status quo raffiné) | Garder la pyramide mais distinguer **types d'erreurs** : 503 `digest_generation_timeout` = 1 retry max (déjà fait par PR #422, `maxGenerationRetries=3`). 202 `preparing` = 5 retries. Network error = 2 retries. Pas de nouveau code. |
| **Impact scalabilité** | A : supprime les zombies liés aux retries (gain ~10-30% des sessions idle long age). B : idem + améliore UX cold start. C : statu quo. |
| **Coût UX** | A : l'utilisateur voit une erreur qu'avant on masquait — perception négative potentielle, mais au moins le spinner infini disparaît. B : meilleure UX (animation "en cours", arrivée du digest annoncée). C : rien ne change côté user. |
| **Recommandation CTO** | **A pour les endpoints non-onboarding** (le digest du quotidien doit répondre vite ou annoncer sa panne), **C conservé pour l'onboarding** (le user a déjà investi 2 min, l'attente est acceptable). B seulement si on fait du long-polling pour d'autres raisons produit. |

---

## Tradeoff 3 — Onboarding pré-gen vs vraie queue

| Champ | Contenu |
|-------|---------|
| **Problème technique** | PR #422 a posé `BackgroundTasks` de FastAPI sur `POST /users/onboarding` pour pré-générer les 2 variantes du digest pendant l'animation de conclusion (10s). Tient tant que le volume reste faible. Un SIGTERM uvicorn (restart Railway, `_scheduled_restart`) **perd** les BackgroundTasks en vol. |
| **Option A** | **Queue dédiée arq/Redis** avec worker Railway séparé. Les jobs persistent au redémarrage. Coût : ~3-5 jours dev + Redis en prod (~$10/mois). |
| **Option B** (status quo) | Garder BackgroundTasks, accepter les pertes rares au restart. Le poll 202 mobile (5 retries, 80s) compense une perte ponctuelle. |
| **Option C** | **Pré-gen synchrone** dans `POST /users/onboarding` avec timeout 15s. Le user attend explicitement que son premier Essentiel soit prêt. Simple, pas de perte possible ; coût UX : barre de progression visible. |
| **Impact scalabilité** | A : tenable jusqu'à plusieurs centaines d'onboardings/h. B : tenable jusqu'à ~20/h d'après seuil T2-4 (voir H2). C : chaque onboarding tient une conn Python 15s → à 20/h ça reste OK, au-delà risque pool. |
| **Coût produit** | A : aucun (transparent). B : perte silencieuse d'un nouvel user ≈ spinner sur le 1er écran pendant 1 min avant retry → désastreux en conversion. C : user voit "préparation de ton Essentiel…" 5-15s supplémentaires sur la dernière étape onboarding — pas forcément grave, mais change la narration. |
| **Recommandation CTO** | **B tant que < 20 onboardings/h** (critère T2-4). Préparer A en arrière-plan (POC technique non-merge en parallèle des autres priorités). **C rejeté** : change la promesse "ton Essentiel t'attend déjà demain matin" en "attends, je prépare". |

---

## Tradeoff 4 — Éditorial LLM 3-5 min : fresh à 6h vs latence UX assumée

| Champ | Contenu |
|-------|---------|
| **Problème technique** | La pipeline éditoriale (`compute_global_context`) peut prendre 3-5 min (LLM curation × 2-3 + perspective analysis × 5 + writing × 5 + pépite + coup de cœur, `bug doc §Site B`). Le batch nocturne 6h Paris absorbe cette latence (user dort). Mais si un user n'est pas couvert à 6h (watchdog 7h30) ou déclenche un regen en journée, on repaye 3-5 min **en ligne** avec une session DB tenue. Round P1 (PR #405) a posé `session_maker` + short sessions pour sortir la session avant LLM, mais la pipeline reste un chemin critique coûteux. |
| **Option A** | **Assumer la latence côté UX** : `/digest/both` renvoie systématiquement 202 `preparing` sur cache-miss, mobile affiche "Préparation de ton Essentiel… (peut prendre quelques minutes)" avec poll. Le 6h-fresh devient une optimisation, pas une garantie. |
| **Option B** (status quo) | Garder le contrat "6h Paris = prêt", accepter les pics du watchdog 7h30 + regens en journée, compter sur les short sessions P1 pour éviter la saturation. |
| **Option C** | **Réduire la pipeline** : moins de subjects (5→3), moins de perspective analysis, moins de writing LLM calls. Gain : ~2× plus rapide. Coût : moins de contenu éditorialisé → possible régression de la perception qualité. |
| **Impact scalabilité** | A : retire la pression des retries côté sessions DB (la génération tourne en background batch, pas en ligne). B : pression modérée, déjà sous contrôle post-P1 tant que le pool R4 tient. C : réduit la charge LLM + DB de moitié, mais change le produit. |
| **Coût produit** | A : change la promesse "ton Essentiel t'attend" → "ton Essentiel se prépare". À tester UX auprès des users. B : aucun. C : risque majeur sur la proposition de valeur "5 articles éditorialisés profonds". |
| **Recommandation CTO** | **B à court terme** (l'architecture short sessions P1 tient). **A à envisager si Round 5 frappe** : c'est le filet qui découple la latence LLM du chemin critique user. **C rejeté** sauf décision CPO explicite de pivot produit. |

---

## Synthèse CPO

| # | Recommandation CTO prioritaire | Délai | Décision CPO requise |
|---|---|---|---|
| 1 | Endpoint `/api/bootstrap` (Option A) | 2-3 jours dev | Accord sur le pattern "un appel au boot" |
| 2 | Retries mobile : 1 tentative + erreur 30s pour non-onboarding | ½ jour | Accepter qu'une erreur soit visible plus tôt |
| 3 | Garder BG tasks onboarding, préparer arq en POC | 0 (statu quo) + POC 1 sprint | Aucune décision bloquante |
| 4 | Statu quo 6h-fresh, plan de secours "202 preparing" en cas de R5 | 0 | Aucune décision immédiate |

**Ce que je demande au CPO cette semaine** : un go/no-go sur #1 (endpoint
bootstrap) et #2 (politique retry). Le reste est instrumental et peut être
décidé par l'équipe technique seule tant que les métriques (H2) restent vertes.

**Ce qui n'est pas dans cette note** : choix produit plus larges
(monétisation, segmentation cohortes, etc.). Strictement scoped aux
tradeoffs qui pèsent sur la scalabilité backend des 30 prochains jours.
