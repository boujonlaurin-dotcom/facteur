# Design Doc — Pipeline Digest Éditorialisé

**Version:** 1.0
**Date:** 10 mars 2026
**Auteur:** Brainstorm Laurin + Claude
**Statut:** Draft — En attente validation

---

## 1. Vue d'ensemble

### 1.1 Objectif

Transformer le digest quotidien de Facteur d'une liste d'articles algorithmiques en un **digest éditorialisé** qui :
- Résume l'actualité chaude en 2-3 phrases par sujet (édito LLM)
- Propose systématiquement un **"pas de recul"** (article deep/systémique) en complément de chaque actu
- Automatise la sélection et la rédaction pour permettre l'itération rapide sur le ton et les critères

### 1.2 Positionnement

Facteur ne dit plus "voilà l'actu". Facteur dit **"voilà pourquoi c'est important — et voici comment comprendre en profondeur"**.

Le digest devient un pont entre l'actualité chaude et les meilleurs articles de fond qui traitent le même sujet de façon structurelle/systémique.

### 1.3 Structure du digest

```
SUJET 1 → Édito + 🔴 L'actu du jour + 🔭 Le pas de recul (swipe)
SUJET 2 → Édito + 🔴 L'actu du jour + 🔭 Le pas de recul (swipe)
SUJET 3 → Édito + 🔴 L'actu du jour + 🔭 Le pas de recul (swipe)
SLOT 4  → 🍀 Pépite du jour (sélection éditoriale)
SLOT 5  → 💚 Coup de cœur (communauté — fallback: 2e pépite)
CLOSURE → "✅ T'es à jour. Bonne journée !"
```

---

## 2. Architecture Pipeline

### 2.1 Vue d'ensemble du flux

```
┌─────────────────────────────────────────────────────┐
│                  SOURCES RSS                         │
│  Mainstream (42 curated) + Deep (20 nouvelles)       │
│  Sync via SyncService existant                       │
└──────────────────┬──────────────────────────────────-┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│          ÉTAPE 1 — DÉTECTION SUJETS CHAUDS           │
│  Algos existants : recoupement multi-sources          │
│  Input : articles < 24h des sources mainstream        │
│  Output : N clusters de sujets chauds                 │
└──────────────────┬──────────────────────────────────-┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│          ÉTAPE 2 — CURATION LLM                      │
│  Model : Claude (configurable)                        │
│  Input : N clusters + contexte éditorial              │
│  Output : 3 sujets retenus + justification            │
│  Prompt : configurable sans code                      │
└──────────────────┬──────────────────────────────────-┘
                   │
           ┌───────┴───────┐
           ▼               ▼
┌──────────────────┐ ┌──────────────────┐
│ ÉTAPE 3A         │ │ ÉTAPE 3B         │
│ MATCH ACTU       │ │ MATCH DEEP       │
│ Sources user     │ │ Sources deep     │
│ > fallback       │ │ (curated, tag    │
│   mainstream     │ │  source_tier:    │
│ Filtre: < 24h    │ │  "deep")         │
│ Filtre: gratuit  │ │ Pas de limite    │
│                  │ │ temps            │
│                  │ │ Filtre: gratuit  │
└────────┬─────────┘ └────────┬─────────┘
         │                    │
         └────────┬───────────┘
                  ▼
┌─────────────────────────────────────────────────────┐
│          ÉTAPE 4 — RÉDACTION ÉDITORIALE (LLM)        │
│  Pour chaque sujet :                                  │
│    - Texte d'intro (2-3 phrases, ton Facteur)         │
│    - Transition narrative vers sujet suivant           │
│  + Closure en fin de digest                            │
│  Prompt : configurable sans code                       │
└──────────────────┬──────────────────────────────────-┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│          ÉTAPE 5 — SLOTS 4 & 5                       │
│  Slot 4 : LLM sélectionne pépite (article surprenant,│
│           décalé, inspirant hors sujets chauds)       │
│  Slot 5 : Query top (likes + saves) sur 48h glissantes│
│           Fallback : 2e pépite LLM                    │
└──────────────────┬──────────────────────────────────-┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│          ÉTAPE 6 — ASSEMBLAGE & STOCKAGE             │
│  Digest complet assemblé en JSON                      │
│  Stocké dans DailyDigest (nouveau format_version)     │
│  Push notification à 8h                               │
└─────────────────────────────────────────────────────-┘
```

