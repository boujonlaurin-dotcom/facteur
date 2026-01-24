# Maintenance: Android App Icon

**Date:** 2026-01-22  
**Classification:** MAINTENANCE

---

## Problème

Le build échoue lors de la génération des icônes Android :
`PathNotFoundException: Cannot open file, path = 'assets/icons/facteur_logo.png'`.
Le fichier d'icône est présent localement mais non versionné, donc absent en CI.

**Fichiers concernés:**
- `apps/mobile/android/app/src/main/res/mipmap-*/launcher_icon.png` - Tous les fichiers contiennent le logo Flutter
- `apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml` - Référence `ic_launcher_foreground` (manquant)
- `apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/` - Également affecté

---

## Résolution

### Prérequis
1. Avoir le logo Facteur haute résolution (1024x1024px, PNG)
2. Utiliser `flutter_launcher_icons` pour générer les assets

### Étapes

1. **Ajouter le logo source au repo**
   - Versionner `apps/mobile/assets/icons/facteur_logo.png`

2. **Configuration pubspec.yaml**
```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/icons/facteur_logo.png"
  adaptive_icon_background: "#E07A5F"  # Terracotta (accent PRD)
  adaptive_icon_foreground: "assets/icons/facteur_logo.png"
```

3. **Exécuter le générateur**
```bash
cd apps/mobile
flutter pub get
dart run flutter_launcher_icons
```

---

## Vérification

```bash
# Build Android
flutter build apk --debug
# Installer sur émulateur et vérifier l'icône dans le launcher
```
