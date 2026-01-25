 # Bug: logo Android manquant/pixelise

## Contexte

Le nouveau logo est visible sur Chrome, mais ne s'affiche pas dans l'app
Android, et l'icone du menu Android est mal centree et pixelisee.

## Probleme

- L'asset utilise par `FacteurLogo` ne se charge pas sur Android.
- L'icone adaptive pointe vers une ressource inexistante, ce qui degrade le rendu.

## Attendu

- Le logo s'affiche dans l'app Android.
- L'icone du menu Android est propre, centree et nette.

## Pistes techniques

- Ajouter un fallback d'asset sans espaces pour `FacteurLogo`.
- Ajuster l'icone adaptive pour utiliser une ressource existante.
- Si le rendu reste flou, fournir un PNG foreground transparent (haute resolution).

## Verification

- Ouvrir l'app Android et verifier le logo sur l'ecran de splash.
- Ouvrir le menu Android et verifier l'icone.
