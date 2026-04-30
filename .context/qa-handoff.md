# QA Handoff — « Bonnes nouvelles du jour » : mobile + push notification

## Feature développée

Repositionnement mobile du digest serein de « Lecture apaisée » → « Bonnes
nouvelles du jour ». Ajoute (1) un renommage end-to-end de la pill, des
titres et de la copy interests ; (2) un badge « À LA UNE · N sources » sur
le sujet rang 1 multi-sources ; (3) un canal de notification push local
dédié, opt-in indépendant du push principal (modal d'activation + écran
profil > notifications), avec règle stricte d'absence de couplage entre
les deux opt-ins.

## PR associée

À créer via `/go` (PR vers `main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed (carte d'entrée digest) | `/feed` | Modifié — pill + titre carte serein |
| Digest (hero) | `/digest` | Modifié — pill + titre adaptés au mode |
| Digest (sujets) | `/digest` | Modifié — badge « À LA UNE · N sources » |
| Mes Intérêts (mode serein) | `/interests` | Modifié — copy renommée |
| Modal d'activation notif | n/a (overlay) | Modifié — section indépendante « Bonnes nouvelles » |
| Profil > Notifications | `/profile/notifications` | Modifié — toggle Bonnes nouvelles + horaire |

## Scénarios de test

### Scénario 1 : Renommage carte feed (happy path)
**Parcours** :
1. Aller sur `/feed`
2. Observer la 2e carte d'entrée digest
**Résultat attendu** :
- Pill `BONNES NOUVELLES` (couleur serein verte conservée)
- Titre `Les bonnes nouvelles du jour`
- Tap → ouvre `/digest` en mode serein

### Scénario 2 : Renommage hero digest serein
**Parcours** :
1. Tap la carte « Bonnes nouvelles » depuis le feed
2. Observer le hero du digest
**Résultat attendu** :
- Pill `BONNES NOUVELLES` (au lieu de `L'ESSENTIEL`)
- Titre `Les bonnes nouvelles du jour`
- Si on bascule vers le mode normal (toggle serein OFF) : pill et titre
  reviennent à `L'ESSENTIEL` + `L'essentiel du jour`.

### Scénario 3 : Badge « À LA UNE · N sources » (rang 1 multi-sources)
**Parcours** :
1. Ouvrir le digest avec un sujet rang 1 ayant `is_une=true` et
   `source_count >= 2`
2. Observer la zone des badges sous le titre du sujet
**Résultat attendu** :
- Badge terracotta `À LA UNE · 4 sources` (count = `source_count` API,
  pas `articles.length`)
- Couleur clairement distincte de la pill `BONNES NOUVELLES` (verte)
  et de la pill `L'ESSENTIEL` (orange/primary)

### Scénario 4 : Badge absent quand single-source
**Parcours** :
1. Ouvrir un digest dont le rang 1 a `is_une=true` mais `source_count=1`
2. Observer
**Résultat attendu** :
- Aucun badge « À LA UNE » affiché — le sujet rang 1 est rendu comme un
  sujet ordinaire.

### Scénario 5 : Modal d'activation — opt-in indépendant (CRITIQUE)
**Parcours** :
1. Première ouverture de l'app (état: `modal_seen=false`)
2. Modal d'activation s'affiche
3. **Sans toucher au toggle Bonnes nouvelles**, choisir préset + horaire
   du push principal, taper `Activer ton Facteur`
4. Aller dans Profil > Notifications
**Résultat attendu** :
- Push principal activé (préset + horaire enregistrés)
- Toggle « Bonnes nouvelles du jour » reste **OFF** dans Profil
- AUCUNE notification Bonnes nouvelles planifiée

### Scénario 6 : Modal — opt-in Bonnes nouvelles
**Parcours** :
1. Réinitialiser, ouvrir la modal
2. Activer le switch « 🌱 Bonnes nouvelles du jour », choisir un horaire
   (par défaut soir)
3. Taper `Activer ton Facteur`
**Résultat attendu** :
- Les 2 canaux sont activés (digest principal + bonnes nouvelles)
- L'horaire bonnes nouvelles est indépendant de l'horaire principal

### Scénario 7 : Profil > Notifications — découvrabilité
**Parcours** :
1. Utilisateur a activé uniquement le push principal au scénario 5
2. Quelques jours plus tard, va dans Profil > Notifications
3. Observer
**Résultat attendu** :
- Section « 🌱 Bonnes nouvelles du jour » visible avec son toggle
  (même si le push principal est ON)
- Tap toggle → demande de permission OS si nécessaire, puis
  `TimeSlotSelector` apparaît

### Scénario 8 : Désactivation Bonnes nouvelles
**Parcours** :
1. Bonnes nouvelles activées avec horaire `evening`
2. Profil > Notifications → toggle Bonnes nouvelles OFF
**Résultat attendu** :
- Notification Bonnes nouvelles annulée
- Push principal et community pick non impactés

### Scénario 9 : Copy mes intérêts (mode serein)
**Parcours** :
1. Activer le mode serein
2. Aller sur Mes Intérêts
**Résultat attendu** :
- Titre `Vos bonnes nouvelles` (au lieu de `Votre mode serein`)
- Sous-titre `Choisissez ce qui reste dans vos bonnes nouvelles…`
  (sans mention « bulle apaisée »)

## Critères d'acceptation

- [ ] Toutes occurrences `LECTURE APAISÉE` / `Une lecture apaisée` ont
      disparu de l'UI mobile (sauf comments internes ou la copy filter
      bar « Rester serein » du feed, hors scope).
