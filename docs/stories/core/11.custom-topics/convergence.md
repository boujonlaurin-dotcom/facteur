# Epic 11 — Convergence : Questions Ouvertes

**Date :** 2026-03-02 (v2 — itération 1)
**Auteur :** PO / Architect Agent (BMAD)
**Statut :** Proposition finale — en attente de validation

---

## Q1 : Page "Mes Intérêts" — Contenu exact et interactions

### Décision proposée (v2)

La page **"Mes Intérêts"** est le cœur de la promesse de transparence de Facteur : "C'est *ton* algorithme". Elle se structure en **une vue unifiée** : thèmes macro et custom topics vivent ensemble, sans séparation.

#### Zone 1 — Header

```
┌─────────────────────────────────────────┐
│  ← Retour          Mes Intérêts         │
├─────────────────────────────────────────┤
│                                         │
│  🧠 Ton algorithme, tes règles.         │
│  Facteur apprend de tes lectures.       │
│  Ici, tu reprends le contrôle.          │
│                                         │
```

> **Pas de CTA "Ajouter un sujet" global.** La discovery de nouveaux topics se fait **in-situ**, au sein de chaque thème (voir Zone 2).

#### Zone 2 — Thèmes & Topics unifiés

Les **thèmes macro** et les **custom topics** vivent dans le même niveau hiérarchique. Chaque section de thème affiche :
1. Le thème lui-même avec son curseur 3 crans
2. Les topics que l'utilisateur suit déjà sous ce thème, chacun avec son curseur
3. **3-4 suggestions de topics** que l'utilisateur semble aimer mais ne suit pas encore (basées sur ses lectures récentes)

Tous les `ExpansionTile` sont **ouverts par défaut**.

```
┌─────────────────────────────────────────┐
│  🔬 TECH & FUTUR                    ▾   │  ← ExpansionTile (OUVERT)
├─────────────────────────────────────────┤
│                                         │
│  🔬 Tech & Futur (thème)               │  ← Le thème macro lui-même
│  ┌─ Intérêt ───────────────────────┐    │
│  │  ◼ ◼ ◼                         │    │  ← 3 crans (set à 3/3 ici)
│  │  Suivi · Intéressé · Fort       │    │
│  └─────────────────────────────────┘    │
│                                         │
│  📌 Intelligence Artificielle           │  ← Topic custom suivi
│  ┌─ Intérêt ───────────────────────┐    │
│  │  ◼ ◼ ◻                         │    │  ← 2/3 = "Intéressé"
│  │  Suivi · Intéressé · Fort       │    │
│  └─────────────────────────────────┘    │
│  Sources : Développeur.com · The Verge  │
│  [→ Voir mes sources]                    │
│                                         │
│  📌 GPT-5                               │  ← Topic custom suivi
│  ┌─ Intérêt ───────────────────────┐    │
│  │  ◼ ◻ ◻                         │    │  ← 1/3 = "Suivi"
│  │  Suivi · Intéressé · Fort       │    │
│  └─────────────────────────────────┘    │
│  Sources : The Verge                    │
│  [→ Voir mes sources]                    │
│                                         │
│  ── Suggestions pour toi ───────────── │  ← Divider
│                                         │
│  ○ Cybersécurité          [+ Suivre]    │  ← Topic suggéré (non suivi)
│  ○ Blockchain             [+ Suivre]    │     Basé sur les lectures récentes
│  ○ Robotique              [+ Suivre]    │     de l'utilisateur dans ce thème
│                                         │
├─────────────────────────────────────────┤
│  🌍 SOCIÉTÉ & CLIMAT                ▾   │  ← OUVERT par défaut aussi
├─────────────────────────────────────────┤
│                                         │
│  🌍 Société & Climat (thème)            │
│  ┌─ Intérêt ───────────────────────┐    │
│  │  ◼ ◼ ◻                         │    │  ← 2/3 (défaut estimé)
│  └─────────────────────────────────┘    │
│                                         │
│  (Aucun topic custom suivi)             │
│                                         │
│  ── Suggestions pour toi ───────────── │
│                                         │
│  ○ Mobilité douce         [+ Suivre]    │
│  ○ Biodiversité           [+ Suivre]    │
│  ○ Énergie renouvelable   [+ Suivre]    │
│                                         │
├─────────────────────────────────────────┤
│  💰 ÉCONOMIE                         ▾   │
├─────────────────────────────────────────┤
│  ...                                     │
└─────────────────────────────────────────┘
```

**Curseur 3 crans :**

