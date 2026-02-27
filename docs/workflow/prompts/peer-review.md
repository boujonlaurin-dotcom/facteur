# Prompt : Peer Review Conductor

> Utilisation : colle ce prompt dans un NOUVEAU workspace Conductor ouvert sur la branche à reviewer.

---

Lis `.context/pr-handoff.md` pour comprendre le contexte du changement, puis review le workspace diff en tant que senior developer.

**Checklist de review :**
1. **Security** : injection, auth bypass, secrets exposés, CORS
2. **Guardrails Facteur** : Python `list[]` (jamais `List[]`), Supabase stale token, worktree isolation
3. **Breaking changes** : contrat API modifié, schema DB sans migration, endpoints supprimés
4. **Test coverage** : nouveaux chemins de code sans tests, edge cases manqués
5. **Architecture** : respect des patterns (Riverpod, Repository, Service layer)
6. **Performance** : N+1 queries, index manquants, requêtes non bornées

**Actions :**
- Utilise `DiffComment` pour laisser tes commentaires directement sur les lignes de code concernées.
- Si tu identifies un point dans "Zones à risque" du handoff, vérifie-le en priorité.

**Output final :**
- **BLOCKERS** : à corriger obligatoirement avant merge
- **WARNINGS** : à corriger de préférence, merge possible avec justification
- **SUGGESTIONS** : améliorations optionnelles
- Verdict : **APPROVED** ou **NOT APPROVED**
