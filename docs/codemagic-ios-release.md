# Codemagic iOS Release

> **Current status (June 8, 2026):** this workflow has not produced a verified
> unsigned IPA yet. Read the
> [active iOS/App Store handoff](handoffs/handoff-ios-app-store-release.md)
> before running or modifying it. In particular, the canonical checkout does
> not currently contain a tracked `apps/mobile/ios/Podfile`, while the workflow
> explicitly runs `pod install`.

`codemagic.yaml` lives at the repository root because this repository is a monorepo.

The iOS release workflow uses `APP_DIR=apps/mobile`, which is the Flutter mobile project directory. This directory contains `pubspec.yaml`, declares the Flutter SDK dependency, and includes the expected `ios/`, `android/`, and `lib/` folders.

The first workflow, `ios-release`, builds an unsigned release IPA with:

```bash
flutter build ipa --release --no-codesign
```

This validates the Flutter, CocoaPods, and iOS archive pipeline on Codemagic before adding Apple signing and App Store Connect upload. `flutter analyze` is currently informational in CI because the local project reports existing analyzer issues; the workflow continues so the unsigned IPA build can still be validated.

The workflow pins Flutter to `3.41.6` for now. Newer Flutter stable releases mark `IconData` as `final`, which breaks the current `phosphor_flutter 2.1.0` dependency. Remove this pin after migrating the icon package or after `phosphor_flutter` publishes a compatible release.

To publish to TestFlight or App Store Connect, configure the following in Codemagic, not in the repository:

- App Store Connect API key
- iOS signing certificate
- provisioning profile
- bundle identifier
- optional automatic App Store Connect upload

Do not commit App Store Connect keys, `.p8`, `.p12`, `.mobileprovision`, passwords, tokens, or any other secret material.
