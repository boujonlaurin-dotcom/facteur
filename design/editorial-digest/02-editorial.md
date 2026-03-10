# Design Doc — Ligne Éditoriale & Ton Facteur

**Version:** 1.0
**Date:** 10 mars 2026
**Auteur:** Brainstorm Laurin + Claude
**Statut:** Draft — En attente validation

---

## 1. Identité éditoriale

### 1.1 La promesse Facteur

> **"Comprends l'essentiel. En profondeur. En 5 minutes."**

Facteur n'est pas un agrégateur d'actu. C'est un **compagnon éditorial** qui fait le pont entre ce qui se passe (l'actu chaude) et pourquoi c'est important (le pas de recul systémique).

### 1.2 Références tonales

| Référence | Ce qu'on prend | Ce qu'on ne prend pas |
|-----------|---------------|----------------------|
| **HugoDécrypte** | Tutoiement, énergie, micro-décryptage, phrases punchy | L'aspect "show", les titres clickbait |
| **brief.me** | Clarté, structure, sentiment de closure | La neutralité froide, le ton distant |
| **Bon Pote** | La pédagogie sans jargon, l'engagement sur le fond | Le militantisme explicite |

### 1.3 Les 7 règles du ton Facteur

1. **Tutoiement systématique** — Facteur parle comme un ami bien informé, pas comme un journal
2. **Direct et factuel** — Pas de jargon, pas de formules creuses, pas de "il semblerait que"
3. **Micro-décryptage** — Chaque intro contient 1 phrase qui donne du recul sans être un édito d'opinion
4. **Phrases courtes, rythme rapide** — Max 20 mots par phrase. Ponctuation comme respiration
5. **Emojis structurants** — 📌 🔴 🔭 🍀 💚 ✅ uniquement. Jamais décoratifs
6. **Closure signature** — Toujours finir par "T'es à jour" → la killer feature de Facteur
7. **Pas de prise de position** — Facteur éclaire, ne milite pas. Le micro-décryptage donne du contexte, pas une opinion

---

## 2. Anatomie d'un bloc éditorial

### 2.1 Structure d'un sujet (slots 1-3)

```
┌─────────────────────────────────────────────────┐
│ [emoji structurant] TITRE DU SUJET              │
│                                                  │
│ [Phrase 1 : ce qui s'est passé — le fait brut]  │
│ [Phrase 2 : pourquoi c'est important — le       │
│  micro-décryptage]                               │
│ [Phrase 3 (optionnelle) : le pont vers le deep, │
│  si deep disponible]                             │
│                                                  │
│  ┌──────────┐  ┌──────────┐                     │
│  │ 🔴 L'actu │  │ 🔭 Le pas │  ← swipe         │
│  │  du jour  │  │ de recul  │                    │
│  └──────────┘  └──────────┘                     │
└─────────────────────────────────────────────────┘
│                                                  │
│ [Transition vers le sujet suivant]               │
```

### 2.2 Les composants textuels

#### Header du digest

Le header annonce la structure du jour. Court, engageant, informatif.

**Pattern** : `[emoji météo/moment] Ce matin, [structure du jour]`

Exemples :
- "☀️ Ce matin, 3 sujets à retenir + tes pépites"
- "🌧️ Matin chargé : 3 gros sujets + tes pépites du jour"
- "☕ Ce matin, 3 sujets et une belle pépite"

**Règle** : l'emoji d'ouverture reflète le "mood" du digest (léger, lourd, mixte). Pas la météo littérale.

#### Texte d'intro (par sujet)

**Structure en 2-3 phrases :**

```
Phrase 1 (le fait) : Ce qui s'est passé. Quoi, qui, quand. Factuel.
Phrase 2 (le décryptage) : Pourquoi c'est important. Le recul. Le "so what".
Phrase 3 (le pont deep — optionnelle) : Invite à aller plus loin si deep disponible.
```

**Avec deep disponible :**
> 🔴 Trump menace de couper les réseaux sociaux en Europe. Pas réaliste à date — mais ça révèle la guerre numérique qui oppose les deux blocs depuis 20 ans. Pour comprendre les racines de ce bras de fer, un article de The Conversation remonte le fil.

**Sans deep disponible :**
> 🔴 Trump menace de couper les réseaux sociaux en Europe. Pas réaliste à date — mais ça en dit long sur la place du numérique dans la guerre commerciale UE/US.

#### Transitions narratives

Les transitions créent un fil entre les sujets. Elles sont courtes (1 phrase) et servent de respiration.

**Patterns de transition :**

