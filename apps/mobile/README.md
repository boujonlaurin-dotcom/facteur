# Facteur - Application Mobile

Application Flutter pour Facteur, le compagnon de curation intelligente de contenus.

## 🚀 Setup

### Prérequis

- Flutter 3.24+ ([Installation](https://docs.flutter.dev/get-started/install))
- Xcode 15+ (pour iOS)
- Un compte Supabase configuré
- Un compte RevenueCat configuré

### Installation

1. **Installer Flutter** (si pas déjà fait) :
   ```bash
   # macOS avec Homebrew
   brew install flutter
   
   # Vérifier l'installation
   flutter doctor
   ```

2. **Installer les dépendances** :
   ```bash
   cd apps/mobile
   flutter pub get
   ```

3. **Télécharger les polices** :
   - [Fraunces](https://fonts.google.com/specimen/Fraunces) → `assets/fonts/`
   - [DM Sans](https://fonts.google.com/specimen/DM+Sans) → `assets/fonts/`
   
   Fichiers requis :
   - `Fraunces-Regular.ttf`
   - `Fraunces-Medium.ttf`
   - `Fraunces-SemiBold.ttf`
   - `Fraunces-Bold.ttf`
   - `DMSans-Regular.ttf`
   - `DMSans-Medium.ttf`
   - `DMSans-Bold.ttf`

4. **Configurer les variables d'environnement** :
   ```bash
   # Dans Xcode ou via --dart-define
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   REVENUECAT_IOS_KEY=your-revenuecat-key
   API_BASE_URL=http://localhost:8000/api
   ```

5. **Lancer l'app** :
   ```bash
   flutter run
   ```

## 📁 Structure

```
lib/
├── main.dart                 # Entry point
├── app.dart                  # MaterialApp configuration
├── config/
│   ├── constants.dart        # Constantes globales
│   ├── theme.dart            # Thème Facteur (dark mode)
│   └── routes.dart           # Configuration go_router
├── core/
│   ├── api/                  # Client HTTP Dio
│   ├── auth/                 # Auth state Supabase
│   └── storage/              # Cache Hive
├── features/
│   ├── auth/                 # Login/Signup
│   ├── onboarding/           # Questionnaire d'onboarding
│   ├── feed/                 # Feed principal
│   ├── detail/               # Détail contenu
│   ├── sources/              # Gestion sources
│   ├── saved/                # Contenus sauvegardés
│   ├── progress/             # Streak & progression
│   ├── settings/             # Paramètres
│   └── subscription/         # Premium & paywall
├── shared/
│   ├── widgets/              # Composants réutilisables
│   └── utils/                # Utilitaires
└── models/                   # Modèles de données
```

## 🎨 Design System

### Couleurs

| Rôle | Hex |
|------|-----|
| Background Primary | `#121212` |
| Background Secondary | `#1A1A1A` |
| Surface | `#1E1E1E` |
| Primary (Terracotta) | `#E07A5F` |
| Secondary (Bleu) | `#6B9AC4` |
| Text Primary | `#F5F5F5` |

### Typographie

- **Titres** : Fraunces (serif)
- **Corps** : DM Sans (sans-serif)

## 🧪 Tests

```bash
flutter test
```

## 📱 Build

### Android — canal `beta` (side-load via GitHub Releases)

Conserve l'auto-update intégré (télécharge l'APK depuis GitHub Releases puis
déclenche l'installeur Android via `REQUEST_INSTALL_PACKAGES`). C'est ce que
fait CI dans `.github/workflows/build-apk.yml` à chaque push sur `main`.

```bash
flutter build apk --flavor beta --release \
  --dart-define=APP_RELEASE_TAG=beta-$(date +'%Y%m%d-%H%M') \
  --dart-define=API_BASE_URL=https://facteur-production.up.railway.app/api/ \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

`applicationId` = `com.example.facteur.beta` (suffix `.beta`) → cohabite avec
le build playstore sur un même device.

### Android — canal `playstore` (AAB sans auto-update)

Pas d'auto-update (Play Store distribue les MAJ), pas de
`REQUEST_INSTALL_PACKAGES`. Le flag `PLAYSTORE_BUILD=true` court-circuite
`appUpdateProvider`.

```bash
flutter build appbundle --flavor playstore --release \
  --dart-define=PLAYSTORE_BUILD=true \
  --dart-define=API_BASE_URL=https://facteur-production.up.railway.app/api/ \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

`applicationId` = `com.example.facteur` (sans suffix) → c'est l'app
publiée sur le Play Store.

### iOS

```bash
flutter build ios --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=API_BASE_URL=...
```

## 📚 Documentation

- [PRD](/docs/prd.md)
- [Architecture](/docs/architecture.md)
- [Specs UI/UX](/docs/front-end-spec.md)

