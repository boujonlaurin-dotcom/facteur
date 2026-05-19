# QA Handoff — Cleanup UI legacy « PrioritySlider 3-crans » → picker 4-états

> Rempli par l'agent dev pour input à `/validate-feature`.

## Feature développée

Retrait du widget legacy `PrioritySlider` (slider 3-crans 0.2/1.0/2.0) sur 8
call-sites Flutter et de ses dépendances backend (endpoint
`PUT /sources/{id}/weight` + champ `priority_multiplier` du
`PUT /personalization/topics/{id}`). Tous les ajustements de sources et de
sujets passent désormais par le **picker canonique 4-états**
(`InterestStatePickerSheet` : Favori / Suivi / Neutre / Masqué). Deux CTA
sur les filtres feed ont été reformulés (le wording « pousse leur priorité
à 3/3 » devient « ajoute-les en favori »).

> **Décision PO** : Option A allégée — la colonne DB `priority_multiplier`
> est conservée (toujours 1.0 pour les nouveaux rows), pas de migration
> Alembic, scoring inchangé.

## PR associée

À créer via `/go` vers `main` (branche : `boujonlaurin-dotcom/cleanup-legacy-priority-sliders`).

## Écrans impactés

| Écran | Route / Trigger | Modifié |
|-------|------------------|---------|
| Topic Explorer | `/topics/:slug` | ✅ pill 4-états dans header |
| Article Sheet (Topic) | Long-press sur un topic chip d'une carte feed | ✅ pill 4-états + section source |
| Source Detail Modal | Tap sur une source dans Mes sources / Add source | ✅ pill 4-états section « Place cette source dans votre flux » |
| Source Adjust Sheet | Swipe-gauche sur une carte feed | ✅ pill 4-états + bouton « Masquer » conservé |
| Sources List | `/sources` | ✅ slider retiré, étoile + picker conservés |
| Digest Personalization Sheet | Tap « Pourquoi cet article » dans le digest | ✅ pill 4-états remplace le slider |
| Source Filter Sheet | Filtres sources sur le feed | ✅ CTA « Ajoute-les en favori » + favoris alignés sur `userSourcesStateProvider` |
| Interest Filter Sheet | Filtres intérêts sur le feed | ✅ CTA « Ajoute-les en favori » |

## Scénarios de test