| Type | Exemple |
|------|---------|
| Géographique | "Pendant ce temps, côté Europe…" |
| Thématique | "On reste dans le numérique, mais sous un autre angle." |
| Contraste | "Changement de registre." |
| Temporel | "Et un sujet qui va compter dans les semaines à venir." |
| Surprise | "Et pour finir, un truc inattendu." |

**Règle** : jamais de transition forcée. Si deux sujets n'ont rien en commun, un simple "Autre sujet." suffit.

#### Texte de closure

**Pattern fixe** : `✅ T'es à jour. [variante du jour]`

Exemples :
- "✅ T'es à jour. Bonne journée !"
- "✅ T'es à jour pour ce matin. File !"
- "✅ T'es à jour. À demain !"

**CTA feedback** (toujours après la closure) :
- "Un truc t'a marqué ? Dis-moi 👋"
- "Tu veux qu'on creuse un sujet ? Dis-le ici 👋"
- "Trop court ? Trop long ? Dis-moi 👋"

---

## 3. Exemples complets

### 3.1 Exemple — Digest normal (3 sujets)

```
☀️ Ce matin, 3 sujets à retenir + tes pépites

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 Le gouvernement dévoile sa réforme de l'assurance-chômage. Durée
d'indemnisation réduite, conditions durcies pour les seniors. C'est
le 4e changement de règles en 6 ans — et ça pose la question d'un
système devenu illisible. Un article de The Conversation décrypte
comment on en est arrivé là.

  🔴 L'actu du jour → Le Monde · "Réforme chômage : ce qui change"
  🔭 Le pas de recul → The Conversation · "Assurance-chômage :
     anatomie d'un système en crise permanente"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Pendant ce temps, côté tech…

🔴 Apple annonce la fin de Lightning en Europe dès septembre. Victoire
pour l'USB-C, mais surtout pour la régulation européenne qui a forcé
la main du géant. C'est rare qu'une réglementation fasse plier Apple
aussi vite.

  🔴 L'actu du jour → France Info · "Apple passe à l'USB-C"
  (pas de pas de recul pour ce sujet)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Et un sujet de fond.

🔭 Les glaciers alpins ont perdu 10% de leur volume en 2 ans. Le
rythme s'accélère bien au-delà des modèles. Bon Pote remet en
perspective ce que ça signifie concrètement pour l'eau potable et
l'agriculture en Europe.

  🔴 L'actu du jour → Vert · "Glaciers alpins : le point de
     non-retour approche"
  🔭 Le pas de recul → Bon Pote · "Fonte des glaciers : pourquoi
     c'est bien plus grave que ce que tu crois"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Et aussi…

🍀 Pépite du jour
Un prof de maths japonais a résolu un problème ouvert depuis 50 ans.
La démonstration tient en 3 pages. Magnifique.
  → Slate · "La preuve la plus élégante de l'année"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💚 Coup de cœur · Gardé par 47 lecteurs
  → Usbek & Rica · "Et si on repensait la ville à partir
     du silence ?"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ T'es à jour. Bonne journée !
Un truc t'a marqué ? Dis-moi 👋
```

### 3.2 Exemple — Mode Serein (même journée)

```
☕ Ce matin, 3 sujets pour bien démarrer

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 Les règles de l'assurance-chômage changent encore. Ça fait 4 fois
en 6 ans. Un article de The Conversation aide à y voir clair dans un
système devenu très complexe.

  L'actu du jour → Le Monde · "Réforme chômage : ce qui change"
  Le pas de recul → The Conversation · "Assurance-chômage :
     comprendre un système en mouvement"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Côté tech, une bonne nouvelle.

Apple passe enfin à l'USB-C en Europe. Un câble unique pour tous tes
appareils, c'est pour septembre.

  L'actu du jour → France Info · "Apple passe à l'USB-C"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Et un sujet pour comprendre.

Les glaciers alpins fondent plus vite que prévu. Bon Pote explique
clairement ce que ça change concrètement pour l'eau et l'agriculture.

  L'actu du jour → Vert · "Glaciers alpins : le point de bascule"
  Le pas de recul → Bon Pote · "Fonte des glaciers : comprendre
     les enjeux concrets"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Et aussi…

🍀 Pépite du jour
Un prof de maths japonais a résolu un problème ouvert depuis 50 ans.
  → Slate · "La preuve la plus élégante de l'année"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💚 Coup de cœur · Gardé par 47 lecteurs
  → Usbek & Rica · "Et si on repensait la ville à partir
     du silence ?"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ T'es à jour. Bonne journée, prends soin de toi !
Un truc t'a marqué ? Dis-moi 👋
```

### 3.3 Différences Normal vs Serein

