# Hand-off CTO — 2026-04-19

> Décisions requises : stabilité + scalabilité backend. Evidence complète dans `.context/perf-watch/2026-04-19.md`. Ici : le minimum pour arbitrer.

## Situation en 3 lignes

1. **On vole aux instruments cassés** : Sentry n'accepte plus aucun event depuis 2026-04-18 15:00 UTC (quota projet épuisée par du bruit externe HTTP). Round 5 (`c2d2d802`, déployé 00:20 UTC, PR #436 "fixes infinite-load > 100 users") tourne en production depuis ~6h sans aucune mesure possible de son effet réel.
2. **Les erreurs DB de Round 1-4 ne sont pas toutes fixées** : `PendingRollbackError` (R3 censé l'avoir tué) refire sur `routers/community.get_community_recommendations`, utilisateurs réels NL, release pré-Round-5. On ignore si Round 5 en a hérité.
3. **Aucune action prise par l'agent** (strictement hors scope). Les tokens Sentry + Railway ont transité via le chat — **à rotater**.

## 4 décisions à trancher

### D1 — Restaurer l'observabilité (P0, bloquant tout le reste)

Sans Sentry, on ne saura pas si Round 5 a marché, ni si l'app crashe en ce moment. Options :

| Option | Coût | Délai | Risque |
|--------|-----:|------:|--------|
| **F1 — Ajouter `before_send` dans `packages/api/app/main.py:113`** pour dropper `trafilatura.*` + messages `not a 200 response` / `download error:` | 1 fichier, ~20 LOC, 1 PR. | 1h dev + CI. | Filtre trop large → masquer de vrais bugs HTTP internes. Mitigé en filtrant par `logger_name` ET message. |
| **Upgrade plan Sentry** (payant) | ~$26–80/mois selon tier. | 5 min via dashboard. | Solde le symptôme, pas la cause. Le bruit externe resterait et re-saturera le plan supérieur dans quelques semaines si trafilatura se dégrade. |
| **Les deux** | Cumule coûts. | — | Approche défensive : quota restaurée immédiatement + ménage à terme. |

**Recommandation agent** : F1 seul en priorité. Décision CTO : stabilité immédiate (upgrade) ou discipline (filtre) ou les deux ?

### D2 — Round 5 en aveugle : laisser tourner ou rollback préventif ?

PR #436 a été mergée avec l'intention explicite de fixer "infinite-load > 100 users". On n'a aucune preuve qu'elle le fait ni qu'elle casse autre chose. Depuis le deploy :
- 0 event Sentry accepté (→ tableau de bord vide, trompeur)
- Client-side on a débounce + SWR gate — risque de régressions UX silencieuses côté mobile
- Invalidation cache ajoutée dans 5 routers (`contents`, `custom_topics`, `personalization`, `sources`, `users`) : surface de bug

| Option | Conséquence |
|--------|-------------|
| **Laisser tourner** + résoudre D1 | Par construction : 24h après F1, on saura. Coût : 24h de risque invisible supplémentaire. |
| **Rollback `c2d2d802`** immédiat vers `c16f51da` | Retour à un état où on avait des erreurs connues (`PendingRollbackError`, pool timeouts) mais mesurées. Annule 1200 LOC et le travail mobile associé. |

**Recommandation agent** : laisser tourner, conditionné à D1 appliqué dans la journée. Rollback seulement si remontée utilisateur critique. Décision CTO : tolérance au risque cette nuit.

### D3 — Stabilité DB : le chemin `community.py` n'est pas couvert par R3

R3 (`_invalidate_on_supabase_kill` dans `packages/api/app/database.py`) était censé neutraliser les `PendingRollbackError` sur connexions tuées Supabase. Evidence : PYTHON-14 encore 14 occurrences, 3 users distincts, culprit `app.routers.community.get_community_recommendations`, dernière occurrence 2026-04-18 15:11 UTC (pré-saturation Sentry).

| Option | Effort | Couverture |
|--------|-------:|-----------|
| **Fix ciblé** : `try/except` + `rollback()` explicite dans `get_community_recommendations` | S (1 fichier, <20 LOC). | Ce seul endpoint. |
| **Audit systématique** : identifier tous les endpoints qui checkout une session et n'ont pas de `rollback()` garanti sur exception | M-L (backlog story). | Couverture complète. |
| **Refacto middleware** : wrapper qui garantit `rollback()` global sur exception | L. | Couverture complète, impact archi. |

**Recommandation agent** : ne rien faire avant D1 résolu (on ne saurait pas mesurer l'impact). Une fois Sentry débloqué + 24h de données sur release `c2d2d802`, si PYTHON-14 refire → option ciblée.

### D4 — Scalabilité du générateur de digest

Signal pré-saturation : **9 groupes distincts** de `HTTPException: digest_generation_timeout` (PYTHON-B / Z / 12 / 20 / 21 / 22 / 1T / 1V / W), cumul ~71 events, 2-3 users par groupe, fenêtre 2026-04-18 12:45→14:26 UTC. Même utilisateur, même signature, groupes séparés = le groupeur Sentry voit des stack variables (contexte différent à chaque run).

Interprétation : le digest timeout n'est pas un edge case, c'est récurrent pendant la fenêtre de traffic. Pool = 10 + overflow 10. Round 4 (feed 3→2 sessions) a réduit la pression côté feed mais pas côté digest.

Questions CTO :
- Quelle est la cible de scale (users simultanés) pour Q2 ?
- Le digest est-il encore compute-bound (LLM) ou IO-bound (DB + fetch) ? Si IO-bound, augmenter le pool (interdit à l'agent avant 24h de métriques — règle levable CTO).
- Quotas externes (Anthropic, trafilatura) sont-ils dimensionnés pour la cible ?

**Pas de recommandation agent** — décision produit/archi hors scope watcher.

## Ce que l'agent n'a PAS pu faire (inputs à débloquer)

1. Lire Railway logs → `backboard.railway.com` hors allowlist réseau du sandbox. Bloque §4 du rapport quotidien.
2. Lire `/api/health/pool` en prod → même host bloqué. Bloque §5.
3. Conséquence : pas de corrélation log / pool / Sentry. Le watcher nocturne reste unilatéral.

Action demandée : étendre l'allowlist sandbox (`facteur-production.up.railway.app`, `backboard.railway.com`). Déjà listé dans le rapport §9 P2.

## Sécurité — immédiat

- Token Sentry utilisateur (préfixe `sntryu_…`, scopes `org:admin`, `event:admin`) transmis via chat : **à révoquer**, régénérer et injecter via variable d'env du harness (`SENTRY_AUTH_TOKEN`), pas par le chat.
- Token Railway (UUID v4) transmis via chat : **à révoquer** même voie (`RAILWAY_TOKEN`).
- Valeurs exactes disponibles dans l'historique de la conversation d'origine ; volontairement non recopiées dans ce fichier pour éviter leur commit.

## Arbitrage suggéré (ordre)

1. D1 F1 **aujourd'hui** (débloque tout).
2. Rotation tokens **aujourd'hui**.
3. Fix allowlist sandbox **cette semaine** (qualité du watcher).
4. Observer 24h sur `c2d2d802` → trancher D2 et D3 sur données.
5. D4 : stocker pour sprint planning, pas nocturne.

Tout le reste (refacto, pool tuning, retrait `_scheduled_restart`) reste gouverné par les règles §0 du watcher — interdit avant 7 jours de `QueuePool limit = 0` consécutifs.
