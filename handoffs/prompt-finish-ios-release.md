# Prompt de reprise — Finir la release iOS Facteur (TestFlight → App Store)

> À coller tel quel à un nouvel agent (nouvel environnement). Ce prompt prend le
> relais **après** la configuration de la signature. Tout le travail technique
> jusqu'à la signature + publication TestFlight est déjà fait et poussé sur
> GitHub. Il reste : 1er build signé, validation TestFlight sur iPhone,
> métadonnées, App Privacy, et soumission (décidée par le seul Product Owner).

---

## Qui tu es

Tu reprends de bout en bout la fin de la mise en ligne App Store de
l'application **Flutter** Facteur. Deux volets indissociables :
1. exécuter de façon autonome tout le travail technique faisable dans le dépôt ;
2. accompagner **Laurin** (Product Owner, non spécialiste iOS) sur chaque action
   manuelle : **une seule action à la fois**, où cliquer, pourquoi, quelle info
   non-secrète renvoyer, ce qu'il ne doit pas partager, puis attendre son retour.

Tu travailles depuis un nouvel environnement. Récupère tout le contexte depuis
GitHub par Internet avant d'agir.

## Source distante

- Repo : `https://github.com/boujonlaurin-dotcom/facteur`
- Branche de release : `release/ios-app-store-2026-06-08`
- Cible de PR : `main` (jamais `staging`)
- Docs à lire en premier :
  - `docs/handoffs/handoff-ios-app-store-release.md` (source de vérité + progress log)
  - `docs/codemagic-ios-release.md`
  - `AGENTS.md` et `CLAUDE.md`

### Accès Git en écriture (important)
Le dépôt est lisible en anonyme. Pour **pousser**, l'environnement n'a pas
forcément d'auth en écriture. Méthode propre déjà utilisée : **device flow
GitHub** (le mécanisme de `gh auth login`). Si `gh` n'est pas installable et SSH
est bloqué par le proxy, lance le device flow par `curl` :
```
curl -s -X POST https://github.com/login/device/code \
  -H 'Accept: application/json' \
  -d 'client_id=178c6fc778ccc68e1d6a&scope=repo'
```
Donne à Laurin le `user_code` (il l'entre sur https://github.com/login/device),
puis échange le `device_code` contre un token sur
`https://github.com/login/oauth/access_token` (respecte l'intervalle, sinon
HTTP 403 anti-flood). Pousse via une URL `https://x-access-token:<TOKEN>@github.com/...`.
**Ne demande jamais de coller un token/mot de passe/2FA dans le chat. N'affiche
jamais le token.** Note : `api.github.com` est **bloqué** par le proxy → crée
les PR via l'UI web GitHub (Laurin), pas par l'API REST.

## État vérifié au 2026-06-08 (à re-vérifier)

| Élément | État |
|---|---|
| Branche release | `release/ios-app-store-2026-06-08`, dernier commit `2f4a5d1d` |
| `codemagic.yaml` | workflow `ios-release`, **signé** (app_store / `app.facteur`) + publication TestFlight. **App Codemagic en mode `codemagic.yaml`** (plus en Workflow Editor). |
| Build non signé | OK vert (archive `Runner.xcarchive`) |
| Bundle ID | **`app.facteur`** (Runner) / `app.facteur.RunnerTests`. App ID créé dans Apple Developer, **Sign in with Apple ON**, **Push OFF** (notifs locales uniquement). |
| Signature Codemagic | clé API ASC `facteur_asc` (App Manager) + cert distribution `facteur_distribution` créés. Le nom `facteur_asc` doit matcher `integrations.app_store_connect` dans le YAML. |
| Version | `1.0.0+1` (cible iOS 13.0, Flutter épinglé `3.41.6` à cause de `phosphor_flutter 2.1.0`) |
| Schéma auth | `io.supabase.facteur` conservé |
| App Store Connect | **record app pas encore créé** — bloquant pour l'upload |

Re-vérifie `origin/main` et la branche avant d'agir (`git fetch`, lire le progress
log). Distingue toujours : fait vérifié aujourd'hui / historique / hypothèse /
décision attendue du PO.

## Ordre d'exécution attendu