### Scénario 1 : Picker depuis Source Detail Modal
**Parcours** :
1. Aller sur `/sources` (Mes sources)
2. Tap sur une source suivie (`isTrusted`)
3. Dans la modale détail, scroller jusqu'à « Place cette source dans votre flux »
4. Tap sur le pill (affiche l'état courant, ex. « Suivi »)
5. Picker s'ouvre → choisir « Favori »

**Résultat attendu** :
- Pill se met à jour en « Favori » (étoile)
- Source apparaît dans le top 3 des favoris dans `/sources`
- Aucune requête `PUT /sources/{id}/weight` dans devtools réseau
- `PATCH /api/user/sources` envoyée avec `state: favorite`

### Scénario 2 : Swipe-gauche carte feed → Adjust Sheet
**Parcours** :
1. Sur le feed, swipe-gauche sur une carte d'article
2. Sheet s'ouvre — vérifier section « Place dans le flux »
3. Tap sur le pill → picker → choisir « Masqué »

**Résultat attendu** :
- Pill devient « Masqué » (icône eye-slash)
- Le sheet reste ouvert (le bouton « Masquer cette source » est aussi présent — c'est un shortcut)
- Aucun slider 3-crans visible
- Si la nudge « explainer » est active, son wording mentionne les 4 états

### Scénario 3 : Topic Explorer — changer l'état d'un sujet suivi
**Parcours** :
1. Tap sur un topic chip → Article Sheet
2. (alternatif) Aller sur `/topics/:slug` directement
3. Si le sujet est suivi, header montre « Suivi ✓ » + pill à droite
4. Tap sur le pill → picker → choisir « Neutre »

**Résultat attendu** :
- Pill devient « Neutre »
- `PATCH /api/user/interests` envoyée avec `kind: custom_topic`, `state: unfollowed`
- Au prochain refresh du digest, le poids du sujet décroît

### Scénario 4 : Article Sheet — pill source (topic_chip)
**Parcours** :
1. Long-press sur le topic chip d'une carte → Article Sheet s'ouvre
2. Scroller jusqu'à la section source
3. Tap sur le pill source

**Résultat attendu** :
- Picker s'ouvre avec le nom de la source en titre
- Sélection persiste après refresh

### Scénario 5 : « Pourquoi cet article » dans le digest
**Parcours** :
1. Sur le digest (`/digest`), tap sur le bouton « Pourquoi cet article » d'un item
2. Sheet s'ouvre avec le breakdown
3. En bas, section source → pill 4-états visible (si source `isTrusted`)
4. Tap → picker → choisir un état

**Résultat attendu** :
- Pill se met à jour, le sheet reste ouvert
- Aucun slider visible

### Scénario 6 : CTA filtres feed (wording)
**Parcours** :
1. Ouvrir le sheet de filtre sources sur le feed
2. Si l'utilisateur a < 3 favoris, le CTA « Définir mes sources favorites » apparaît

**Résultat attendu** :
- Sous-titre = « Ajoute-les en favori dans Mes sources (top 3 = Tournée du jour) » si 0 favoris
- ou « N favori(s) — top 3 affiché dans la Tournée du jour » si 1+
- Le wording legacy « Pousse leur priorité à 3/3 » est **absent**
- Idem côté filtres intérêts (« Mes intérêts »)

### Scénario 7 : Ajout d'une source du catalogue (`source_add_panel`)
**Parcours** :
1. Aller sur `/sources/add` (ou équivalent)
2. Chercher une source du catalogue, tap pour l'ajouter
3. Sheet détail s'ouvre après ajout

**Résultat attendu** :
- La source est automatiquement marquée comme **favorite** (via `PATCH /api/user/sources` avec `state: favorite`)
- Plus aucun appel `PUT /sources/{id}/weight`

## Critères d'acceptation

- [ ] **0 appel réseau** `PUT /sources/{id}/weight` dans toute l'app (devtools)
- [ ] **0 payload** `priority_multiplier` dans les `PUT /personalization/topics/{id}` envoyés par le mobile
- [ ] Aucun slider 3-crans visible nulle part dans l'app
- [ ] Tous les pickers 4-états s'ouvrent au tap sur les pills/étoiles
- [ ] Les états choisis persistent après refresh / reload
- [ ] Le mute reste possible via le shortcut du `source_adjust_sheet`
- [ ] CTAs filtres feed utilisent le nouveau wording « Ajoute-les en favori »

## Zones de risque

- **`source_add_panel`** : la promotion auto-favori d'une source ajoutée
  depuis le catalogue est passée de `priority_multiplier=2.0` à
  `setSourceState(favorite)`. Vérifier que la source est bien favori après
  ajout (et apparaît dans le top 3 si la liste de favoris en compte < 3).
- **`source_filter_sheet`** : le bloc « VOS FAVORIS » se lit désormais dans
  `userSourcesStateProvider.favorites` (au lieu de l'ancienne détection
  `priorityMultiplier >= 2.0 || hasSubscription`). Vérifier que tous les
  favoris existants apparaissent correctement (post-migration Story 22.1).
- **`source_adjust_sheet`** : l'explainer nudge est conservé sous l'ID
  `prioritySliderExplainer` (texte mis à jour). Vérifier que le nudge
  s'affiche bien la 1re fois.
- **Backend** : `PUT /sources/{id}/weight` retourne désormais **404/405**.
  Aucun client (mobile/web/admin) ne doit plus l'appeler.
- **Backend** : le scoring ML lit toujours `priority_multiplier` en DB,
  donc les anciens rows ≠ 1.0 continuent d'influencer le ranking. Pas de
  régression de scoring attendue.

## Dépendances

- **Endpoints backend touchés** :
  - `PUT /sources/{id}/weight` → **supprimé**
  - `PUT /personalization/topics/{id}` → champ `priority_multiplier` retiré du request (autres champs intacts)
  - `PATCH /api/user/sources` → seul endpoint d'écriture côté sources (existant, Story 22.1)
  - `PATCH /api/user/interests` → seul endpoint d'écriture côté thèmes / sujets (existant, Story 22.1)
- **Services backend** : pas de redémarrage spécifique, déploiement Railway standard.
- **Migration Alembic** : aucune.