### 2.2 Scheduling

| Heure | Action |
|-------|--------|
| 00:00 - 06:00 | RSS sync continue (existant) |
| 06:00 | Trigger pipeline éditoriale batch |
| 06:00 - 07:30 | Étapes 1-6 pour tous les users actifs |
| 08:00 | Push notification "Ton Essentiel est prêt" |

**On-demand fallback** : si un user ouvre l'app avant 8h et que son digest n'est pas prêt, génération à la volée (existant, adapté).

---

## 3. Détail des étapes

### 3.1 Étape 1 — Détection sujets chauds

**Réutilise l'infra existante** du `TopicSelector` et `ImportanceDetector`.

Ce qui change :
- Le clustering est découplé de l'utilisateur : on calcule les **sujets chauds globaux** une seule fois (déjà le cas dans le batch job via `global_trending_context`)
- On extrait les top N clusters (N=10-15) avec leurs articles associés
- Chaque cluster contient : `topic_id`, `label`, `articles[]`, `source_count`, `is_trending`

**Input** : articles des sources mainstream, publiés < 24h
**Output** : liste de `TopicCluster` triés par importance

### 3.2 Étape 2 — Curation LLM

**Nouvelle étape. Appel LLM.**

Le LLM reçoit les N clusters et applique des critères éditoriaux pour en retenir 3.

**Prompt système** (stocké dans config, modifiable sans deploy) :

```
Tu es le rédacteur en chef de Facteur, un média qui aide les Français
à comprendre l'essentiel de l'actualité en 5 minutes.

Parmi les {n} sujets détectés ce matin, sélectionne les 3 plus importants.

Critères de sélection (par ordre de priorité) :
1. Impact réel sur la vie des gens (pas juste du bruit médiatique)
2. Diversité thématique (pas 3 sujets politiques)
3. Intérêt citoyen (le lecteur sera content d'être au courant)
4. Potentiel de "pas de recul" (existe-t-il un angle systémique ?)

Pour chaque sujet retenu, renvoie :
- topic_id
- label (titre court, 5-8 mots)
- selection_reason (1 phrase : pourquoi ce sujet)
- deep_angle (1 phrase : quel angle deep/systémique chercher)

Format : JSON strict.
```

**Input** : `TopicCluster[]` sérialisés (label, article titles, source_count, is_trending)
**Output** : 3 `SelectedTopic` avec `deep_angle` pour guider l'étape 3B

**Config modifiable** :
- Nombre de sujets à sélectionner (default: 3)
- Critères de sélection (texte du prompt)
- Modèle LLM (default: claude-sonnet-4-6 pour le coût, upgradeable)

### 3.3 Étape 3A — Match Actu (sources utilisateur)

**Adapte la logique existante du `DigestSelector`.**

Pour chaque sujet retenu :
1. Chercher un article dans les **sources suivies par l'utilisateur** qui couvre ce sujet
2. Matching : similarity d'embeddings entre le `label` du sujet et les `title` + `topics[]` des articles candidats
3. **Si trouvé** → cet article devient la carte 🔴 L'actu du jour
4. **Si pas trouvé** → fallback vers l'article mainstream le mieux classé du cluster, avec mention "Aucune de tes sources n'a couvert ce sujet"

**Filtres** :
- `published_at` < 24h
- `is_paid = false`
- Pas dans `UserContentStatus` (déjà lu/dismissé)
- Diversité : max 1 article par source (existant)

### 3.4 Étape 3B — Match Deep (sources curated deep)

**Nouvelle étape.**

Pour chaque sujet retenu, on cherche le meilleur article "pas de recul" :

1. **Pool de candidats** : tous les articles des sources avec `source_tier = "deep"` (nouveau champ)
2. **Pas de limite temporelle** : un article deep pertinent peut avoir 6 mois
3. **Matching** : le LLM évalue la pertinence entre le `deep_angle` (étape 2) et les articles candidats
4. **Si match trouvé** → carte 🔭 Le pas de recul, swipeable à côté de l'actu
5. **Si pas de match** → pas de swipe, juste la carte actu classique (dégradation gracieuse)

**Stratégie de matching (2 passes)** :

