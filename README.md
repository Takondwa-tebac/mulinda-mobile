# mulinda_mobile

Mulinda Personal Financial Assistant

## Apple app build (iOS)

The iOS project lives in `ios/`. It can only be built on a Mac with Xcode (or a
cloud builder such as Codemagic); the Dart code can still be edited and
analysed on Windows. Bundle ID: `tech.lyncsystems.mulinda` (same as Android).

### What works differently on iOS

iOS apps cannot read or listen for SMS, so automatic SMS capture is
Android-only (`SmsCapability.canReadSms`). On iOS the capture sheet offers
receipt scan, manual entry and **Paste SMS**, which has a "Paste from
clipboard" button. Bulk import, inbox scan, background SMS sync and the SMS
permission card are hidden. Everything is still propose-then-approve.

### One-time setup (before the first build)

1. **Firebase**: add an iOS app with bundle ID `tech.lyncsystems.mulinda` in the
   Firebase console, download `GoogleService-Info.plist` and add it to
   `ios/Runner` through Xcode (tick "Copy items if needed" and the Runner
   target). Firebase starts from this file on iOS, so `firebase_options.dart`
   needs no iOS entry.
2. **Google sign-in**: open `ios/Runner/Info.plist` and replace
   `com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID` with the
   `REVERSED_CLIENT_ID` value from `GoogleService-Info.plist`. Google sign-in
   fails until this is done.
3. **Apple Developer account** (paid program): register the App ID
   `tech.lyncsystems.mulinda` and enable the **Push Notifications** and
   **Sign in with Apple** capabilities. The entitlements are already in
   `ios/Runner/Runner.entitlements`.
4. **Push notifications**: create an APNs Auth Key (`.p8`) under Keys in the
   Apple Developer account and upload it in Firebase console > Project
   settings > Cloud Messaging > Apple app configuration.
5. **Signing**: open `ios/Runner.xcworkspace` in Xcode, select the Runner
   target > Signing & Capabilities, choose your Team and leave "Automatically
   manage signing" on. Check that Push Notifications and Sign in with Apple
   both appear.
6. **Backend (mulinda-api)**: set these in `.env` and run `php artisan migrate`:
   - `APPLE_CLIENT_ID=tech.lyncsystems.mulinda`
   - `APPLE_TEAM_ID`: your 10-character Apple Team ID
   - `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY_PATH`: create a **Sign in with
     Apple** key (`.p8`) under Keys in the Apple Developer account, then put
     the file on the server (outside `public/`, path relative to the project
     root) and point the variable at it.

   `APPLE_CLIENT_ID` is enough for sign-in itself. The team ID and key are
   needed to **revoke the Apple token when a user deletes their account**,
   which App Review requires for apps that offer Sign in with Apple. Without
   them, account deletion still works but the Apple link stays on the user's
   Apple ID.

### Build and run

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run                 # on a simulator or a connected iPhone
flutter build ipa           # App Store / TestFlight archive
```

`ios/Podfile` enables only the `permission_handler` permissions the app uses
(camera, photos, notifications). Do not add the SMS permission: iOS has none,
and App Review rejects unused permission code.

### Before App Store submission

- Add the privacy policy URL and fill in the App Privacy ("nutrition label")
  answers to match the policy.
- Test Sign in with Apple, including account deletion, on a real device.
- Push notifications and Sign in with Apple do not work on the simulator in
  every case; use a real iPhone to confirm both.
- The Chichewa strings added for iOS (`sms.copyHint`, `sms.pasteClipboard`,
  `sms.clipboardEmpty`, `auth.continueWithApple`, `auth.appleUnavailable`)
  should be reviewed by a Chichewa speaker.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
