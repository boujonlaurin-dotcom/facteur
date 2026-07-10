---
name: facteur-qa-web
description: Spécificités QA web de Facteur — comment piloter le build Flutter web (canvas/CanvasKit) avec le Playwright Agent CLI. À lire AVANT toute session /validate-feature ou test UI sur l'app.
---

# QA web de Facteur (Playwright Agent CLI)

Facteur se teste via son **build web Flutter** — seule surface « browsable ».
Ce skill capture ce qui est propre à Facteur ; pour la syntaxe générale du CLI,
voir le skill [`playwright-cli`](../playwright-cli/SKILL.md).

## Paramètres de base

- **URL de base** : `https://boujonlaurin-dotcom.github.io/facteur/`
  (GitHub Pages, build du flavor `staging`, pointe l'API staging `api-staging-40d3`).
- **Viewport** : **390×844** (iPhone 14 Pro) — l'app est mobile-first.
  `playwright-cli resize 390 844` AVANT toute interaction.
- **Login** : demander les credentials à l'utilisateur si un scénario l'exige
  (écran `/#/login`). Sinon rester sur les écrans publics.

## ⚠️ Flutter web = canvas → activer la sémantique au boot (OBLIGATOIRE)

Le build rend dans un `<canvas>` (CanvasKit) : **les widgets ne sont pas du DOM**.
Tant que l'arbre de sémantique Flutter n'est pas activé, `snapshot` ne renvoie
que le bouton « Enable accessibility » et un placeholder « Chargement de
Facteur… » — donc **aucun ref cliquable**.

Le bouton natif « Enable accessibility » est positionné **hors viewport** : un
`click` dessus échoue (« element is outside of the viewport »). Le contournement
fiable est de cliquer le placeholder via `eval` :

```bash
playwright-cli open
playwright-cli resize 390 844
playwright-cli goto "https://boujonlaurin-dotcom.github.io/facteur/"
sleep 8   # 1er démarrage Flutter = quelques secondes
# Active l'arbre de sémantique → débloque les refs du snapshot :
playwright-cli eval "() => { const b = document.querySelector('flt-semantics-placeholder'); if (b) b.click(); return !!b; }"
playwright-cli snapshot   # expose désormais textbox/button/checkbox avec refs (e16, e22, …)
```

Une fois la sémantique active, le **flux nominal est viable** :
`snapshot` → `click <ref>` / `type` / `fill <ref> <texte>` fonctionnent
normalement (vérifié : saisie dans « Email », clic « Se connecter », etc.).

> À refaire **après chaque rechargement complet** de page (`goto`, `reload`) :
> la sémantique se réinitialise. En cas de doute, refaire l'`eval` puis re-`snapshot`.

### Repli screenshot-driven

Si la sémantique reste vide pour un écran (widget custom non sémantisé), basculer
en **screenshot-driven** : `playwright-cli screenshot` pour lire l'écran, puis
cliquer par coordonnées (`playwright-cli click <x> <y>` ou `mousemove`+`mousedown`).
Le `screenshot` reste de toute façon utile comme **confirmation visuelle** d'un
état (texte tronqué, carte masquée par un header/footer) que le snapshot ne montre pas.

## Bonnes pratiques Facteur

- Après une action significative : `console error` (aucune erreur JS attendue ;
  une erreur résiduelle au boot est connue) et surveiller les requêtes réseau
  (4xx/5xx inattendus = bug même si l'UI ne le montre pas).
- Penser **utilisateur** : interagir, saisir, scroller, revenir en arrière —
  pas seulement vérifier l'affichage.
- Pointeur QA pré-release : **[`docs/qa/pre-release-qa-plan.md`](../../../docs/qa/pre-release-qa-plan.md)**
  (parcours clés + features récentes à couvrir avant la mise en store).
