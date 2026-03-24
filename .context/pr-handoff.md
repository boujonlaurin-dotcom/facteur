# PR — fix: feed default shows only followed sources (remove curated enrichment)

## Quoi
Suppression de la Phase 2 "curated enrichment" du feed par défaut (sans filtre). Le bloc `_use_two_phase` ne requête plus que les sources suivies par l'utilisateur, au lieu de sources suivies + sources curated (non-suivies).

## Pourquoi
Régression introduite par le commit `167aa78b` (topic-aware feed diversification). Le pool élargi laissait beaucoup plus de sources curated (non-suivies) passer la diversification chronologique. Résultat observé en prod : des sources comme Novethic, Osons Causer, Next, La Croix apparaissent dans le feed d'utilisateurs qui ne les suivent pas. Le digest peut inclure des sources curated — le feed par défaut non.

## Fichiers modifiés
- `packages/api/app/services/recommendation_service.py` (+11/-26 lignes)
  - Bloc `_use_two_phase` : suppression Phase 2 curated, single query sur `Source.id.in_(followed_source_ids)` uniquement
  - Commentaires mis à jour pour refléter "followed sources only"
  - Log event renommé : `feed_candidates_two_phase` → `feed_candidates_followed_only`
  - Ajout `followed_source_count` au log pour meilleur debugging

## Zones à risque
- `recommendation_service.py` : la méthode `_get_candidates()` est le cœur du feed. Le changement est minimal (suppression de ~15 lignes de curated enrichment), mais tout bug ici impacte 100% des utilisateurs.

## Ce que le reviewer doit vérifier en priorité
1. Le bloc `_use_two_phase` est désormais single-phase — query uniquement sur followed sources, pas de curated enrichment
2. `limit_candidates` remplace le hardcoded `120` — le limit est passé en paramètre, pas fixé arbitrairement
3. Aucun autre fichier n'est touché — pas de changement mobile, pas de nouveau schema, pas de nouvelle feature
4. Le path `elif theme or topic or entity` reste sur `Source.is_curated` — la découverte via filtres explicites est inchangée

## Ce qui N'A PAS changé (mais pourrait sembler affecté)
- `_use_three_phase` / filtres explicites (topic/theme/entity) : le path `elif theme or topic or entity` reste sur `Source.is_curated`, inchangé
- `_apply_chronological_diversification()` : inchangé
- `_apply_topic_regroupement()` : inchangé
- Le digest (`digest_selector.py`) : aucune modification, continue d'inclure sources curated/deep
- Le mobile : aucun fichier Flutter modifié

## Comment tester
```bash
# 1. Lancer l'API locale
cd packages/api && source venv/bin/activate
DATABASE_URL="<supabase_url>" SUPABASE_JWT_SECRET="<secret>" PYTHONPATH=. uvicorn app.main:app --port 8080

# 2. Générer un JWT test
python3 -c "
import jose.jwt, datetime
token = jose.jwt.encode({
    'sub': '<USER_UUID>', 'aud': 'authenticated', 'role': 'authenticated',
    'iat': int(datetime.datetime.now(datetime.timezone.utc).timestamp()),
    'exp': int((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=2)).timestamp())
}, '<JWT_SECRET>', algorithm='HS256')
print(f'Bearer {token}')
"

# 3. Feed sans filtre → toutes les sources doivent être suivies par l'utilisateur
curl -s "http://localhost:8080/api/feed/?limit=20" -H "Authorization: Bearer <token>" | jq '.items[].source.name'

# 4. Feed avec filtre theme → sources curated OK (path inchangé)
curl -s "http://localhost:8080/api/feed/?limit=20&theme=tech" -H "Authorization: Bearer <token>" | jq '.items[].source.name'
```

## Comparaison PROD vs LOCAL (extrait des tests précédents)
| Scénario | PROD (bug) | LOCAL (fix) |
|---|---|---|
| Laurin (52 src) sans filtre | 2 followed / 11 non-followed | 2 followed / 0 non-followed |
| Corentin (6 src) sans filtre | 7 followed / 13 non-followed | 17 followed / 0 non-followed |
| User 2 sources sans filtre | 0 followed / 20 non-followed | 20 followed / 0 non-followed |

## Note
Le stash `feat: source suggestions + three-phase fetch (PR B material)` contient le travail restant (source suggestions, three-phase fetch, mobile UI) pour une PR séparée.