```
Passe 1 — Pré-filtre rapide (pas de LLM)
  - Keyword/embedding similarity entre deep_angle et article title+topics
  - Filtre : is_paid = false
  - Filtre : source.source_tier = "deep"
  - Retourne top 10 candidats par sujet

Passe 2 — Évaluation LLM
  - Le LLM reçoit le sujet chaud + deep_angle + 10 candidats (titre, source, description, date)
  - Il sélectionne le meilleur (ou "aucun match satisfaisant")
  - Critères : pertinence systémique, qualité, pas événementiel
```

**Config modifiable** :
- Nombre de candidats pré-filtrés (default: 10)
- Prompt de matching deep
- Seuil de pertinence minimum

### 3.5 Étape 4 — Rédaction éditoriale (LLM)

**Nouvelle étape. Appel LLM.**

Le LLM reçoit les 3 sujets avec leurs articles (actu + deep) et génère tout le texte éditorial.

**Prompt système** (configurable) :

```
Tu es le rédacteur de Facteur. Ton style :
- Tutoiement systématique
- Direct, factuel, pas de jargon
- Micro-décryptage : 1 phrase qui donne du recul
- Phrases courtes, rythme rapide
- Emojis structurants uniquement (📌 🚨 🔭 ✅), jamais décoratifs

Pour chaque sujet, génère :
1. intro_text : 2-3 phrases qui résument ce qui s'est passé (chaud)
   ET posent le pont vers l'article deep s'il existe.
   Si pas de deep : juste le résumé chaud.
2. transition_text : 1 phrase de transition vers le sujet suivant
   (ex : "Pendant ce temps, côté tech…", "Et un sujet de fond…")
   Pas de transition après le dernier sujet.

Génère aussi :
3. header_text : titre du digest (ex: "☀️ Ce matin, 3 sujets à retenir")
4. closure_text : phrase de fermeture (toujours inclure "T'es à jour")
5. cta_text : call-to-action feedback

Format : JSON strict.
```

**Variante mode Serein** :

```
[Même prompt mais avec ces ajustements :]
- Pas de 🔴 ni 🚨
- Formulations neutres, pas d'urgence ni d'alarme
- Privilégie la compréhension sur l'impact émotionnel
- Ton rassurant sans être condescendant
```

**Output** :

```json
{
  "header_text": "☀️ Ce matin, 3 sujets + tes pépites",
  "subjects": [
    {
      "topic_id": "...",
      "intro_text": "Trump menace de couper les réseaux...",
      "transition_text": "Pendant ce temps, côté climat…"
    },
    ...
  ],
  "closure_text": "✅ T'es à jour. Bonne journée !",
  "cta_text": "Un truc t'a marqué ? Dis-moi 👋"
}
```

### 3.6 Étape 5 — Slots 4 & 5

#### Slot 4 — 🍀 Pépite du jour

Sélection éditoriale par LLM :
- Pool : tous les articles récents (7 jours) non couverts par les 3 sujets chauds
- Le LLM sélectionne 1 article surprenant/décalé/inspirant
- Prompt configurable avec critères de "pépite" (originalité, surprise, inspiration)
- Mini-édito d'1 phrase : pourquoi c'est une pépite

#### Slot 5 — 💚 Coup de cœur

Signal communautaire :
- Query : article avec le plus de (likes + saves) sur 48h glissantes
- Exclusion : articles déjà dans les slots 1-4
- Badge : "💚 Gardé par {n} lecteurs"
- **Fallback** (si volume users insuffisant) : 2e pépite LLM

### 3.7 Étape 6 — Assemblage & Stockage

Le digest est assemblé dans un nouveau format `editorial_v1` :

```json
{
  "format_version": "editorial_v1",
  "header_text": "...",
  "mode": "pour_vous",
  "subjects": [
    {
      "rank": 1,
      "topic_id": "...",
      "label": "Guerre numérique UE/US",
      "intro_text": "...",
      "transition_text": "...",
      "actu_article": {
        "content_id": "...",
        "title": "...",
        "source_name": "Le Monde",
        "is_user_source": true,
        "badge": "actu"
      },
      "deep_article": {
        "content_id": "...",
        "title": "...",
        "source_name": "The Conversation",
        "badge": "pas_de_recul",
        "published_at": "2025-12-15"
      }
    },
    ...
  ],
  "pepite": {
    "content_id": "...",
    "intro_text": "...",
    "badge": "pepite"
  },
  "coup_de_coeur": {
    "content_id": "...",
    "community_saves": 34,
    "badge": "coup_de_coeur"
  },
  "closure_text": "...",
  "cta_text": "...",
  "generated_at": "2026-03-10T06:45:00Z"
}
```

