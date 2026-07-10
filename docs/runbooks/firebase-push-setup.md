# Firebase push setup

## Backend

Create one Firebase project per environment and set either
`FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_BASE64` on the API.
The service account needs Firebase Cloud Messaging send access.

## Android

Place the matching files at:

- `apps/mobile/android/app/src/prod/google-services.json`
- `apps/mobile/android/app/src/staging/google-services.json`

The Gradle plugin is applied only when at least one configuration file exists,
so local builds without Firebase credentials remain usable.

## iOS

Add each environment's `GoogleService-Info.plist` to the corresponding Xcode
scheme/configuration and ensure it is copied into the Runner bundle as
`GoogleService-Info.plist`.

In Firebase Console, upload the APNs authentication key for each iOS app.
The Runner target already includes the `aps-environment` entitlement.
