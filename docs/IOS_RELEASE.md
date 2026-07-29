# NutriFlow iOS Release

This project is prepared for an internal TestFlight build. A public App Store
release still requires the security and privacy work listed below.

## Current identifiers

- App name: `NutriFlow`
- Bundle ID: `dev.sunnxz.nutriflow`
- Version: `1.0.0`
- Build: `1`
- API: `https://nutriflow.sunnxz.dev/api/v1`
- Minimum iOS version: `13.0`

The staging invitation code is intentionally not stored in Git.

## 1. Required accounts and hardware

You need:

- A Mac capable of running a currently supported Xcode release
- A physical iPhone for camera, photo-library, microphone, and speech tests
- An active Apple Developer Program membership
- Access to App Store Connect

Individual students do not qualify for Apple's organization-only fee waiver.

## 2. Prepare the Mac

Install the current stable Xcode and Flutter SDK, then run:

```bash
sudo xcodebuild -runFirstLaunch
flutter doctor -v
cd nutri-mobile
flutter pub get
```

Resolve every red item reported by `flutter doctor` before building.

## 3. Configure signing

1. Sign in to Xcode with the Apple Account enrolled in the Developer Program.
2. Open `nutri-mobile/ios/Runner.xcworkspace`.
3. Select the `Runner` target, then **Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Choose your personal developer Team.
6. Confirm the Bundle Identifier is `dev.sunnxz.nutriflow`.

Create the matching app record in App Store Connect before uploading the first
build. The Bundle ID in App Store Connect must match the Xcode project.

## 4. Build an internal TestFlight IPA

From `nutri-mobile` on the Mac:

```bash
flutter clean
flutter pub get
flutter build ipa --release \
  --dart-define=NUTRI_API_BASE=https://nutriflow.sunnxz.dev/api/v1 \
  --dart-define=NUTRI_DEMO_ACCESS_CODE=YOUR_STAGING_ACCESS_CODE
```

Outputs:

- Xcode archive: `build/ios/archive/Runner.xcarchive`
- IPA: `build/ios/ipa/`

The staging code is compiled into this test build. Do not use this mechanism
for a public App Store binary.

## 5. Device smoke test

Before uploading, install a release build on a physical iPhone and verify:

1. First launch and onboarding
2. Phone-code test login
3. Camera permission and capture
4. Photo-library permission and selection
5. Microphone and speech-recognition permission
6. Meal upload reaches `COMPLETED`
7. Result image, calories, advice, history, and profile load correctly
8. Airplane-mode and server-error states are understandable
9. No clipped text on the smallest supported iPhone

## 6. Upload and enable TestFlight

Open the archive in Xcode Organizer:

1. Select **Distribute App**
2. Choose **App Store Connect**
3. Choose **Upload**
4. Keep automatic signing and symbol upload enabled
5. Resolve validation errors, then upload

After Apple finishes processing the build, add it to an Internal Testing group
in App Store Connect. Increment the build number for every subsequent upload:

```yaml
version: 1.0.0+2
```

## 7. Required before public release

Do not submit the current staging build for public App Review until all of these
are complete:

- Replace client-supplied user IDs with signed access and refresh tokens
- Connect a real SMS or email verification provider and disable debug OTPs
- Add per-IP and per-account rate limits for login, upload, and task polling
- Add in-app account deletion that removes associated photos and records
- Publish a privacy policy and link it inside the app
- Publish a support page and a user-data deletion/contact channel
- Complete App Privacy declarations for phone number, photos, health profile,
  identifiers, and diagnostics actually collected
- Add a clear statement that calorie estimates are informational, not medical
  advice
- Move the backend to a server that remains online after the current cloud
  credit expires
- Prepare one to ten App Store screenshots without transparency

## 8. App Store metadata draft

- Name: `NutriFlow`
- Subtitle: `拍照记录餐食与营养建议`
- Primary category: `Health & Fitness`
- Secondary category: `Food & Drink`
- SKU suggestion: `NUTRIFLOW-IOS-001`
- Support URL: `https://sunnxz.dev/support`
- Privacy URL: `https://sunnxz.dev/privacy`

Official references:

- https://docs.flutter.dev/deployment/ios
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