| Cran | Label | Multiplicateur Boost | Quand |
|------|-------|---------------------|-------|
| 1/3 | Suivi | ×0.5 | "Je veux le voir passer, mais pas en priorité" |
| 2/3 | Intéressé | ×1.0 (défaut) | "C'est un de mes centres d'intérêt" |
| 3/3 | Fort intérêt | ×2.0 | "C'est mon sujet prioritaire, montrez-moi tout" |

> **3 crans, pas 5** — Réduit la paralysie décisionnelle. Les labels sont intuitifs et ne demandent pas de réfléchir à des nuances subtiles.

**Thèmes macro = même traitement que les topics :**
- Ils ont leur curseur 3 crans comme les topics
- Valeur par défaut = **2/3** (estimée) si l'utilisateur n'a pas explicitement ajusté
- L'utilisateur peut baisser à 1/3 ou monter à 3/3
- **Pour "désélectionner" un thème** → l'utilisateur peut swipe-to-delete le thème (avec confirm dialog : "Tu ne verras plus d'articles dans ce thème sauf ceux matchant tes topics. Continuer ?")

> **Pourquoi ne pas juste mettre un toggle ON/OFF ?** Parce que le curseur 3 crans est plus nuancé. Un toggle forcerait un choix binaire alors que "Suivi mais pas prioritaire" (1/3) est un état valide et courant.

**Suggestions de topics — Logique :**

| Source des suggestions | Règle |
|----------------------|-------|
| Slugs Mistral les plus lus par l'utilisateur | Top 3-4 `content.topics[]` les plus fréquents dans les 30 derniers jours |
| Filtrage | Exclure les topics déjà suivis |
| Groupement | Suggestions rattachées au thème parent correct |

Quand l'utilisateur clique **[+ Suivre]** sur une suggestion :
1. Le topic est instantanément ajouté à la liste (animation slide-in)
2. Le curseur apparaît au cran **2/3 par défaut**
3. Un call LLM one-shot est déclenché en arrière-plan pour enrichir le topic (keywords, intent)
4. Toast : "Cybersécurité ajouté ✓"

> **Pas d'input libre pour le MVP.** Les suggestions couvrent 90% des cas. L'input libre (tape un sujet → LLM catégorise) peut être ajouté en V2 via un CTA "Autre sujet…" en bas de chaque section, si les données montrent que les suggestions ne suffisent pas.

#### CTA d'entrée — Wording et placement

| Point d'entrée | Wording | Écran |
|----------------|---------|-------|
| Modale Day 2 | "**Personnaliser mon feed** ❯" | Modale plein écran |
| Nudge post-lecture | "**Suivre ce sujet** → Régler la priorité" | Bottom sheet |
| Chip topic dans le feed | "**IA ☑️**" → ouvre la page | Footer carte |
| Settings > Profil | "**Mes Intérêts**" (premier item) | Liste Settings |
| Onboarding S3 (bonus) | "💡 Pour aller plus loin : **Personnalise ton algorithme**" | Bas de page Thèmes |

---

## Q2 : Feed Clustering — Comportement exact

### Décision proposée (v2)

#### Règle 1 : Les articles clusterisés sont **masqués** du feed principal

Quand le système détecte ≥3 articles du même topic dans la page courante, il :
1. **Garde 1 article représentatif** dans le flux (le plus scoré)
2. **Masque les N-1 autres** du feed principal
3. **Affiche une chip de cluster** sous l'article représentatif

#### Règle 2 : Au tap sur la chip → **Navigation push vers Topic Explorer**

```
Chip "▸ 4 articles sur l'IA" → Push navigation : Topic Explorer
```

