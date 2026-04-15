# QA Handoff — PR2 : Smart Search Field + Enriched Result Cards

> Rempli par l'agent dev. Input pour /validate-feature.

## Feature developpee

Remplacement de l'ecran "Ajouter une source" a 3 onglets (URL/YouTube/Reddit) par un champ de recherche unique intelligent qui delegue la classification au backend.

## Ecrans impactes

- `AddSourceScreen` (apps/mobile/lib/features/sources/screens/add_source_screen.dart)

## Prerequis

- PR1 backend mergee et deployee (POST /api/sources/smart-search fonctionnel)
- Compte utilisateur connecte

---

## Scenarios de test

### Scenario 1 — URL directe
**Action** : Taper `lemonde.fr` dans le champ de recherche
**Attendu** : Apres ~1-2s, une ou plusieurs cartes enrichies s'affichent avec le nom "Le Monde", une favicon, les 3 derniers articles, et les boutons "Apercu" / "Ajouter"

### Scenario 2 — Mot-cle vague
**Action** : Taper `tech news` et attendre le debounce (350ms)
**Attendu** : Liste de resultats pertinents (sources tech). Chaque carte montre favicon + derniers articles + CTAs

### Scenario 3 — @handle YouTube
**Action** : Taper `@HugoDecrypte`
**Attendu** : Resultat(s) avec type "YouTube", icone YouTube, derniers videos dans la preview

### Scenario 4 — r/subreddit Reddit
**Action** : Taper `r/technology`
**Attendu** : Resultat(s) avec type "Reddit", derniers posts affiches

### Scenario 5 — URL invalide / requete sans resultat
**Action** : Taper `xyznotarealsite12345`
**Attendu** : Message "Aucun resultat pour ..." avec suggestion d'essayer une URL directe

### Scenario 10 — Skeleton loading
**Action** : Taper une requete et observer immediatement
**Attendu** : 3 cartes skeleton avec animation pulsante s'affichent pendant le chargement, puis disparaissent quand les resultats arrivent

### Scenario 11 — Clear button
**Action** : Taper du texte puis appuyer sur le bouton X dans le champ
**Attendu** : Le champ se vide, l'ecran revient a l'etat vide (trending + AtlasFlux)

### Scenario 12 — Ajouter une source
**Action** : Chercher une source, puis appuyer sur "Ajouter" sur une carte resultat
**Attendu** : Toast "Source ajoutee !", le bouton se transforme en "Ajoutee" (vert, desactive). La source apparait dans la liste des sources de l'utilisateur.

---

## Criteres d'acceptation

- [ ] Le SegmentedControl (3 onglets) n'apparait plus
- [ ] Le champ unique accepte tous les formats (URL, @handle, r/sub, mots-cles)
- [ ] Le debounce de 350ms fonctionne (pas d'appel API a chaque frappe)
- [ ] Les cartes enrichies affichent favicon, derniers articles, boutons
- [ ] Les etats loading/empty/error sont geres correctement
- [ ] L'ajout de source fonctionne et met a jour l'UI immediatement
- [ ] `flutter analyze` : 0 erreurs
- [ ] `flutter test` : tous les tests source passent