- [ ] Pill `BONNES NOUVELLES` rendue dans la carte feed et dans le hero
      digest mode serein.
- [ ] `DigestTopic.sourceCount` lit la valeur API `source_count` (pas
      `articles.length`).
- [ ] Badge « À LA UNE · N sources » affiché si et seulement si
      `topic.isUne == true && topic.sourceCount >= 2`.
- [ ] Toggle « Bonnes nouvelles » présent dans la modal d'activation +
      l'écran Profil > Notifications.
- [ ] Activer le push principal n'active jamais le canal Bonnes
      nouvelles (et inversement).
- [ ] `flutter test` sur les fichiers touchés passe : digest_entry_card,
      a_la_une_badge, push_notification_service_copy.
- [ ] `flutter analyze` ne crée pas de NOUVEAU error / warning par
      rapport à la baseline (info-level OK).

## Zones de risque

1. **Modèle `DigestTopic.sourceCount` : changement de getter → champ
   API.** Tous les endroits qui construisaient un `DigestTopic` dans des
   tests sans passer `sourceCount` recevront `0` par défaut (au lieu de
   `articles.length`). Vérifier qu'aucun test fixture ne dépend
   implicitement de l'ancien comportement.
2. **Couplage opt-in (CRITIQUE).** Toute régression qui pré-coche le
   toggle Bonnes nouvelles automatiquement (par ex. en lisant
   `serein_enabled` du provider) viole la règle. Ne PAS modifier
   `_GoodNewsSection` pour qu'elle écoute autre chose que son propre
   état.
3. **Push notification permission.** Sur Android, `setGoodNewsEnabled`
   re-demande la permission OS. Si le user a déjà accordé pour le push
   principal, le système devrait répondre immédiatement sans re-prompt.
   À vérifier sur device réel.
4. **Persistance Hive.** Les nouvelles clés `notif_good_news_enabled`
   et `notif_good_news_time_slot` n'existent pas pour les users
   existants — fallback `false` / `evening` côté `_loadFromHive`.
5. **Backend non touché** — l'API expose déjà `is_une` + `source_count`
   sur `DigestTopic`. Si l'un des deux disparaît côté pipeline (par ex.
   refactor), le badge ne s'affichera jamais.

## Dépendances

- Endpoint API : `GET /api/digest/both` (ne change pas — déjà expose
  `is_une` + `source_count` sur les topics serein).
- Pas de migration backend.
- Pas de sender FCM/APNS (push 100% local via
  `flutter_local_notifications`).
