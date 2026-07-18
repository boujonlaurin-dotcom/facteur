# Notifs intelligentes — Micro-rapport de décision (pré-brief PM)

**Date :** 2026-07-18
**Source :** [rapport de brainstorming du même jour](2026-07-18-notifs-intelligentes.md) + arbitrages PO (Laurin)
**Usage :** document d'entrée pour le brief PM BMAD (Epic 30)

---

## 1. Les arbitrages, et comment ils ont été tranchés

| Question | Décision | Raisonnement |
|---|---|---|
| **Freemium** : l'alerte sujet est-elle premium ? | **Free en V1.** | On est en phase de preuve de valeur et d'adoption : monétiser une feature dont le geste ("poser une alerte") n'existe pas encore chez les utilisateurs tuerait l'apprentissage. La monétisation (persona Pro, RAS quotidien, budget réglable) reste une **option ouverte pour plus tard**, une fois l'usage prouvé. |
| **Seuil « source rare »** | **< 1 article/semaine** (plus strict que la proposition initiale < 3/sem). Plafond de cloches actives : **5**, inchangé. | Le PO durcit volontairement le seuil : la promesse V1 est « la revue mensuelle qu'on rate », pas « le blog hebdo ». Un seuil strict garantit que chaque alerte source reste un événement (~1 à 4 notifs/mois max par cloche) et rend le risque spam nul par construction. Élargir le seuil plus tard est trivial ; le resserrer après coup casserait des cloches posées. |
| **Skip du push les jours pauvres** | **Pas tranché — remonté au PM comme question produit plus profonde.** V1 : le push quotidien reste quotidien. | Le PO juge l'idée « entendable » mais elle révèle une vraie question : propose-t-on à un utilisateur de venir « garder sa streak » un jour faible, alors que la valeur éditoriale du jour est basse ? C'est un arbitrage rituel-vs-honnêteté qui dépasse le scope notifs → à instruire dans le brief (voir §4). |
| **Naming** | **« Alerte »**, tout simplement. | Simplicité et compréhension immédiate priment sur la poésie facteur. La métaphore (📯, « ça n'arrive qu'une fois par mois ») vit dans le *contenu* des notifs, pas dans le nom de l'objet. Dans l'UI : « Poser une alerte », « Mes alertes » (dans « Mes intérêts »), section « Tes alertes » en tête de Tournée. |

**Rappel des décisions déjà tranchées par le brainstorm** (inchangées) : pas de time picker en V1 (le créneau matin/soir est le contrat), différé par défaut partout (l'immédiat n'existe pas en V1), pas d'inbox dédiée, budget serveur non contournable ≤ 2 push/jour et ≤ 6/semaine, jamais de push sur match mot-clé brut.

---

## 2. À quoi ressemblent les notifs du plan

> **Révision PO du 18/07 (v2).** Le modèle initial (« tout coalescer dans le push quotidien ») optimisait le nombre de notifs au détriment de la clarté : bullets mélangés = CTA flou, info diluée, réglages illisibles. Nouveau principe : **une info = une notif claire ; séparation dans l'affichage, groupement dans le temps.** Chaque type de notif garde son identité, son CTA unique et son réglage propre ; mais toutes arrivent au créneau choisi et seule la tournée sonne (les alertes sont silencieuses, elles s'ajoutent dans le tiroir). L'anti-spam n'est plus la fusion : c'est la rareté des déclencheurs + le budget serveur.

### Notif 1 — Le push quotidien « coup d'œil » (PR #1)

Son job, et son seul job : montrer **en un coup d'œil ce qu'il y a eu d'important aujourd'hui** (la faiblesse actuelle de la notif). Les bullets deviennent les 3 faits saillants du jour, ordonnés par les intérêts de l'utilisateur, écrits comme des faits et non comme des teasers. Aucune mention d'alertes dedans : CTA unique = ouvrir la tournée.

```
🌅 Ta tournée est prête                   ← titre/son/canal actuels, intouchés
─────────────────────────────────────────
Ce matin, il faut retenir :
• Retraites : accord trouvé à l'Assemblée
• Nestlé Waters : le procès s'ouvre à Paris
• Nvidia franchit les 5 000 milliards
```

