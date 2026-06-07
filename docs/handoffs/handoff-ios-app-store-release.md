# Handoff: Facteur iOS / App Store Release

**Status date:** June 8, 2026

**Canonical repository:** `/Users/laurinboujon/facteur`

**Flutter application:** `apps/mobile`

**Release status:** blocked before the first successful unsigned Codemagic IPA

This document preserves the useful context from the May 27, 2026 Codex
sessions and replaces their stale worktree-specific instructions. It is the
starting point for any agent working on iOS release, Codemagic, TestFlight,
App Store Connect, bundle identifiers, signing, or provisioning.

## Executive Summary

The repository has an initial `codemagic.yaml`, but the release pipeline has
not been proven. Do not ask the product owner to configure certificates or
publish anything yet.

The immediate sequence is:

1. An agent repairs and validates the unsigned Codemagic workflow.
2. The product owner confirms the real Apple bundle ID.
3. An agent applies that confirmed bundle ID and prepares signed-build YAML.
4. The product owner connects Apple credentials in Codemagic.
5. An agent runs and diagnoses the first signed build.
6. The product owner validates the build in TestFlight and completes App Store
   metadata, privacy answers, review information, and submission.

## Verified Current State

These facts were checked in the canonical checkout on June 8, 2026:

| Item | Current state | Consequence |
|---|---|---|
| Flutter project | `apps/mobile` | All Flutter commands must run there. |
| App version | `1.0.0+1` | Confirm release version/build number before upload. |
| iOS display name | `Facteur` | No known blocker. |
| Bundle ID | `com.example.facteur` | Placeholder; cannot be used for the real release unless Apple was intentionally configured with it. |
| iOS deployment target | `13.0` | Revalidate against current dependencies during CI build. |
| Signing style | Automatic | No development team is committed in the Xcode project. |
| App icon | 1024x1024 RGB PNG, no alpha | The App Store icon asset is present. |
| Sensitive `Info.plist` usage descriptions | None currently declared | Re-check against actual native features before submission. |
| Flutter toolchain | Local Flutter `3.41.6`, Dart `3.11.4` | Codemagic is pinned to Flutter `3.41.6`. |
| Local Xcode | Full Xcode is not installed/selected | `xcodebuild` and local iOS archive remain unavailable on this Mac. |
| Codemagic config | Two local commits, not on the remote branch as of local Git state | Codemagic cannot consume those commits until they are safely integrated and pushed. |
| CocoaPods files | No tracked `apps/mobile/ios/Podfile` or `Podfile.lock` | The current explicit `cd "$APP_DIR/ios" && pod install` CI step will fail. |

The working tree also contains unrelated product-owner work in
`apps/mobile/lib/features/feed/widgets/feed_card.dart` and an untracked
`.envrc`. Do not overwrite, stage, commit, or discard those changes as part of
the release work.

## Recovered May 27 Context

The original local iOS attempt established:

- Flutter commands had initially been run outside `apps/mobile`, causing
  `No pubspec.yaml file found`.
- `flutter clean` and `flutter pub get` succeeded from the correct directory.
- The Mac only had Xcode Command Line Tools. Full Xcode was absent, so a local
  iOS release/archive could not be completed.
- The App Store icon was checked as 1024x1024 RGB without alpha.
- The project used the placeholder bundle ID `com.example.facteur`.
- No bundle ID, team, certificate, profile, or App Store setting was to be
  changed without product-owner confirmation.

The later Codemagic attempt established:

- `codemagic.yaml` belongs at the repository root.
- The intended YAML workflow is `ios-release`, with `APP_DIR=apps/mobile`.
- Codemagic had run an auto-detected Android build (`bundleDebug`) instead of
  the YAML iOS workflow.
- Flutter stable then exposed an incompatibility between newer Flutter and
  `phosphor_flutter 2.1.0`, so the workflow was pinned to Flutter `3.41.6`.

Local commits containing that work:

- `3f4db01a` - add initial Codemagic iOS workflow
- `26938b1f` - pin Flutter to `3.41.6`

The current branch has diverged from `main`. A future agent must transplant or
rebuild the release changes on a fresh branch from current `main`; do not
blindly merge the old branch.