Stocké dans `DailyDigest.items` (JSONB) avec `format_version = "editorial_v1"`.

---

## 4. Intégration sources deep

### 4.1 Nouveau champ Source

Ajout d'un champ `source_tier` au modèle `Source` :

```python
source_tier = Column(String(20), default="mainstream")
# Valeurs : "mainstream" (default), "deep"
```

Les sources deep sont des sources curated (`is_curated = true`) avec `source_tier = "deep"`.

### 4.2 Pool de sources deep — Lancement

**20 sources actives au lancement :**

#### Sources nativement deep (gratuites)

| Source | Thématique | RSS | source_tier |
|--------|-----------|-----|-------------|
| The Conversation FR | Multi | Oui | deep |
| Bon Pote | Climat/énergie | Oui | deep |
| Vert | Écologie | Oui | deep |
| Socialter | Société/alternatives | Partiel | deep |
| Novethic | RSE/transition | Oui | deep |
| Basta! | Social/économie | Oui | deep |
| Next.ink | Tech/numérique | Oui | deep |
| AOC Media | Culture/société | Oui | deep |
| Mr Mondialisation | Environnement | Oui | deep |
| Usbek & Rica | Prospective | Oui | deep |
| Reporterre | Environnement | Oui | deep |
| Le Grand Continent | Géopolitique | Oui | deep |

#### Sections deep de médias mainstream

| Source | Section | source_tier |
|--------|---------|-------------|
| Le Monde — Les Décodeurs | /les-decodeurs/ | deep |
| France Culture | Articles web | deep |
| Arte — Dossiers | Dossiers | deep |
| La Croix — À vif | /a-vif/ | deep |
| Courrier International | Analyses | deep |
| Slate FR | Explainers | deep |
| Numerama | Décryptages | deep |
| France Info — Analyses | Vrai ou Fake | deep |

### 4.3 Intégration dans le RSS sync

Les sources deep sont traitées comme les sources curated existantes :
- Ajoutées dans `sources_master.csv` avec `Status: CURATED` et `source_tier: deep`
- Importées en base avec `is_curated = true`, `source_tier = "deep"`, `is_active = true`
- Synchronisées par le `SyncService` existant (même pipeline RSS)
- Les articles sont enrichis normalement (HTML, paywall detection, etc.)

**Aucune modification du SyncService nécessaire** — les sources deep passent dans le même flux.

### 4.4 Rétention des articles deep

Les articles des sources deep ont une durée de rétention plus longue :
- Articles mainstream : rétention standard (configurable, actuellement ~30 jours)
- Articles deep : **pas de purge automatique** (ou rétention 365 jours minimum)

Implémentation : le job de purge ignore les articles dont `source.source_tier = "deep"`.

---

## 5. Mode Serein

Le mode serein s'applique à toutes les couches :

| Couche | Comportement Serein |
|--------|-------------------|
| **Sujets chauds** | Le LLM exclut les sujets anxiogènes (prompt adapté) |
| **Actu** | Filtre `is_serene = true` sur les articles candidats |
| **Deep** | Filtre `is_serene = true` sur les candidats deep |
| **Édito** | Prompt de rédaction "ton serein" (pas de 🔴/🚨, formulations neutres) |
| **Deep sans match serein** | Si le deep ne passe pas is_serene → pas de swipe pour ce sujet |

**Point d'attention** : `is_serene` doit être fiable. Validation à faire sur un échantillon avant lancement.

---

## 6. Configuration sans code

### 6.1 Prompts externalisés

Tous les prompts LLM sont stockés dans un fichier de config (YAML ou table DB) :

```yaml
# config/editorial_prompts.yaml

curation_prompt:
  system: |
    Tu es le rédacteur en chef de Facteur...
  model: claude-sonnet-4-6
  temperature: 0.3
  max_tokens: 1000

deep_matching_prompt:
  system: |
    Pour chaque sujet chaud, évalue les articles candidats...
  model: claude-sonnet-4-6
  temperature: 0.2
  max_tokens: 500

editorial_writing_prompt:
  system: |
    Tu es le rédacteur de Facteur...
  model: claude-sonnet-4-6
  temperature: 0.7
  max_tokens: 2000

editorial_writing_serein_prompt:
  system: |
    [Variante serein]
  model: claude-sonnet-4-6
  temperature: 0.5
  max_tokens: 2000

pepite_prompt:
  system: |
    Sélectionne un article surprenant...
  model: claude-sonnet-4-6
  temperature: 0.8
  max_tokens: 500
```