**Topic Explorer** = un feed filtré dédié au topic, avec :
- Header contextuel (nom du topic, icône thème parent)
- Liste des articles du cluster + articles plus anciens du topic
- Même composant `ContentCard` que le feed principal
- Si topic **non suivi** : CTA **"[+ Suivre]"** en haut
- Si topic **déjà suivi** : CTA **"Modifier la priorité"** → ouvre le curseur 3 crans inline *(pas de "Ne plus suivre" pour l'instant)*

#### Règle 3 : Interaction Clustering × Filtres header

| Scénario | Comportement |
|----------|-------------|
| **Aucun filtre actif** | Le feed affiche les clusters. Les articles clusterisés sont masqués sauf l'article représentatif. |
| **Filtre thème macro actif** (ex: "Tech") | Les clusters du thème restent visibles. Les articles d'autres thèmes sont masqués. |
| **Filtre topic custom actif** (ex: chip "IA") | **Le cluster explose** : tous les articles IA deviennent visibles dans le feed, triés par score. Le cluster IA disparaît. |

#### Règle 4 : Contraintes d'affichage des clusters

| Contrainte | Valeur | Raison |
|-----------|--------|--------|
| Articles minimum pour cluster | ≥ 3 | En dessous, pas de valeur ajoutée |
| Max clusters par page | 2-3 | Évite de transformer le feed en index |
| Sources diversifiées requises | ≥ 2 sources | Mono-source ≠ vrai sujet |
| Fraîcheur max des articles | 48h | Au-delà, trop vieux pour un cluster "actu" |

#### Règle 5 : Hot News vs Niches — Cadrage

> [!IMPORTANT]
> **Risque identifié et accepté comme out-of-scope.**

Le scoring composite fait remonter naturellement les articles "chauds" (freshness_score élevé, volume) en tête de feed. Les custom topics se regroupent en clusters sans monopoliser.

**Cependant**, un sujet "hot" non suivi (ex: "Affaire Epstein", "Crise au Venezuela") **peut passer au travers** des topics niches de l'utilisateur — il ne sera ni clusterisé en tant que tel, ni mis en avant spécifiquement.

**Position :**
- Le **feed** ne résout pas ce problème seul. Il faudrait un clustering séparé "Hot Topics du jour" (détection de sujets tendance à l'échelle globale) — c'est un chantier UX/backend complexe, hors-scope Epic 11.
- Le **Digest** est le levier naturel pour cette promesse : "les sujets importants du jour que tu aurais pu manquer". C'est l'EPIC "résumé d'info" qui devra adresser ce besoin.
- **Mitigation MVP** : les articles hot scorent haut via la fraîcheur. S'ils sont sur un thème que l'utilisateur suit (même à cran 1/3), ils apparaîtront. Le vrai trou = un sujet hors de tous les thèmes suivis. → Accepter cette limitation pour le MVP.

---

## Résumé des décisions à intégrer dans le story file

| # | Question | Décision |
|---|----------|----------|
| Q1a | Structure page | Vue unifiée : thèmes macro + topics dans les mêmes sections, pas de séparation |
| Q1b | Curseur | 3 crans : Suivi (×0.5) / Intéressé (×1.0) / Fort intérêt (×2.0). Défaut 2/3 |
| Q1c | Ajout de topic | Pas d'input libre (MVP). Suggestions in-situ (3-4 topics par thème basés sur lectures). Clic → suivi + LLM enrichissement en background |
| Q1d | Thèmes macro | Même traitement que les topics : curseur 3 crans, suppressibles (swipe-to-delete) |
| Q1e | ExpansionTiles | Tous ouverts par défaut |
| Q2a | Masquage cluster | MASQUÉS sauf 1 représentatif |
| Q2b | Tap cluster | Push → Topic Explorer |
| Q2c | Topic Explorer suivi | "Modifier la priorité" (pas de "Ne plus suivre") |
| Q2d | Filtre + Cluster | Filtre topic = cluster explose inline |
| Q2e | Hot News vs Niches | Out-of-scope. Le Digest est le levier adéquat. Risque accepté pour le MVP |

---

## Q3 : Points d'Architecture Backend (Itération 2)

### Q3a : Lien Topics ↔ Sources
**Décision :** La connexion est déjà robuste. Les sources possèdent un champ `granular_topics`. Le worker Mistral (`classification_worker.py`) utilise déjà ce champ en fallback (si échec ML) et le valide contre la liste centralisée `VALID_TOPIC_SLUGS`. L'endpoint de suggestions utilisera simplement ce même mapping direct.

### Q3b : Évolution des Slugs & Thèmes (Ajout "Sport", "Robotique"...)
**Décision :** Les modifications de taxonomie sont devenues simples. Contrairement au front-end hardcodé du passé, la logique vit uniquement dans l'API (`classification_service.py` et `topic_theme_mapper.py`).
- Le thème "Sport" **est déjà implémenté** dans la base `VALID_THEMES`.
- Le prompt Mistral prend dynamiquement de notre mapping. Ajouter des catégories se fera sans modifier le modèle, juste par une PR de configuration.

### Q3c : Rééquilibrage du Score (Fraîcheur vs Personnalisation)
**Décision :** Le problème de domination des vieux articles est identifié (`core.py`, `scoring_config.py`). Actuellement la fraîcheur max à **30 points** alors que l'affinité topic parfaite peut cumuler **~175 points**.
- **Action (Phase 3) :** Cap max des bonus de personnalisation ou hausse de la `recency_base` à 100+ points. La personnalisation ne doit pas écraser l'actualité brûlante à ce point.

### Q3d : Désynchronisation des Slugs (Article ↔ Topic Suivi)
**Décision :** Le risque est nul par design (Single Source of Truth). Le LLM qui classifie les articles et l'endpoint qui crée les Custom Topics utilisent scrupuleusement le même validateur (`VALID_TOPIC_SLUGS`). Une orthographe divergente sera rejetée avant l'insertion en base.
