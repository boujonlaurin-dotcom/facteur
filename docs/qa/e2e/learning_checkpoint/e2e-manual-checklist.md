# Checklist E2E manuelle — Carte « Construire ton flux » (13.5-13.6)

> Validation visuelle et fonctionnelle de la carte Learning Checkpoint dans le feed mobile.

## Setup

```bash
# 1. Checkout branche avec backend + mobile
git checkout claude/learning-checkpoint-algo-UDwDy  # ou branche combinée

# 2. Appliquer migration (si pas déjà fait)
# → Supabase SQL Editor : contenu de alembic/versions/ln01_create_learning_tables.py

# 3. Seed données test
bash docs/qa/scripts/seed_13_5_13_6.sh

# 4. Lancer backend
cd packages/api && uvicorn app.main:app --port 8080 --reload &

# 5. Lancer mobile (iOS simulator ou Android)
cd apps/mobile && flutter run
```

### UUIDs des users test

| User | UUID | Scénario |
|------|------|----------|
| A | `a0000000-1356-4000-a000-000000000001` | Happy path (4 proposals, signal max 0.87) |
| B | `b0000000-1356-4000-b000-000000000002` | Gating N<2 (1 proposal) |
| C | `c0000000-1356-4000-c000-000000000003` | Gating signal<0.6 (4 proposals, signal max 0.55) |
| D | `d0000000-1356-4000-d000-000000000004` | Auto-expire shown≥3 (4 proposals) |
| E | `e0000000-1356-4000-e000-000000000005` | Test apply actions (4 proposals) |

---

## Scénario 1 : Happy path — Valider tout

**User** : A | **Prérequis** : seed frais, pas de cooldown

**Actions** :
1. Se connecter avec le compte User A
2. Aller sur le feed (`/feed`)
3. Scroller jusqu'à la position 3

**Vérifications** :
- [ ] La carte « Construire ton flux · Cette semaine » est visible en position 3
- [ ] Le header affiche « Construire ton flux · Cette semaine » (font-weight: 600)
- [ ] 4 rows de propositions affichées, mix de types :
  - [ ] Au moins 1 `source_priority` avec slider 3 dots (●○○ style)
  - [ ] Au moins 1 `mute_entity` avec toggle "Masquer"
  - [ ] Au moins 1 `follow_entity` avec toggle "Suivre"
- [ ] Chaque row affiche : label entité (bold) + phrase de justification
- [ ] Bouton X (dismiss) visible par row
- [ ] Bouton ℹ (expand) visible par row
- [ ] Footer : « Plus tard » (text) + « Valider » (filled)

4. Tapper **Valider** sans modifier

- [ ] Spinner sur le bouton « Valider » pendant l'appel
- [ ] Toast succès : « Tes préférences sont mises à jour »
- [ ] La carte disparaît du feed
- [ ] Cooldown actif : reload → carte absente
- [ ] Le feed se rafraîchit (contenu potentiellement réordonné)

---

## Scénario 2 : Snooze (Plus tard)

**User** : E | **Prérequis** : seed frais, pas de cooldown

**Actions** :
1. Se connecter avec User E
2. Voir la carte dans le feed
3. Tapper **Plus tard**

**Vérifications** :
- [ ] La carte disparaît
- [ ] Pas de toast succès (contrairement à Valider)
- [ ] Cooldown actif : reload → carte absente
- [ ] Vérifier en DB : toutes les proposals de User E ont status `dismissed`

---

## Scénario 3 : Dismiss individuel + Valider

**User** : A | **Prérequis** : seed frais (relancer `seed_13_5_13_6.sh`)

**Actions** :
1. Se connecter avec User A
2. Sur la carte, tapper le **✕** de la 2e proposition
3. Observer : la row disparaît visuellement
4. Tapper **Valider**

**Vérifications** :
- [ ] La row dismiss disparaît avec animation
- [ ] Les rows restantes ne bougent pas de position
- [ ] Le POST contient un mix : 3× `accept` + 1× `dismiss`
- [ ] Toast succès affiché
- [ ] Carte disparaît

---

## Scénario 4 : Expand stats (accordion)

**User** : A | **Prérequis** : seed frais

