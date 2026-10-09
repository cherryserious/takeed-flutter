# takeed

Push notifications for Flutter apps on [Takeed](https://takeed-iq.com).
Android goes through Firebase Cloud Messaging and iOS through APNs directly, with images and
action buttons on both.

The API mirrors `onesignal_flutter` v5: the same calls, under `Takeed` instead of `OneSignal`.
Moving an app over is mostly a rename.

## Install

```yaml
dependencies:
  takeed: ^2.0.0
```

## Before you start

In the [Takeed dashboard](https://takeed-iq.com), open your app → **Push** tab → **Firebase & Apple keys** → **Add key**:

- **Android:** the Firebase service account JSON (Firebase console → Project settings → Service
  accounts → Generate new private key). Keep your app's `google-services.json` and the
  `com.google.gms.google-services` Gradle plugin as usual.
- **iOS:** the `.p8` key from Apple (Certificates, IDs & Profiles → Keys → APNs) with its Key ID,
  your Team ID and the app's Bundle ID. Turn on the **Push Notifications** capability in Xcode.

Copy the app's **App ID** from the dashboard.

## Start

```dart
import 'package:flutter/material.dart';
import 'package:takeed/takeed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Takeed.initialize('YOUR-APP-ID');
  runApp(const MyApp());
}
```

`initialize` registers the device with Takeed (`https://takeed-iq.com`; the SDK talks to nothing else). Pass `branch: 'north'` to tie it to one of the app's branches,
so notifications sent to that branch reach it.

## Permission, users and tags

```dart
await Takeed.Notifications.requestPermission(true);

// After your own sign-in, link the device to your user ID.
await Takeed.login(user.id);
await Takeed.logout();

await Takeed.User.addTagWithKey('plan', 'gold');
await Takeed.User.removeTag('plan');
await Takeed.User.setLanguage('ar');
```

With identity verification on for the app, pass the HMAC-SHA256 of the user ID, made by your
backend with the app's identity secret: `Takeed.login(user.id, identityHash: hash)`. It stops
anyone from claiming someone else's ID.

## Opened and received notifications

```dart
Takeed.Notifications.addClickListener((event) {
  final data = event.notification.additionalData; // the "data" you sent
  final button = event.result.actionId;           // button id, or null for the notification itself
});

// While the app is open: show it, or call preventDefault() to handle it yourself.
Takeed.Notifications.addForegroundWillDisplayListener((event) => event.display());

Takeed.User.pushSubscription.addObserver((state) {
  print('Device ID: ${state.current.id}');
});
```

## iOS images, buttons and receipts

Images, action buttons and delivery receipts on iOS need a Notification Service Extension:

1. In Xcode: **File → New → Target → Notification Service Extension**.
2. Replace its `NotificationService.swift` with
   [`extension/NotificationService.swift`](extension/NotificationService.swift) from this package.
3. Remove any OneSignal pod from the extension target. No App Group is needed.

## Coming from OneSignal

| OneSignal | Takeed |
|---|---|
| `OneSignal.initialize(appId)` | `await Takeed.initialize(appId)` |
| `OneSignal.login(id)` | `Takeed.login(id)` |
| `OneSignal.Notifications.*` | `Takeed.Notifications.*` |
| `OneSignal.User.*` | `Takeed.User.*` |

Devices exported from OneSignal can be imported in the dashboard and keep receiving pushes until
users update to the version with this package.

## License

MIT. The SDK is open source; the Takeed service it connects to is not.
