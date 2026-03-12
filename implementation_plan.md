# Plan d'implémentation: Fix Feed 500 - topics NULL

**Bug**: Feed endpoint retourne 500 car `topics=None` n'est pas transformé en `[]`
**Root Cause**: `field_validator` ne fonctionne pas sur Railway malgré qu'il fonctionne localement
**Branche**: `dev-feed-topics-null-fix`

---

## 🔍 Analyse Root Cause

### Tests Effectués ✅
1. ✅ Validator fonctionne localement (test_validator.py)
2. ✅ Héritage `FeedItemResponse` → `ContentResponse` fonctionne (test_validator_inheritance.py)
3. ✅ Code validator existe dans main (commit `599ba1a`, PR #65)
4. ✅ `field_serializer` fonctionne aussi localement (test_serializer.py)

### Conclusion
- Code correct et présent dans main
- Validator fonctionne en local mais **PAS sur Railway**
- **TOUS** les items échouent (pas seulement item 19)
- Problème d'environnement Railway ou cache Python

---

## 🛠️ Solution Proposée

### Approche 1: Remplacer `field_validator` par `field_serializer` (RECOMMANDÉ)

**Pourquoi:**
- `field_serializer` s'exécute lors de la sérialisation JSON (plus robuste)
- `field_validator` s'exécute pendant la construction de l'objet (peut être skippé avec `from_attributes`)
- Plus explicite et prévisible

**Changement:**
```python
# AVANT (approche actuelle - ne marche pas sur Railway)
@field_validator('topics', mode='before')
@classmethod
def coerce_topics(cls, v: object) -> list[str]:
    """ORM topics peut être NULL en base → toujours retourner une liste."""
    return v if v is not None else []

# APRÈS (approche robuste)
@field_serializer('topics', when_used='always')
def serialize_topics(self, value: Optional[list[str]]) -> list[str]:
    """ORM topics peut être NULL en base → toujours retourner une liste."""
    return value if value is not None else []
```

**Fichiers à modifier:**
- `packages/api/app/schemas/content.py:67-71`

**Import à ajouter:**
```python
from pydantic import BaseModel, field_serializer  # Ajouter field_serializer
```

### Approche 2: Fix dans le service (FALLBACK si Approche 1 échoue)

Si `field_serializer` ne marche toujours pas, fixer directement dans le service avant de retourner les objets:

```python
# Dans recommendation_service.py, ligne ~227
result = [item[0] for item in scored_candidates[start:end]]

# AJOUTER après cette ligne:
for content in result:
    if content.topics is None:
        content.topics = []
```

### Approche 3: Fix au niveau ORM (SOLUTION PERMANENTE - pour plus tard)

Modifier le modèle ORM pour que `topics` ne soit jamais NULL:

```python
# Dans packages/api/app/models/content.py:62
topics: Mapped[list[str]] = mapped_column(
    ARRAY(Text),
    nullable=False,  # Changer de True à False
    server_default="'{}'"  # Default SQL = array vide
)
```

**Nécessite:**
- Migration Alembic pour UPDATE tous les NULL → []
- Plus de changements, plus risqué

---

## 📋 Steps d'Implémentation

### Step 1: Implémenter Approche 1 (field_serializer)
- [ ] Modifier `packages/api/app/schemas/content.py`
- [ ] Remplacer `field_validator` par `field_serializer`
- [ ] Ajouter import `field_serializer`
- [ ] Tester localement avec `test_serializer.py`

### Step 2: Ajouter Logging de Debug
- [ ] Ajouter log dans le serializer pour confirmer qu'il s'exécute sur Railway
- [ ] Log format: `logger.debug("topics_serializer_called", value=value, content_id=...)`

### Step 3: Commit & Push
- [ ] Commit avec message clair
- [ ] Push vers branche `dev-feed-topics-null-fix`
- [ ] Créer PR vers main

### Step 4: Vérifier Déploiement Railway
- [ ] Attendre le build Railway
- [ ] Vérifier les logs Railway pour voir si le nouveau code est déployé
- [ ] Force restart du container si nécessaire

### Step 5: Tester en Production
- [ ] Tester `GET /api/feed/` avec un compte qui a des articles avec `topics=NULL`
- [ ] Vérifier les logs pour voir si le serializer est appelé
- [ ] Confirmer que le feed retourne 200 avec `topics: []`

### Step 6: Fallback si Échec
- [ ] Si Approche 1 échoue, implémenter Approche 2 (fix dans service)
- [ ] Ajouter TODO pour Approche 3 (migration ORM) plus tard

---

## 🧪 Tests de Vérification

### Test Local
```bash
cd packages/api && source venv/bin/activate
python ../../test_serializer.py
# Expected: Both tests pass
```

### Test Production (après déploiement)
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  "https://facteur-production.up.railway.app/api/feed/?limit=20" \
  | jq '.items[] | select(.topics == null)'

# Expected: Empty output (no null topics)
```

### Test QA Script (à créer)
```bash
#!/bin/bash
# docs/qa/scripts/verify_feed_topics_not_null.sh

echo "🧪 Testing feed topics field..."

RESPONSE=$(curl -s -H "Authorization: Bearer $FACTEUR_TEST_TOKEN" \
  "$API_BASE_URL/api/feed/?limit=50")

NULL_COUNT=$(echo "$RESPONSE" | jq '[.items[] | select(.topics == null)] | length')

if [ "$NULL_COUNT" -eq 0 ]; then
  echo "✅ PASS: No null topics in feed"
  exit 0
else
  echo "❌ FAIL: Found $NULL_COUNT items with null topics"
  echo "$RESPONSE" | jq '.items[] | select(.topics == null) | {id, title, topics}'
  exit 1
fi
```

---

## 🚨 Risques

| Risque | Probabilité | Impact | Mitigation |
|--------|-------------|--------|------------|
| `field_serializer` ne marche pas non plus sur Railway | Faible | Élevé | Utiliser Approche 2 (fix dans service) |
| Cache Python sur Railway | Moyen | Moyen | Force restart du container |
| Régression sur digest | Faible | Moyen | Digest utilise déjà `topics or []` explicitement |

---

## ✅ Success Criteria

1. **Feed endpoint retourne 200** pour tous les users
2. **Tous les items ont `topics: []` ou `topics: [...]`** (jamais `null`)
3. **Pas de régression** sur le digest
4. **Logs confirment** que le serializer est appelé

---

## 📝 Files Modified (Preview)

```
packages/api/app/schemas/content.py          (1 change: validator → serializer)
docs/qa/scripts/verify_feed_topics_not_null.sh  (nouveau)
docs/bugs/bug-feed-500-topics-null.md       (update: Root Cause + Solution)
```

---

**Estimation**: 30 minutes implementation + 15 minutes tests + attente déploiement Railway
**Priority**: CRITICAL (bloque l'app)
**Ready for approval**: ✅ OUI

---

*Plan créé le: 2026-02-15*
*Agent: @dev*
*Session: dev-feed-topics-null-fix*