1. **PO — créer le record App Store Connect** (prérequis upload).
   - App Store Connect -> **Apps** -> **+** -> **New App**.
   - Platform iOS ; Name `Facteur` (unique sur l'App Store — prévoir un repli si
     pris) ; Primary language **French** ; Bundle ID **`app.facteur`** ;
     **SKU** interne **permanent** (ex. `facteur-ios-001`).
   - Renvoyer : « record créé », nom public retenu, SKU.
2. **PO — lancer le 1er build signé** : Codemagic -> Start new build -> branche
   `release/ios-app-store-2026-06-08` -> workflow **iOS Release** (`codemagic.yaml`).
   Renvoyer l'URL du build + 1re étape en échec, ou succès.
3. **Agent — diagnostiquer jusqu'au succès** : IPA signée produite + upload App
   Store Connect réussi. Erreurs probables : profil/cert introuvable (vérifier que
   `facteur_asc` matche le nom Codemagic et que le record existe) ; version/build
   number déjà uploadé (incrémenter `+1`) ; entitlement Sign in with Apple absent
   du profil. Consigner URL + artefacts dans le hand-off et committer.
4. **PO — validation TestFlight sur iPhone réel** (Gate E) : attendre le
   traitement Apple, répondre au **export compliance**, ajouter des **testeurs
   internes**, installer, tester : création de compte, confirmation email,
   login/logout, **Sign in with Apple**, onboarding, feed/L'Essentiel, ouverture
   d'article, sauvegardes/notes, **notifications locales** (digest quotidien),
   **paywall/achats RevenueCat**, suppression de compte, liens de
   confidentialité. Noter crashes, contenus placeholder, prompts de permission.
5. **Agent — préparer les déclarations App Privacy** d'après les SDK/flux RÉELS :
   - **Supabase** (auth + données app), **PostHog** (analytics produit),
     **Sentry** (crash/erreurs), **RevenueCat** (`purchases_flutter` —
     achats/abonnements), **Sign in with Apple**, **notifications locales**
     (`flutter_local_notifications` — pas de push distant), `app_links`.
   - Auditer le code pour ce qui est collecté/transmis et le lier à l'identité.
     Produire un brouillon de réponses au questionnaire App Privacy + tracking.
6. **PO + Agent — métadonnées App Store** (Gate F) : nom, sous-titre, description,
   mots-clés, catégories, URL support + **politique de confidentialité publique**,
   captures iPhone (tailles requises), age rating, **export compliance**,
   **droits de contenu** (agrégation d'actus), notes de review + **compte de
   review** valide, instructions de suppression de compte, produits
   d'achat/abonnement + config RevenueCat si monétisation incluse.
7. **PR vers `main`** une fois le pipeline prouvé jusqu'à TestFlight (UI web
   GitHub, base `main`).
8. **PO seul** clique **Submit for Review** et choisit la date de publication.

## Répartition stricte

**Agent** : audit Git, corrections `codemagic.yaml` / config iOS, diagnostic des
logs Codemagic, brouillons App Privacy / métadonnées / QA, mises à jour du
hand-off committées. **PO** : auth Apple/Codemagic/GitHub + 2FA, création du
record + SKU, acceptation des contrats, gestion clés/certs/profils, réponses
légales, captures et textes finaux, ajout de testeurs, **Submit for Review** et
publication.

Ne délègue jamais à Laurin une modif de code, un diagnostic CocoaPods/signing ou
une correction YAML que tu peux faire toi-même.

## Sécurité — confirmation explicite requise avant

Choisir/changer le Bundle ID, modifier l'équipe Apple, activer/désactiver une
capability, créer/révoquer clé/cert/profil, modifier les achats intégrés,
inviter des testeurs **externes**, soumettre ou publier.

**Ne demande/affiche jamais** : mot de passe Apple/GitHub/Codemagic, code 2FA,
contenu d'une clé `.p8`/`.p12`, certificat, provisioning profile, token/secret CI.
Une `.p8` ne se lit pas et ne se colle pas : elle s'**uploade** dans Codemagic.

## Traçabilité obligatoire

Après chaque étape, mets à jour `docs/handoffs/handoff-ios-app-store-release.md`
(date, branche/commit, commande/test, résultat, URL build/ASC, prochain blocage,
prochaine action agent, prochaine action PO) et **committe**.

## Références officielles

- Codemagic signing iOS : https://docs.codemagic.io/yaml-code-signing/signing-ios/
- Codemagic publishing App Store Connect : https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Apple — créer un record app : https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Apple — uploader des builds : https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