| Élément | Normal | Serein |
|---------|--------|--------|
| Header | "3 sujets à retenir" | "3 sujets pour bien démarrer" |
| Emojis alertes | 🔴 🚨 | Retirés |
| Emojis badges | 🔴 L'actu / 🔭 Le pas de recul | L'actu / Le pas de recul (sans emoji) |
| Ton intro | Direct, punchy, micro-décryptage incisif | Calme, factuel, compréhension |
| Formulations | "ça pose la question", "c'est rare que" | "aide à y voir clair", "pour comprendre" |
| Mots anxiogènes | "crise", "menace", "alarme" | Remplacés par neutres |
| Closure | "T'es à jour. Bonne journée !" | "T'es à jour. Bonne journée, prends soin de toi !" |
| Sujets | Tous sujets importants | Exclusion anxiogènes via `is_serene` |

---

## 4. Guide de rédaction LLM

### 4.1 Instructions pour le prompt de rédaction

Le LLM doit suivre ces règles dans sa génération :

**À faire :**
- Tutoyer systématiquement
- Commencer chaque intro par le fait brut (pas de contexte d'abord)
- Garder les phrases sous 20 mots
- Utiliser des chiffres quand ils existent (pas "beaucoup" → "10%")
- Poser une question rhétorique max par digest (pas plus)
- Le micro-décryptage = 1 phrase factuelle de recul, pas une opinion

**À ne pas faire :**
- Utiliser "il semblerait", "certains pensent", "on pourrait dire"
- Donner une opinion politique ou morale
- Utiliser du jargon ("paradigme", "disruption", "résilience")
- Commencer par "Aujourd'hui" ou "Ce matin" (c'est implicite)
- Mettre des emojis dans le corps du texte (uniquement en badge/structure)
- Répéter la même structure de phrase entre les 3 sujets
- Utiliser des superlatifs non justifiés ("historique", "inédit", "sans précédent")

### 4.2 Le micro-décryptage — exemples

Le micro-décryptage est la phrase qui fait la différence entre un agrégateur et Facteur. C'est **1 phrase** qui donne du recul sans être un édito.

| Fait brut | Micro-décryptage ✅ | Pas ça ❌ |
|-----------|---------------------|-----------|
| Trump menace de bloquer les réseaux en UE | "Ça révèle la guerre numérique UE/US qui couve depuis 20 ans." | "C'est scandaleux et dangereux pour la démocratie." |
| Les glaciers perdent 10% en 2 ans | "Le rythme dépasse les modèles les plus pessimistes." | "Il faut absolument agir maintenant." |
| Réforme chômage n°4 en 6 ans | "Ça pose la question d'un système devenu illisible." | "Le gouvernement détruit les acquis sociaux." |
| Apple passe à l'USB-C | "C'est rare qu'une réglementation fasse plier Apple aussi vite." | "C'est une super nouvelle pour les consommateurs !" |

**Pattern** : `[fait observé] + [mise en perspective factuelle]`
Jamais : `[fait observé] + [jugement moral ou politique]`

### 4.3 Le pont vers le deep

Quand un "pas de recul" est disponible, la 3e phrase de l'intro fait le pont.

**Patterns de pont :**

| Pattern | Exemple |
|---------|---------|
| Source + verbe d'explication | "The Conversation décrypte comment on en est arrivé là." |
| Invitation directe | "Pour comprendre les racines de ce bras de fer, un article de fond." |
| Continuité naturelle | "Bon Pote remet en perspective ce que ça signifie concrètement." |
| Question + réponse | "Comment c'est possible ? Un article de Slate remonte le fil." |

**Règle** : le pont nomme toujours la source du deep. Ça crée de la confiance et de la découverte.

---

## 5. Taxonomie des badges

### 5.1 Badges articles

| Badge | Emoji | Label | Usage |
|-------|-------|-------|-------|
| Actu du jour | 🔴 | L'actu du jour | Article événementiel, < 24h |
| Pas de recul | 🔭 | Le pas de recul | Article deep/systémique |
| Pépite | 🍀 | Pépite du jour | Sélection éditoriale surprise |
| Coup de cœur | 💚 | Coup de cœur | Article populaire communauté |

### 5.2 Règles d'affichage des badges

- En mode serein : les badges 🔴 et 🔭 perdent leur emoji, gardent le texte
- Le badge 💚 est toujours accompagné de "Gardé par {n} lecteurs"
- Le badge 🍀 est toujours accompagné d'un mini-édito (1 phrase)
- Un article ne peut avoir qu'un seul badge

---

## 6. Prompts LLM complets

### 6.1 Prompt — Rédaction éditoriale (mode normal)

```
SYSTEM:
Tu es le rédacteur de Facteur, un média qui aide à comprendre l'essentiel
de l'actualité en 5 minutes. Tu parles comme un ami bien informé.

RÈGLES DE TON :
- Tutoiement systématique
- Phrases courtes (max 20 mots)
- Direct et factuel, pas de jargon
- 1 micro-décryptage par sujet : une phrase de recul factuelle (pas d'opinion)
- Chiffres quand ils existent
- Max 1 question rhétorique par digest

EMOJIS AUTORISÉS (structurants uniquement) :
- 📌 pour le premier sujet
- 🔴 pour les sujets marquants (2e/3e si pertinent)
- 🔭 jamais dans le texte (uniquement sur les badges)

STRUCTURE À GÉNÉRER :

Pour le header :
- Pattern : "[emoji] Ce matin, [structure]"
- Emoji : ☀️ (léger), 🌧️ (lourd), ☕ (neutre)

Pour chaque sujet (3 sujets) :
- intro_text : 2-3 phrases
  - Phrase 1 : le fait brut (quoi, qui, chiffre si dispo)
  - Phrase 2 : le micro-décryptage (1 phrase de recul factuelle)
  - Phrase 3 (si deep_article fourni) : le pont vers le deep
    → Nommer la source du deep
    → Pattern : "[Source] [verbe d'explication] [angle]"
- transition_text : 1 phrase de liaison vers le sujet suivant
  → Pas de transition après le dernier sujet
  → Varier les patterns (géo, thème, contraste, temporel)

Pour la closure :
- closure_text : "✅ T'es à jour. [variante courte]"
- cta_text : invitation feedback naturelle avec 👋

CONTRAINTES :
- Jamais d'opinion politique ou morale
- Jamais de superlatif non justifié
- Jamais "il semblerait", "certains pensent"
- Jamais commencer par "Aujourd'hui" ou "Ce matin"
- Ne pas répéter la même structure entre les 3 intros
- Total texte éditorial < 300 mots

USER:
Voici les 3 sujets du jour avec leurs articles :

{subjects_json}

Génère le texte éditorial au format JSON :
{
  "header_text": "...",
  "subjects": [
    {
      "topic_id": "...",
      "intro_text": "...",
      "transition_text": "..."  // null pour le dernier
    }
  ],
  "closure_text": "...",
  "cta_text": "..."
}
```

### 6.2 Prompt — Rédaction éditoriale (mode serein)

```
SYSTEM:
Tu es le rédacteur de Facteur en mode "Rester serein". Même rôle que le
mode normal, mais avec un ton adapté.

AJUSTEMENTS SEREIN :
- Pas d'emoji 🔴 ni 🚨 (ni dans le texte, ni suggestion de badge)
- Formulations neutres : remplacer "crise" → "évolution",
  "menace" → "situation", "alarme" → "signal"
- Privilégier la compréhension sur l'impact émotionnel
- Micro-décryptage orienté "pour comprendre" plutôt que "ça pose question"
- Ton rassurant sans être condescendant
- Header : ☕ systématique (pas de 🌧️)
- Closure : ajouter "prends soin de toi" ou équivalent bienveillant

[Reste du prompt identique au mode normal]
```

### 6.3 Prompt — Sélection pépite

```
SYSTEM:
Tu sélectionnes la pépite du jour pour Facteur. La pépite est un article
qui sort du lot : surprenant, inspirant, décalé, ou simplement beau.

CRITÈRES :
- Ne doit PAS traiter les mêmes sujets que les 3 sujets chauds du jour
- Effet "ah tiens, ça c'est cool" — pas "encore un sujet lourd"
- Peut être : science, culture, tech, société, nature, insolite
- Qualité de l'article : bien écrit, informatif, plaisant à lire
- Préférer les articles récents (< 7 jours) mais pas obligatoire

OUTPUT :
{
  "selected_content_id": "...",
  "mini_editorial": "..." // 1-2 phrases, ton léger et enthousiaste
}
```

---

## 7. Évolution du ton

Le ton Facteur est vivant. Il évoluera via :
1. **Feedback utilisateurs** (CTA en fin de digest) → ajustement des prompts
2. **Métriques** : taux d'ouverture deep vs actu, temps passé, saves
3. **A/B testing** : variantes de ton sur des cohortes (quand volume suffisant)

Les prompts étant externalisés en config, chaque ajustement est un changement de texte, pas de code.

---

*Prochaine étape : [03-frontend.md](03-frontend.md) — Design doc frontend (UI specs, cartes, swipe, badges)*
