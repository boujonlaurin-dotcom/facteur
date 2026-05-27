# Codemagic iOS Release

`codemagic.yaml` lives at the repository root because this repository is a monorepo.

The iOS release workflow uses `APP_DIR=apps/mobile`, which is the Flutter mobile project directory. This directory contains `pubspec.yaml`, declares the Flutter SDK dependency, and includes the expected `ios/`, `android/`, and `lib/` folders.

The first workflow, `ios-release`, builds an unsigned release IPA with:

```bash
flutter build ipa --release --no-codesign
```

This validates the Flutter, CocoaPods, and iOS archive pipeline on Codemagic before adding Apple signing and App Store Connect upload. `flutter analyze` is currently informational in CI because the local project reports existing analyzer issues; the workflow continues so the unsigned IPA build can still be validated.

To publish to TestFlight or App Store Connect, configure the following in Codemagic, not in the repository:

- App Store Connect API key
- iOS signing certificate
- provisioning profile
- bundle identifier
- optional automatic App Store Connect upload

Do not commit App Store Connect keys, `.p8`, `.p12`, `.mobileprovision`, passwords, tokens, or any other secret material.