### Notif 2 — L'alerte source rare (PR #2, kind `source_alert`)

Notif **distincte et reconnaissable** (📯 + préfixe « Alerte »), silencieuse, livrée au même créneau que la tournée. Sa rareté est garantie par construction (source < 1/sem, soit ~1 notif/mois). CTA unique = lire la publication.

```
Canal « Alertes » (silencieux)
─────────────────────────────────────────
📯 Alerte : Le 1 Hebdo vient de publier
Son numéro de juillet est disponible.
Ça n'arrive qu'une fois par mois.

[ Lire ]  [ Régler cette alerte ]          ← réglage propre à CETTE alerte, en 1 tap
```

### Notif 3 — L'alerte sujet cluster-gated (PR #3, sur preuve d'usage de #2)

Même logique : notif distincte (🔔 + nom de l'alerte), silencieuse, au créneau. Jamais sur un match mot-clé seul : uniquement quand plusieurs sources confirment. Un événement = une notif, mise à jour silencieusement s'il grossit.

```
Canal « Alertes » (silencieux)
─────────────────────────────────────────
🔔 Alerte « glyphosate » : du nouveau
3 sources en parlent aujourd'hui, dont
Le Monde et Reporterre.

[ Voir ]  [ Régler cette alerte ]
```

### Le modèle de réglage (rendu lisible par la séparation)

Chaque alerte a sa fiche (dans « Mes intérêts ») avec 2 réglages simples : **quand** (à mon créneau, par défaut / récap hebdo / immédiat, pas en V1) et **désactiver**. « Régler cette alerte » dans la notif y mène directement. Le push quotidien, lui, garde ses réglages actuels : les deux mondes ne se mélangent jamais.

### Matin type d'un utilisateur avec 2 alertes actives

Une seule vibration (la tournée), et dans le tiroir : la notif tournée + 0 à 2 cartes d'alerte silencieuses, chacune lisible et actionnable indépendamment. Les jours sans signal (la grande majorité) : la tournée seule, comme aujourd'hui.

### Ce qui n'est PAS une notif (mais fait partie du contrat)

- **Le devis de bruit à la création** (in-app) : « Ce mot aurait déclenché ~14 alertes ces 30 derniers jours 🔴. Conseillé : dans ta prochaine tournée. » La digue principale contre la sur-souscription.
- **Le silence comme preuve** (in-app, fiche de l'alerte) : « En veille active. Rien d'important sur ce sujet depuis 3 semaines, et c'est vérifié. »
- **Le gouverneur invisible** : si le budget du jour est atteint ou qu'un push rituel part dans les 4h, l'alerte attend l'édition suivante au lieu de sonner.

---

## 3. Impact sur le plan d'exécution (top 3 confirmé)

| PR | Contenu | Ajustements issus des arbitrages |
|---|---|---|
| **#1 Gouverneur + push « coup d'œil »** (S/M) | Composeur unique, budget, canal séparé, bullets « faits saillants du jour », `push_opened` | Les bullets ne mentionnent plus les alertes : ils deviennent le résumé du jour en un coup d'œil (v2 PO). |
| **#2 Alerte source rare + devis** (S) | Colonne `notify` sur `user_sources`, badge de rythme, kind `source_alert` | Seuil d'éligibilité **< 1/sem** (au lieu de < 3), plafond **5 alertes actives**, naming UI « Alerte ». |
| **#3 Alerte sujet cluster-gated** (M) | Custom-topics-only, gate cluster, chips d'expansion | **Free** (pas de gating premium à prévoir dans l'architecture V1 ; garder le hook pour plus tard). |

---

## 4. À instruire dans le brief PM (nouveau)

**La question streak / jour pauvre.** Le skip du push les jours faibles pose une question que le PO veut voir traitée en tant que telle : *quand la valeur éditoriale du jour est basse, est-il honnête d'inviter l'utilisateur à venir « garder sa streak » ?* Pistes à évaluer : streak "gelée" les jours pauvres (le silence ne casse pas la série), wording du push qui assume un jour léger, ou statu quo. Hors scope des 3 PRs ; à traiter comme réflexion rituel/rétention séparée.
