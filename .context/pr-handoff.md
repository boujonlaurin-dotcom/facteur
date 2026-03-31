# Handoff — Fix CTA Footer Chips: Logos + Remove Dots

## Contexte

La branche `boujonlaurin-dotcom/feed-grouping-rework` a introduit des CTA footers sous les cartes du feed. Ces bandeaux indiquent "N autres articles sur/de X" et permettent de filtrer le feed.

**Deux problèmes visuels persistent après une première passe de correctifs :**
1. Les logos de source n'apparaissent sur aucun type de CTA footer
2. Les caractères `•` (bullet `\u2022`) persistent dans le texte des footers

---

## Architecture du rendering (CRITIQUE à comprendre)

### Priority chain (feed_screen.dart:842-859)

```
content.clusterHiddenCount > 0       →  ClusterChip          (Priority 1)
  : content.keywordOverflowCount > 0 →  KeywordOverflowChip  (Priority 2)
  : content.topicOverflowCount > 0   →  TopicOverflowChip    (Priority 3)
  : SourceOverflowChip                                       (Priority 4 / fallback)
```

### Ce qui est RÉELLEMENT rendu en prod

En pratique, les chips qui s'affichent le plus souvent sont :
- **ClusterChip** (priorité 1) — pour les utilisateurs avec des custom topics suivis
- **SourceOverflowChip** (priorité 4, fallback) — quand aucun autre regroupement ne s'applique

Les KeywordOverflowChip et TopicOverflowChip n'apparaissent que rarement (seulement en mode chronologique, et seulement si le keyword mining produit des groupes viables).

### Conséquence

**Le premier agent a modifié TopicOverflowChip et SourceOverflowChip pour ajouter des logos, mais n'a JAMAIS touché ClusterChip** — qui est le chip le plus couramment affiché. C'est pourquoi l'utilisateur ne voit aucun logo.

---

## Problème 1 : Aucun logo sur les CTA footers

### État actuel par type de chip

| Chip | Fichier | Logo actuel | Données source disponibles |
|------|---------|-------------|---------------------------|
| **ClusterChip** | `apps/mobile/lib/features/custom_topics/widgets/cluster_chip.dart` | ❌ Aucun logo, aucune donnée source | Le widget reçoit un `Content` (la carte représentante). `content.source` est disponible (nom + logoUrl). Mais les sources des articles cachés ne sont PAS dans les données cluster. |
| **KeywordOverflowChip** | `apps/mobile/lib/features/feed/widgets/keyword_overflow_chip.dart` | ✅ Multi-logos fonctionnels | `content.keywordOverflowSources` contient une liste de `KeywordOverflowSource` avec `sourceId`, `sourceName`, `sourceLogoUrl`, `articleCount`. |
| **TopicOverflowChip** | `apps/mobile/lib/features/feed/widgets/topic_overflow_chip.dart` | ⚠️ Code ajouté mais jamais testé/affiché | L'agent a ajouté `topicOverflowSources` (même format que keyword). Le backend a été modifié pour envoyer `sources` dans `topic_overflow`. |
| **SourceOverflowChip** | `apps/mobile/lib/features/feed/widgets/source_overflow_chip.dart` | ⚠️ Code ajouté mais layout potentiellement incorrect | L'agent a déplacé le logo à droite du texte. Utilise `content.source.logoUrl` (une seule source, logique puisque source overflow = même source). |

### Fix requis

#### 1a — ClusterChip : Ajouter les logos (le plus impactant)

**Backend** (`packages/api/app/services/recommendation_service.py`, méthode `build_clusters()` L1535-1558) :

Le cluster dict actuel ne contient que :
```python
{
    "topic_slug": slug,
    "topic_name": topic_map[slug],
    "representative_id": representative.id,
    "hidden_count": len(others),
    "hidden_ids": [a.id for a in others],
}
```

→ Ajouter un champ `sources` (même format que keyword overflow) :
```python
"sources": [unique sources from all articles in the group, with article_count]
```

**Mobile model** (`content_model.dart`) :
- `FeedCluster` → ajouter `final List<KeywordOverflowSource> sources;`
- `Content` → ajouter `final List<KeywordOverflowSource> clusterSources;`
- Mettre à jour constructor, `copyWith`, `clearNote`

**Mobile repository** (`feed_repository.dart`, section cluster annotation ~L139-149) :
- Parser le nouveau `sources` dans `FeedCluster.fromJson`
- Passer `clusterSources` dans le `copyWith` lors de l'annotation du representant

**Mobile widget** (`cluster_chip.dart`) :
- Ajouter le multi-logo pattern à droite du texte (même layout que `keyword_overflow_chip.dart`)
- Utiliser `content.clusterSources` comme data source
- Import `initial_circle.dart` + `facteur_image.dart`

#### 1b — Vérifier que SourceOverflowChip affiche bien le logo

Le code est déjà en place (réécrit par le premier agent). Vérifier que :
- `content.source.logoUrl` n'est pas null pour les sources concernées
- Le layout est correct (logo à droite du texte, avant la flèche →)
- Le fallback `InitialCircle` fonctionne quand logoUrl est null

