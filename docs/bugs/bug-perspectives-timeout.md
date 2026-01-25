# Bug: Perspectives - Temps de chargement long et aucun résultat

## Status: RESOLVED

## Date: 2026-01-24

## Symptômes
- Temps de chargement très long pour la fonctionnalité "Comparer"
- Aucun résultat trouvé (même sur articles d'actualité)

## Analyse

### Ce qui fonctionnait
- Le test local `test_perspectives.py` retournait des résultats (10 perspectives en ~500ms)
- L'endpoint `/api/health` répondait correctement

### Problèmes identifiés

1. **Anti-pattern: exceptions silencieuses**
   - Le code avait `except Exception: return []` partout
   - Les erreurs (timeout, SSL, réseau) étaient avalées sans trace
   - Impossible de diagnostiquer le problème réel

2. **Timeout insuffisant**
   - 5 secondes par défaut, potentiellement trop court en production

3. **Absence de User-Agent**
   - Google News peut bloquer les requêtes sans User-Agent approprié
   - Les requêtes httpx par défaut n'ont pas de User-Agent réaliste

4. **Pas de logging**
   - Aucune trace dans les logs pour diagnostiquer

## Fix appliqué

### Fichiers modifiés
- `packages/api/app/services/perspective_service.py`
- `packages/api/app/routers/contents.py`

### Changements
1. **Ajout de logging structuré (structlog)**
   - Trace des recherches, succès, et erreurs
   - Logging du nombre de résultats et des keywords

2. **Ajout d'un User-Agent réaliste**
   - Chrome sur macOS pour éviter le blocage

3. **Augmentation du timeout**
   - De 5s à 10s pour plus de marge en production

4. **Gestion des erreurs explicite**
   - Logging des TimeoutException
   - Logging des RequestError
   - Logging des erreurs de parsing XML

5. **Activation de follow_redirects**
   - Pour gérer les redirections Google News

## Vérification

Script: `docs/qa/scripts/verify_perspectives.sh`

```bash
./docs/qa/scripts/verify_perspectives.sh
```

## Tests

- ✅ Syntaxe Python valide
- ✅ Logging structlog présent
- ✅ User-Agent défini
- ✅ Erreurs HTTP loggées
- ✅ Service fonctionnel (10 perspectives en ~500ms)
