# Epic 12 : Feed Chronologique avec Diversification de Sources

**Status** : 🟡 En cours de planification
**Phase** : Design complet + handoff développeurs
**Mainteneur** : PO (Laurin) + @dev

---

## 🎯 Objectif

Inverser le flux par défaut de Facteur : passer d'un **algorithme de scoring multi-piliers** (opaque, risque de bulle de confirmation) à un **flux chronologique intelligent avec diversification des sources**. L'utilisateur reprend le contrôle direct sur son flux — cohérent avec la philosophie "Slow Media" de Facteur.

## 📋 Vision Produit

### Aujourd'hui
- Mode par défaut : "Pour vous" (scoring IA 4 piliers : Pertinence 40%, Source 25%, Fraîcheur 20%, Qualité 15%)
- Chip secondaire : "Derniers articles" (chrono pur, sans diversification)

### Demain
- Mode par défaut : "Mon flux" (chronologique diversifié par source + préférences user)
- Chip "Pour vous" (ancien scoring, accessible pour comparaison)
- Transparence : l'user comprend exactement pourquoi il voit un article (c'est récent + sa source est suivie)

---

## 🔄 Algô : "Ratio Normalisé"

```
PASSE 1 — Fréquence relative
  Pour chaque source :
    ratio = nb_articles_source / total_articles_pool

PASSE 2 — Quota avec multiplicateurs user
  quota_source = ceil(ratio_normalisé × page_size × priority_multiplier)
  où priority_multiplier ∈ [0.5, 1.0, 2.0]

PASSE 3 — Sélection des articles
  Pour sources > quota :
    garder les N plus récents (MVP: pure recency, pas de matching intérêts)

PASSE 4 — Tri final
  Tous les articles retenus triés par published_at DESC
```

**Note** : Les mutes existantes (sources/thèmes/topics) s'appliquent toujours au niveau SQL.

---

## 🚀 Stories Incluses

| ID | Titre | Effort | Statut |
|---|-------|--------|--------|
| 12.1 | Backend: Algorithme Chronologique Diversifié | 3j | ⏳ À faire |
| 12.2 | Mobile: Inversion des Chips (Chrono défaut + "Pour vous" en chip) | 2j | ⏳ À faire |
| 12.3 | Mobile: Swipe Left → Bottom Sheet Source (Slider + Mute) | 2j | ⏳ À faire |
| 12.4 | Mobile: Tap Source → Source Detail Modal avec Slider | 1j | ⏳ À faire |
| 12.5 | Mobile: Bouton Info Contextuel (Chrono vs Pour Vous) | 1j | ⏳ À faire |
| 12.6 | Mobile: Labels, Textes & Toast Migration | 1j | ⏳ À faire |
| 12.7 | Documentation: Mise à jour Feed | 1j | ⏳ À faire |

**Total estimé** : ~11 jours (peut être parallélisé après 12.1)

---

## 📦 Dépendances

```
12.1 (Backend Algo)
  │
  ├─ 12.2 (Chip Inversion) ──┬─ 12.6 (Labels/Textes)
  │                            │
  ├─ 12.3 (Swipe Bottom Sheet) ├─ 12.5 (Info Contextuel)
  │                            │
  └─ 12.4 (Tap Source)         └─ 12.7 (Docs)
```

**Ordre recommandé** : 12.1 → 12.2 → (12.3 + 12.4 + 12.6 en parallèle) → 12.5 → 12.7

---

## ✅ Critères de Succès (Epic-wide)

- [ ] Feed par défaut est chronologique diversifié (pas de chip sélectionnée)
- [ ] "Pour vous" est accessible en chip #2
- [ ] Slider source contrôle la fréquence d'apparition (0.5/1.0/2.0)
- [ ] Swipe left → bottom sheet avec slider (pas banner inline)
- [ ] Tap source → modal detail avec slider ajustable
- [ ] Toast one-shot migration explique le changement aux users existants
- [ ] Tous les textes (Mes Intérêts, Sources, explications) sont à jour
- [ ] Digest inchangé (scoring existant préservé)
- [ ] Zéro régression : "Pour vous" ≈ ancien défaut

---

## ⚠️ Risques Identifiés

| Risque | Impact | Mitigation |
|--------|--------|-----------|
| Pagination instable en chrono | User voit doublons/sauts de pages | Tester pagination multi-page en chrono |
| Sources rares avec multiplier 2.0× créent quota vide | Flux clairsemé | Utiliser `max(1, quota)` pour toute source suivie |
| User perd compréhension de la sélection | UX confusion | Toast + textes explicites sur le défaut chrono |
| Scoring 4-piliers devient dette tech | Maintenance future | Documenter bien, laisser porte ouverte dépréciaton post-MVP |

---

## 📚 Fichiers Clés à Modifier

### Backend
- `packages/api/app/models/enums.py` — Ajouter `CHRONOLOGICAL`, `POUR_VOUS`
- `packages/api/app/services/recommendation_service.py` — Nouvelle méthode `_apply_chronological_diversification()`
- `packages/api/app/routers/feed.py` — Routing entre modes

### Mobile
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — Filter bar, chip wiring
- `apps/mobile/lib/features/feed/providers/theme_filters_provider.dart` — Remplacer `recentFilter` par `pourVousFilter`
- **Nouveau** : `apps/mobile/lib/features/feed/widgets/source_adjust_sheet.dart`
- `apps/mobile/lib/features/sources/widgets/source_detail_modal.dart` — Ajouter slider
- `apps/mobile/lib/features/feed/widgets/dismiss_banner.dart` — Déprécier (remplacé par bottom sheet)

---

## 🧪 Plan de Vérification

Chaque story a un script QA dans `docs/qa/scripts/verify_epic_12_<story>.sh` :
- 12.1 : curl feed endpoint, vérifier ordres différents (mode=null vs mode=pour_vous)
- 12.2 : UI mobile, vérifier chips
- 12.3 : Swipe left → bottom sheet
- 12.4 : Tap source → modal
- 12.5 : ℹ️ contextuel
- 12.6 : Grep "Explorer", SharedPreferences toast
- 12.7 : Revue docs

**Régressions à checker**:
- Digest inchangé
- "Pour vous" ≈ ancien défaut
- Mutes toujours actifs
- Pagination cohérente

---

## 📖 Docs à Mettre à Jour (Story 12.7)

- `docs/prd.md` — Feed section
- `docs/architecture.md` — Recommendation service section
- `docs/front-end-spec.md` — Feed UI section
- `docs/data-architecture/` (si existe) — Feed filtering
- Stories existantes si elles référencent l'algo

---

## 🔗 Références

- **Brainstorming complet** : `.context/epic-12-brainstorming.md`
- **Plan technique détaillé** : `.context/epic-12-plan.md` (créé par PO)
- **CLAUDE.md** : Méthodologie BMAD, guardrails, hooks
