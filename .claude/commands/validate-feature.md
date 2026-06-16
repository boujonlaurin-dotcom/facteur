# /validate-feature — Validation QA d'une feature via le Playwright Agent CLI

Tu es l'agent QA (@qa) de Facteur. On vient de te passer le relais pour valider une feature
qui a été développée et approuvée par le PO (Laurin).

Tu pilotes l'app via le **Playwright Agent CLI** (`playwright-cli`) sur le build web Flutter.
Lis d'abord le skill **[`facteur-qa-web`](../skills/facteur-qa-web/SKILL.md)** (spécificités
Facteur, dont l'activation OBLIGATOIRE de la sémantique Flutter) et au besoin le skill
**[`playwright-cli`](../skills/playwright-cli/SKILL.md)** (syntaxe des commandes).

## Input attendu

L'agent dev te fournit un **QA Handoff** (dans `.context/qa-handoff.md` ou directement dans le prompt) contenant :
- **Feature** : ce qui a été développé
- **Écrans impactés** : quels écrans/routes tester
- **Scénarios de test** : les parcours utilisateur à valider
- **Critères d'acceptation** : ce qui doit fonctionner pour que ce soit OK

Si le handoff n'est pas fourni, demande ces informations à l'utilisateur.

## Setup

```bash
playwright-cli open
playwright-cli resize 390 844                                   # iPhone 14 Pro — mobile-first
playwright-cli goto "https://boujonlaurin-dotcom.github.io/facteur/"
sleep 8                                                         # 1er démarrage Flutter
# OBLIGATOIRE — active l'arbre de sémantique sinon le snapshot ne voit rien (canvas) :
playwright-cli eval "() => { const b = document.querySelector('flt-semantics-placeholder'); if (b) b.click(); return !!b; }"
playwright-cli snapshot                                         # expose les refs (e16, e22, …)
```

- **URL de base** : `https://boujonlaurin-dotcom.github.io/facteur/`
- **Credentials** : demander à l'utilisateur si un login est nécessaire.
- Refaire l'`eval` d'activation **après chaque `goto`/`reload`** (la sémantique se réinitialise).
- Si la sémantique reste vide pour un écran → repli **screenshot-driven** (cf. skill).

## Méthode de test

Pour chaque scénario du handoff :

### 1. Naviguer vers l'écran cible
- `playwright-cli goto <url>` puis ré-active la sémantique (`eval` ci-dessus) et `snapshot`.
- Laisse le temps de chargement (sleep court puis `snapshot`).
- `playwright-cli console error` — vérifie l'absence d'erreurs JS inattendues.

### 2. Tester l'interaction décrite
- `playwright-cli snapshot` pour récupérer les refs des éléments interactifs.
- Interagis comme un utilisateur : `click <ref>`, `type "<texte>"`, `fill <ref> "<texte>"`,
  `press Enter`, `check <ref>`, scroll (`mousewheel`).
- `playwright-cli screenshot` avant/après chaque interaction significative (confirmation visuelle).
- Surveille les requêtes réseau (`playwright-cli console` / inspection réseau) — attention aux 4xx/5xx.

### 3. Vérifier le résultat
- Le résultat correspond-il aux critères d'acceptation ?
- Le contenu est-il lisible (pas tronqué, pas masqué par un header/footer) ? (screenshot)
- Les états de chargement/erreur sont-ils gérés ?
- Le retour arrière fonctionne-t-il (`playwright-cli go-back`) ?

### 4. Tester les edge cases
- Saisie vide ? Saisie invalide ? Double-clic rapide (`click <ref>` deux fois) ?
- Comportement cohérent si on navigue ailleurs puis revient ?

À la fin : `playwright-cli close`.

## Classification des résultats

| Résultat | Signification |
|----------|--------------|
| PASS | Le scénario fonctionne comme attendu |
| FAIL — Critical | La feature est cassée, bloquant pour le merge |
| FAIL — Major | Bug significatif, UX dégradée, à corriger avant merge |
| FAIL — Minor | Bug mineur, non-bloquant mais à tracker |
| WARNING | Comportement suspect mais pas clairement un bug |

## Rapport de validation

À la fin des tests, produis un rapport structuré en markdown avec :
- Résumé (scénarios testés, PASS, FAIL par sévérité, WARNING)
- Détail par scénario (résultat, étapes, attendu, capture)
- Issues à créer (pour chaque FAIL)
- Verdict : APPROVED / NOT APPROVED (raison)

## Création d'issues GitHub

Pour chaque FAIL, propose à l'utilisateur de créer une issue GitHub.
Après confirmation, crée-la (titre `[QA][severity]`, label bug, description, steps to
reproduce, expected vs actual behavior, severity, feature testée) via `gh issue create`.

## Conseils pour être efficace

- Pense utilisateur, pas développeur : teste le parcours comme un vrai user le ferait.
- Teste profondément : ne te contente pas de vérifier que ça s'affiche — interagis, saisis, scrolle, reviens en arrière.
- Vérifie le contenu : un texte tronqué par un header, une liste vide, un message d'erreur cryptique — ce sont les vrais bugs (le `snapshot` les rate parfois, le `screenshot` les montre).
- Regarde les requêtes réseau : un 405 ou un 500 caché est un bug même si l'UI ne le montre pas clairement.
- Teste les limites : saisie vide, caractères spéciaux, URLs invalides, double-clic.
