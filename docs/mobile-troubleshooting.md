# Flutter Troubleshooting — Environment & Builds

Ce document centralise les problèmes courants rencontrés lors du développement et du build de l'application mobile Facteur, ainsi que leurs solutions.

## 1. Environnement Flutter

### 1.1 Localiser le SDK Flutter
Sur macOS, si la commande `flutter` n'est pas trouvée (`command not found`), le SDK est souvent installé via Homebrew ou dans un dossier de développement.

**Chemins communs :**
- `/opt/homebrew/share/flutter/bin` (Installation via Homebrew)
- `~/development/flutter/bin`
- `~/flutter/bin`

**Trouver le chemin via Dart :**
Si `dart` est accessible mais pas `flutter`, lancez :
```bash
which dart
```
Le dossier `bin` de Flutter est généralement le parent de ce chemin (ou proche).

### 1.2 Fix Permanent du PATH (zsh)
Ajoutez cette ligne à votre fichier `~/.zshrc` :
```bash
export PATH="$PATH:/opt/homebrew/share/flutter/bin"
```
Puis rechargez la configuration :
```bash
source ~/.zshrc
```

## 2. Erreurs de Build (APK / iOS)

### 2.1 Erreur "No such file or directory" sur un fichier existant
Si le build échoue en disant qu'un fichier Dart est manquant alors qu'il est présent sur le disque, c'est généralement un problème de cache `.dart_tool` ou de fichiers non suivis par Git (pour la CI).

**Solution radicale (Clean Build) :**
Exécutez ces commandes dans `apps/mobile` :
```bash
# 1. S'assurer que les nouveaux fichiers sont trackés
git add .

# 2. Nettoyage complet
flutter clean
rm -rf .dart_tool pubspec.lock

# 3. Réinstaller et Build
flutter pub get
flutter build apk
```

## 3. Adressage API Local
Pour que l'application mobile puisse contacter le backend en local :
- **iOS Simulator / Web** : `http://localhost:8080`
- **Android Emulator** : `http://10.0.2.2:8080`
- **App physique** : Utilisez l'IP locale de votre machine (ex: `192.168.x.x`) et assurez-vous d'être sur le même WiFi.