## Agent-Owned Work: Do This Before PO Setup

The next agent owns all of the following. Do not hand these technical steps to
the product owner.

### 1. Preserve unrelated local work

Inspect `git status` and isolate release work without losing the existing
`feed_card.dart` and `.envrc` changes. Use a separate worktree or another
non-destructive approach if needed.

### 2. Start from current `main`

Create a fresh release branch from current `main`. Bring over only the intended
Codemagic and documentation changes. Do not merge the old analytics branch as
a whole.

### 3. Repair the unsigned workflow

Resolve the missing CocoaPods project files deliberately. Determine whether to:

- restore a valid Flutter-generated `ios/Podfile` and track it; or
- remove the standalone `pod install` step and let the verified Flutter build
  command manage pods.

Do not guess. Compare with a newly generated Flutter iOS project for the pinned
Flutter version and inspect this project's plugins and Xcode configuration.

Then validate:

```bash
ruby -e 'require "yaml"; YAML.load_file("codemagic.yaml"); puts "YAML OK"'
git diff --check
```

Push the release branch, then in Codemagic manually start:

```text
Branch: the new release branch
Workflow: ios-release
Configuration: codemagic.yaml
```

The first gate is a successful unsigned iOS archive/IPA. Capture the Codemagic
build URL and final artifact names in this document.

### 4. Resolve the Flutter pin debt

For the first build, retain Flutter `3.41.6` unless testing proves another
version works. Separately assess upgrading/replacing `phosphor_flutter 2.1.0`.
Do not combine a broad icon migration with the first CI recovery unless the pin
itself is no longer supported by Codemagic.

### 5. Ask for exactly one Apple decision

After the unsigned build passes, ask the product owner for the exact explicit
bundle ID shown in Apple Developer and App Store Connect. Never infer it from
the app name and never ship `com.example.facteur` by accident.

### 6. Prepare signed build configuration

After the bundle ID is confirmed:

- update the Runner and RunnerTests bundle identifiers consistently;
- preserve the Supabase URL scheme unless an auth-flow change is intended;
- add Codemagic `ios_signing` with `distribution_type: app_store`;
- use the confirmed bundle ID;
- add `xcode-project use-profiles` if required by the selected Codemagic
  signing approach;
- build a signed IPA;
- configure App Store Connect publishing only after credentials exist.

Keep all `.p8`, `.p12`, `.mobileprovision`, passwords, private keys, and tokens
out of Git.

### 7. Verify before TestFlight handoff

Record evidence for:

- exact commit and branch;
- successful unsigned build;
- successful signed build;
- resolved bundle ID and version/build number;
- produced `.ipa`;
- upload result and App Store Connect processing status;
- test account requirements and tested login flow;
- remaining warnings that could affect App Review.

## Product Owner Manual Checklist

Only the product owner should complete account decisions, legal declarations,
2FA, and final submission. Use this checklist in order.

### Gate A: Confirm Apple Account State

- [ ] Open Apple Developer and confirm the membership is active.
- [ ] In App Store Connect, open **Business** and accept any pending agreements.
- [ ] Confirm you have Account Holder or Admin access for identifiers/API keys,
      and App Manager access for the app record.
- [ ] Do not create certificates or profiles yet if the unsigned CI build has
      not passed.

### Gate B: Confirm the Real Bundle ID

In Apple Developer:

1. Open **Certificates, Identifiers & Profiles**.
2. Open **Identifiers**.
3. Find the explicit App ID intended for Facteur.
4. Copy the bundle ID exactly.
5. Confirm whether **Sign in with Apple** and **Push Notifications** are
   enabled for that App ID.

In App Store Connect:

1. Open **Apps** and select Facteur, or create **New App** if it does not exist.
2. Confirm the selected bundle ID is the same exact value.
3. Record the SKU if creating the app; it is internal and cannot be changed
   later.

Send the agent only:

```text
Confirmed Facteur bundle ID: <exact value>
App Store Connect app record exists: yes/no
Sign in with Apple enabled: yes/no
Push Notifications enabled: yes/no
```

Do not send account passwords, private keys, recovery codes, or 2FA codes.

### Gate C: Connect Apple to Codemagic

Do this only after the agent reports a successful unsigned `ios-release`
build.

