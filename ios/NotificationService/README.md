# Notification Service Extension (iOS push pictures)

Story pushes carry a cover picture. Android shows it from FCM
`notification.image` with no app code. On iOS the API sends the picture (an
animated GIF) in `apns.fcm_options.image` with `mutable-content: 1`, and iOS
only shows it if the app has a Notification Service Extension that downloads
and attaches it. That extension is the code in this folder.

The Xcode target is **not** in `Runner.xcodeproj` yet: the project file cannot
be edited safely or built on Windows. Add it on a Mac with the steps below.
The extension uses no pods, so the Podfile does not change.

## Files

- `NotificationService.swift`: downloads `fcm_options.image` (HTTPS only),
  attaches it, and falls back to the plain push on any error or timeout.
- `Info.plist`: the extension's plist (service extension point, principal
  class `$(PRODUCT_MODULE_NAME).NotificationService`, version from Flutter).

## Add the target in Xcode (on a Mac)

1. Run `flutter pub get`, then `cd ios && pod install`, then open
   `ios/Runner.xcworkspace` in Xcode.
2. File > New > Target... > iOS > **Notification Service Extension** > Next.
3. Product Name: `NotificationService`. Team: the same team as Runner.
   Language: Swift. Embed in Application: **Runner**. Finish. If Xcode offers
   to activate the new scheme, choose **Cancel** (keep building Runner).
4. Xcode generates its own `NotificationService.swift` and `Info.plist` in
   this folder, overwriting the ones from git. Restore ours with
   `git checkout -- ios/NotificationService/NotificationService.swift ios/NotificationService/Info.plist`.
   In the Project navigator, make sure `NotificationService.swift` belongs
   only to the `NotificationService` target, and that `Info.plist` and this
   README belong to no target.
5. Select the `NotificationService` target > Build Settings:
   - Info.plist File: `NotificationService/Info.plist`
   - Product Bundle Identifier: `tech.lyncsystems.mulinda.NotificationService`
   - iOS Deployment Target: `15.5` (same as Runner)
   - Swift Language Version: same as Runner
6. Signing & Capabilities for the extension: automatic signing with the
   Runner team. It needs no capabilities of its own. UserNotifications is
   linked automatically.
7. Version numbers: the plist reads `$(FLUTTER_BUILD_NAME)` and
   `$(FLUTTER_BUILD_NUMBER)`. Project > Info > Configurations: for Debug,
   Release and Profile, set the `NotificationService` row to the same
   `Flutter/Debug.xcconfig` or `Flutter/Release.xcconfig` the Runner row uses,
   so the extension version always matches the app (App Store Connect rejects
   a mismatch).
8. Avoid the "Cycle inside Runner" build error: Runner target > Build Phases,
   drag **Embed Foundation Extensions** (called Embed App Extensions in older
   Xcode) above **Run Script** and **Thin Binary**.
9. Build and run on a real iPhone (the simulator does not receive FCM pushes),
   then commit `ios/Runner.xcodeproj/project.pbxproj` with the new target.

## How to check it worked

- Send a test push with `apns.fcm_options.image` set to
  `https://<api-host>/images/stories/month-cover.gif` and
  `apns.payload.aps.mutable-content` set to 1, or run
  `php artisan stories:send-notifications` on a test server on a day a push is
  due.
- On the iPhone the push shows a thumbnail; long-press or pull it down and the
  cover animates.
- Tapping it opens the story (handled in Dart by `NotificationRouter`, not by
  this extension).
- A push without a picture, or with a broken URL, still arrives as plain text.