### 6.2 Paramètres ajustables

```yaml
# config/editorial_config.yaml

pipeline:
  subjects_count: 3              # Nombre de sujets chauds
  deep_candidates_prefilter: 10  # Candidats deep avant LLM
  deep_required: false           # Deep optionnel par sujet
  pepite_lookback_days: 7        # Fenêtre pour la pépite
  coup_de_coeur_window_hours: 48 # Fenêtre pour le coup de cœur
  coup_de_coeur_min_saves: 5     # Seuil minimum pour activer

scheduling:
  pipeline_trigger_hour: 6       # Heure de déclenchement (UTC+1)
  push_notification_hour: 8      # Heure de la push

sources:
  deep_retention_days: 365       # Rétention articles deep
  mainstream_max_age_hours: 24   # Fenêtre articles actu

modes:
  serein_filter_enabled: true
  serein_prompt_key: "editorial_writing_serein_prompt"
```

### 6.3 Itération rapide

Pour ajuster le ton ou les critères :
1. Modifier le fichier YAML de prompts
2. Redéployer (ou hot-reload si DB-backed)
3. Les prochains digests utilisent la nouvelle config

**Pas de changement de code nécessaire pour itérer sur le contenu éditorial.**

---

## 7. Coût estimé par digest

| Étape | Appels LLM | Tokens estimés | Coût estimé |
|-------|-----------|----------------|-------------|
| Curation (étape 2) | 1 | ~2K in + 500 out | ~$0.01 |
| Deep matching (étape 3B) | 3 (1/sujet) | ~1K in + 200 out × 3 | ~$0.02 |
| Rédaction éditoriale (étape 4) | 1 | ~3K in + 1K out | ~$0.02 |
| Pépite (étape 5) | 1 | ~1K in + 200 out | ~$0.005 |
| **Total par user/jour** | **6** | **~10K tokens** | **~$0.05** |

Avec Claude Sonnet 4.6 (moins cher qu'Opus). Pour 1000 users : ~$50/jour = ~$1500/mois.

**Optimisation possible** : les étapes 2 et une partie de 3B sont globales (même pour tous les users). Seules 3A et 4 sont per-user.

---

## 8. Compatibilité avec l'existant

| Composant existant | Impact |
|-------------------|--------|
| `DigestSelector` | Adapté : logique de sélection déléguée au LLM pour les 3 sujets |
| `TopicSelector` | Réutilisé pour le clustering (étape 1) |
| `ImportanceDetector` | Réutilisé pour les clusters |
| `DigestService` | Étendu : orchestre la nouvelle pipeline |
| `DigestGenerationJob` | Adapté : appelle la pipeline éditoriale |
| `SyncService` | Inchangé : les sources deep passent dans le même flux |
| `DailyDigest` model | Étendu : nouveau `format_version = "editorial_v1"` |
| `Source` model | Étendu : nouveau champ `source_tier` |
| Frontend `DigestProvider` | Adapté pour le nouveau format |
| Frontend `DigestCard` | Étendu : gestion des badges et du swipe actu/deep |

**Rétrocompatibilité** : le format `topics_v1` reste supporté. Le frontend détecte `format_version` et rend le layout approprié.

---

## 9. Risques et mitigations

| Risque | Impact | Mitigation |
|--------|--------|-----------|
| LLM indisponible | Pas de digest | Fallback : pipeline existante (topics_v1) sans édito |
| Pas de deep trouvé pour un sujet | UX dégradée | Dégradation gracieuse : juste carte actu, pas de swipe |
| is_serene peu fiable | Mode serein inutile | Validation sur échantillon avant lancement |
| Coût LLM élevé à scale | Budget | Étapes globales mutualisées + cache des résultats |
| Qualité éditoriale variable | Ton incohérent | Itération rapide sur les prompts via config |
| Sources deep RSS indisponible | Pool réduit | 20 sources → redondance thématique suffisante |

---

*Prochaine étape : [02-editorial.md](02-editorial.md) — Design doc éditorial (ton, exemples, prompts)*