1. In App Store Connect, open **Users and Access > Integrations**.
2. If API access is not enabled, the Account Holder must request/enable it.
3. Create a team API key with the minimum role needed for upload.
4. Download the `.p8` key immediately and store it in a password manager or
   secure vault; Apple does not offer repeated downloads.
5. In Codemagic, open the team settings/integrations area and add the App Store
   Connect API key using its name, issuer ID, key ID, and private key.
6. Use Codemagic's signing-certificate/provisioning-profile management or
   automatic signing flow for the confirmed bundle ID.
7. Never paste credentials into `codemagic.yaml`, GitHub, an issue, or chat.

Tell the agent:

```text
Codemagic Apple integration name: <name only, no secret>
Signing assets available for bundle ID: yes/no
```

### Gate D: Start the Correct Codemagic Build

In Codemagic:

1. Click **Start new build**.
2. Select the release branch supplied by the agent.
3. Select the YAML workflow **iOS Release** / `ios-release`.
4. Verify the screen says it is using `codemagic.yaml`.
5. Start the build.

Stop immediately if the log shows Android tasks such as `bundleDebug`,
`assembleDebug`, or `Failed to build for Android`. That means the wrong
workflow was selected.

Send the agent the build URL and the first failing step, or confirmation that
the build succeeded. Do not manually edit random build settings to chase an
error; the YAML should remain the source of truth.

### Gate E: TestFlight Validation

After upload:

- [ ] Wait for Apple processing; the build will not appear immediately.
- [ ] Open **App Store Connect > Facteur > TestFlight**.
- [ ] Resolve export compliance prompts.
- [ ] Add internal testers first.
- [ ] Install on a real iPhone.
- [ ] Test account creation, email confirmation, login/logout, Apple/Google
      login if offered, onboarding, feed, article opening, saves, notes,
      notifications, purchases/paywall, account deletion, and privacy links.
- [ ] Record crashes, broken links, placeholder content, and permission prompts.
- [ ] Increment the build number before every replacement upload.

### Gate F: App Store Submission Content

Complete and review:

- [ ] App name, subtitle, description, promotional text, and keywords.
- [ ] Primary/secondary categories.
- [ ] Support URL, marketing URL if used, and a public privacy-policy URL.
- [ ] Required iPhone/iPad screenshots matching supported devices.
- [ ] Age rating questionnaire.
- [ ] App Privacy/data collection answers based on actual Supabase, PostHog,
      Sentry, RevenueCat, authentication, and notification behavior.
- [ ] Encryption/export-compliance answers.
- [ ] Content-rights declaration for aggregated news/content.
- [ ] Review notes explaining the product and any non-obvious flows.
- [ ] A working review account if login is required, with credentials that do
      not expire during review.
- [ ] Account-deletion instructions if users can create accounts.
- [ ] In-app purchase/subscription products and RevenueCat configuration, if
      monetization is enabled in the submitted build.
- [ ] Correct build selected for version `1.0.0` or the final chosen version.

Only the product owner should click **Submit for Review** after the TestFlight
checklist passes and all declarations have been reviewed.

## Stop Conditions

An agent must stop and ask the product owner before:

- choosing or changing the production bundle ID;
- enabling/disabling Apple capabilities;
- creating/revoking API keys, certificates, or profiles;
- changing the Apple development team;
- accepting legal agreements;
- answering App Privacy, export, content-rights, or age-rating declarations;
- inviting external testers;
- submitting the app for review or releasing it.

## Useful Official References

- Codemagic YAML setup:
  https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/
- Codemagic iOS signing:
  https://docs.codemagic.io/yaml-code-signing/signing-ios/
- Codemagic App Store Connect publishing:
  https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Apple: register an App ID:
  https://developer.apple.com/help/account/identifiers/register-an-app-id/
- Apple: add an App Store Connect app:
  https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Apple: upload builds:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

## Progress Log

Update this section after each gate so the next agent never has to reconstruct
the release from chat history again.

| Date | Gate | Evidence/result | Owner |
|---|---|---|---|
| 2026-06-08 | Context recovery | Historical sessions recovered; current checkout re-audited; unsigned pipeline still blocked | Agent |