**Actions** :
1. Se connecter avec User A
2. Tapper ℹ sur la 1re proposition
3. Observer le panneau stats
4. Tapper ℹ sur la 2e proposition

**Vérifications** :
- [ ] Panel stats sous la 1re row :
  - [ ] « X articles affichés · Y lu · Z sauvegardé »
  - [ ] « Période : 7 derniers jours »
  - [ ] Signal : « engagement soutenu très fort » (signal ≥0.8) ou « fort » (≥0.6)
- [ ] Au tap sur row 2 : panel row 1 se ferme, panel row 2 s'ouvre
- [ ] Un seul panel ouvert à la fois
- [ ] Animation `AnimatedSize` fluide (pas de saut)

---

## Scénario 5 : Modify slider

**User** : A | **Prérequis** : seed frais

**Actions** :
1. Se connecter avec User A
2. Trouver une row `source_priority` avec le slider dots
3. Observer : dots "current" (gris) + dots "proposed" (couleur primaire)
4. Tapper le dot 2 sur la rangée "proposed"
5. Tapper **Valider**

**Vérifications** :
- [ ] Le dot tappé devient actif visuellement
- [ ] Le POST contient `{"action": "modify", "value": "..."}` pour cette proposal
- [ ] Les autres proposals sont `accept`
- [ ] Touch target ≥ 48dp (pas de misclick)

---

## Scénario 6 : Gating — pas assez de proposals

**User** : B | **Prérequis** : seed (User B a 1 seule proposal)

**Actions** :
1. Se connecter avec User B
2. Parcourir le feed entier

**Vérifications** :
- [ ] La carte « Construire ton flux » n'apparaît JAMAIS
- [ ] Aucun crash ni erreur console

---

## Scénario 7 : Erreur backend + Réessayer

**User** : A | **Prérequis** : seed frais

**Actions** :
1. Se connecter avec User A
2. Couper le backend (`kill` le processus uvicorn)
3. Tapper **Valider** sur la carte

**Vérifications** :
- [ ] Toast erreur : « Une erreur est survenue »
- [ ] La carte reste visible (pas de disparition)
- [ ] Les données des rows sont préservées (pas de reset)
- [ ] Le bouton « Valider » change en « Réessayer »
4. Relancer le backend
5. Tapper **Réessayer**
- [ ] Le POST réussit cette fois
- [ ] Toast succès + carte disparaît

---

## Scénario 8 : Dark mode

**User** : A | **Prérequis** : seed frais

**Actions** :
1. Basculer le device en dark mode
2. Se connecter avec User A
3. Observer la carte

**Vérifications** :
- [ ] Header lisible, contraste suffisant
- [ ] Dots slider : couleurs adaptées (pas de dots invisibles)
- [ ] Toggles : texte lisible sur fond sombre
- [ ] Panel stats : texte secondaire/tertiaire visible
- [ ] Bordures et séparateurs visibles
- [ ] Boutons footer : contraste OK

---

## Scénario 9 : Accessibilité

**User** : A | **Prérequis** : seed frais

**Actions** :
1. Activer VoiceOver (iOS) ou TalkBack (Android)
2. Naviguer sur la carte

**Vérifications** :
- [ ] Chaque proposition annonce : « Proposition : {entityLabel} »
- [ ] Dots slider annoncent : « Niveau X sur 3 »
- [ ] Toggle annonce : « Masquer » / « Suivre » + état (activé/désactivé)
- [ ] Bouton X annonce : « Ignorer la proposition »
- [ ] Bouton ℹ annonce : « Détails de la proposition »
- [ ] Touch targets ≥ 48dp sur tous les éléments interactifs

---

## Résultat

| # | Scénario | Status | Notes |
|---|----------|--------|-------|
| 1 | Happy path Valider | | |
| 2 | Snooze | | |
| 3 | Dismiss + Valider | | |
| 4 | Expand stats | | |
| 5 | Modify slider | | |
| 6 | Gating N<2 | | |
| 7 | Erreur + Réessayer | | |
| 8 | Dark mode | | |
| 9 | Accessibilité | | |

**Date** : ___  
**Testeur** : ___  
**Branche** : ___  
**Device** : ___