#### 1c — Vérifier que TopicOverflowChip fonctionne aussi

Le code est en place. Le backend envoie `sources` dans `topic_overflow`. Vérifier le flow complet.

---

## Problème 2 : Caractères "•" (bullet) dans le texte des footers

### Root cause

Le commit `eeef2fa8` a introduit `\u2022` (bullet Unicode) dans les strings de texte de 3 widgets :

| Fichier | Ligne originale | État actuel |
|---------|----------------|-------------|
| `cluster_chip.dart:66` | `'... sur \u2022 $topicName'` | Fix unstaged (diff enlève le `\u2022`) |
| `source_overflow_chip.dart:73` | `'... de \u2022 ${content.source.name}'` | Réécrit par l'agent (plus de `\u2022`) |
| `topic_overflow_chip.dart:62` | `'... \u2022 ${content.topicOverflowLabel}'` | Réécrit par l'agent (plus de `\u2022`) |

### Fix requis

- **cluster_chip.dart** : Le fix est déjà dans le working tree (diff unstaged). Vérifier qu'il est bien appliqué.
- **source_overflow_chip.dart** et **topic_overflow_chip.dart** : Déjà fixés par la réécriture de l'agent.
- **keyword_overflow_chip.dart** : N'a jamais eu de `\u2022`.

---

## Design des logos dans les CTA footers

Le pattern de référence est dans `keyword_overflow_chip.dart` (le seul qui fonctionne aujourd'hui) :

```
[> caret]  [Texte label ............]  [logo1 logo2 logo3 +N]  [→]
```

- Logos 14x14px, ClipOval
- Max 3 logos visibles, puis "+N" pour le reste
- Sources avec logo en premier (tri par `logoUrl != null`)
- Fallback : `InitialCircle` (cercle coloré + initiale) — widget partagé dans `initial_circle.dart`
- Le widget `InitialCircle` existe déjà dans `apps/mobile/lib/features/feed/widgets/initial_circle.dart`

---

## Fichiers à modifier

### Backend (1 fichier)
- `packages/api/app/services/recommendation_service.py` L1550-1558 : Ajouter `sources` au dict cluster

### Schema (potentiellement)
- `packages/api/app/schemas/feed.py` : Ajouter `sources` à `ClusterInfo` si le schema est validé côté router

### Mobile (4-5 fichiers)
- `apps/mobile/lib/features/feed/models/content_model.dart` : `FeedCluster.sources`, `Content.clusterSources`
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart` : Parser + annoter `clusterSources`
- `apps/mobile/lib/features/custom_topics/widgets/cluster_chip.dart` : Multi-logos à droite + vérifier suppression `\u2022`
- `apps/mobile/lib/features/feed/widgets/source_overflow_chip.dart` : Vérifier layout logo à droite (déjà modifié)
- `apps/mobile/lib/features/feed/widgets/topic_overflow_chip.dart` : Vérifier layout multi-logos (déjà modifié)

### NE PAS toucher
- `keyword_overflow_chip.dart` — fonctionne déjà correctement
- `feed_screen.dart` — la priority chain est correcte
- `feed_provider.dart` — aucun changement nécessaire

---

## Vérification

Après modification, sur Chrome (`flutter run -d chrome`) :

1. **ClusterChip** ("N autres articles sur Topic") : doit afficher 1-3 logos source à droite du texte
2. **SourceOverflowChip** ("N autres articles de Source") : doit afficher 1 logo source à droite
3. **TopicOverflowChip** ("N autres articles Label") : doit afficher 1-3 logos à droite
4. **Aucun** footer ne doit contenir le caractère "•"
5. Quand `logoUrl` est null, un cercle avec initiale colorée (InitialCircle) doit apparaître en fallback

---

## Changements déjà effectués par le premier agent (à conserver/ajuster)

Ces changements sont dans le working tree. Ils sont globalement corrects mais le focus était mal ciblé :

**Backend :**
- ✅ `scoring_config.py` : `KEYWORD_MIN_LENGTH` baissé de 5 à 4
- ✅ `recommendation_service.py` : Seuil adaptatif `min_kw = 2` si `retained < 15`
- ✅ `recommendation_service.py` : `sources` list dans topic_overflow_info (L876-895)
- ✅ `schemas/feed.py` : `OverflowSourceInfo` partagé + `sources` sur `TopicOverflowInfo`

**Mobile :**
- ✅ `initial_circle.dart` : Widget partagé extrait
- ✅ `keyword_overflow_chip.dart` : Import du widget partagé, suppression du privé
- ✅ `content_model.dart` : `TopicOverflow.sources`, `Content.topicOverflowSources`
- ✅ `feed_repository.dart` : Passage de `topicOverflowSources`
- ⚠️ `topic_overflow_chip.dart` : Multi-logos ajoutés (correct mais jamais testé)
- ⚠️ `source_overflow_chip.dart` : Logo unique à droite (correct mais jamais testé)
- ❌ `cluster_chip.dart` : NON MODIFIÉ — c'est le widget le plus visible, et le seul vraiment manquant
