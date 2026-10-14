# takeed

Push notifications for Flutter apps, delivered by [Takeed](https://takeed-iq.com).

- **Android** through Firebase Cloud Messaging, **iOS** through Apple (APNs) directly.
- Images, up to three action buttons, deep links and your own data, on both.
- **No `google-services.json` in your app.** You upload it once in the Takeed dashboard; the SDK
  gets the Firebase settings from Takeed and starts Firebase itself.
- Delivery and open tracking, users, tags and branches, sent from the dashboard or your backend.
- Same calls as `onesignal_flutter` v5, under `Takeed`: moving an app over is mostly a rename.

Notifications are free and unlimited on Takeed.

---

## Contents

1. [Requirements](#requirements)
2. [Set up the dashboard](#1-set-up-the-dashboard)
3. [Install](#2-install)
4. [Android](#3-android)
5. [iOS](#4-ios)
6. [Start the SDK](#5-start-the-sdk)
7. [Permission](#permission)
8. [Users](#users)
9. [Tags and user details](#tags-and-user-details)
10. [Handling notifications](#handling-notifications)
11. [Subscription state](#subscription-state)
12. [Branches](#branches)
13. [Sending notifications](#sending-notifications)
14. [Troubleshooting](#troubleshooting)
15. [Coming from OneSignal](#coming-from-onesignal)
16. [API reference](#api-reference)

---

## Requirements

| | Minimum |
|---|---|
| Flutter | 3.22 (Dart 3.4) |
| Android | 5.0, API 21 |
| iOS | 12.0 |

## 1. Set up the dashboard

Sign in at [takeed-iq.com](https://takeed-iq.com), open your app, and go to the **Push** tab →
**Firebase & Apple keys** → **Add key**.

**Android: two files from the same Firebase project**

| File | Where in the Firebase console | Secret? |
|---|---|---|
| Service account JSON | Project settings → **Service accounts** → *Generate new private key* | Yes: stored encrypted, never shown again |
| `google-services.json` | Project settings → **Your apps** → your Android app → *google-services.json* | No |

Add every Android app (package name) that should receive notifications to that Firebase project
first, then download `google-services.json`, so it lists them all.

**iOS: the APNs key from Apple**

In [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) → Keys, create a key
with **Apple Push Notifications service (APNs)**, download the `.p8` file, and enter it with its
**Key ID**, your **Team ID**, and the app's **Bundle ID**.

Then copy the app's **App ID** from the top of the app page. That's all the SDK needs.

## 2. Install

```yaml
dependencies:
  takeed: ^2.1.0
```

```bash
flutter pub get
```

## 3. Android

Nothing to add. Specifically, you **don't** need:

- `google-services.json` in `android/app`,
- the `com.google.gms.google-services` Gradle plugin,
- `firebase_core` or `firebase_messaging` in `pubspec.yaml`.

If your app already uses Firebase for something else with its own `google-services.json`, keep it:
Takeed's Firebase runs alongside it.

**Notification icon (recommended).** Android shows a small monochrome icon in the status bar. Add a
white-on-transparent drawable named `ic_stat_notification` (for example
`android/app/src/main/res/drawable/ic_stat_notification.png`) and Takeed uses it. Without one, the app
icon is used, which Android may show as a plain square.

## 4. iOS

1. In Xcode, open `ios/Runner.xcworkspace` → Runner target → **Signing & Capabilities** →
   **+ Capability** → **Push Notifications**.
2. For images, action buttons and delivery receipts, add a Notification Service Extension:
   **File → New → Target → Notification Service Extension**, name it e.g. `NotificationService`, and
   replace its `NotificationService.swift` with
   [`extension/NotificationService.swift`](extension/NotificationService.swift) from this package.
   No App Group is needed.
3. Run `cd ios && pod install`.

Debug builds (development provisioning profile) automatically use Apple's sandbox; release builds use
production. Nothing to configure.

## 5. Start the SDK

Call `initialize` once, as early as possible:

```dart
import 'package:flutter/material.dart';
import 'package:takeed/takeed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Takeed.initialize('YOUR-APP-ID');
  runApp(const MyApp());
}
```

`initialize` registers the device with Takeed. On Android it first fetches the Firebase settings from
Takeed and starts Firebase. Everything goes to `https://takeed-iq.com`; the SDK talks to nothing else.

The device is registered even before the user allows notifications, so it can be messaged as soon as
they do.

## Permission

Android 13+ and iOS need the user's permission to show notifications. Ask at a moment that makes
sense in your app, not necessarily on first launch:

```dart
final granted = await Takeed.Notifications.requestPermission(true);
```

Pass `true` to send the user to the system settings when they denied it before and the system won't
ask again. Check without asking:

```dart
Takeed.Notifications.permission;          // whether notifications are allowed
await Takeed.Notifications.canRequest();   // true while they aren't allowed yet

Takeed.Notifications.addPermissionObserver((granted) {
  // the user changed it, here or in system settings
});
```

## Users

Devices start anonymous. After your own sign-in, link the device to your user ID, so your backend
can send to that user on all their devices:

```dart
await Takeed.login(user.id);   // after the user signs in
await Takeed.logout();         // when they sign out
```

`login` can be called before `initialize` finishes; it's sent with the registration.

**Identity verification.** Turn it on in the app's **Security** tab so nobody can claim someone
else's ID. Your backend computes `HMAC-SHA256(userId, identitySecret)` as hex, and the app passes it:

```dart
await Takeed.login(user.id, identityHash: hashFromYourBackend);
```

Never put the identity secret in the app.

## Tags and user details

Tags are key/value pairs you can target with filters when sending:

```dart
await Takeed.User.addTag('plan', 'gold');
await Takeed.User.addTags({'city': 'Basra', 'orders': 12});
await Takeed.User.removeTag('plan');
await Takeed.User.removeTags(['city', 'orders']);
```

Other details, all optional:

```dart
await Takeed.User.setLanguage('ar');              // picks the Arabic text of a notification
await Takeed.User.setPhone('+9647701234567');      // E.164
await Takeed.User.setEmail('user@example.com');
await Takeed.User.setLocation(30.508, 47.783);     // only if your app already has location permission
```

The device's language and timezone are sent automatically; `setLanguage` overrides the language.

## Handling notifications

**Taps and buttons.** Called when the user opens a notification or presses one of its buttons,
including when that tap launched the app:

```dart
Takeed.Notifications.addClickListener((event) {
  final n = event.notification;
  final data = n.additionalData;        // the "data" you sent, e.g. {'order_id': '7'}
  final button = event.result.actionId; // the pressed button's id, or null for the notification itself
  final url = event.result.url;         // its URL, if any

  if (data?['order_id'] != null) navigator.pushNamed('/orders/${data!['order_id']}');
});
```

Register click listeners early (right after `initialize`), so the tap that opened the app isn't missed.

**While the app is open.** By default the notification is shown. To decide yourself:

```dart
Takeed.Notifications.addForegroundWillDisplayListener((event) {
  if (isOnChatScreen) {
    event.preventDefault(); // don't show it; update the screen instead
  } else {
    event.display();
  }
});
```

`event.notification` has `notificationId`, `title`, `body`, `launchUrl`, `additionalData`, `buttons`
and `rawPayload`.

Delivery ("received") and opens ("clicked") are reported to Takeed automatically, so the dashboard's
reports show them.

## Subscription state

```dart
final sub = Takeed.User.pushSubscription;
sub.id;       // the device's ID in Takeed (null until registered)
sub.optedIn;  // registered, permission granted, and not opted out

await sub.optOut(); // stop notifications for this device without removing the permission
await sub.optIn();  // undo; asks for permission if needed

sub.addObserver((state) {
  print('${state.previous.optedIn} → ${state.current.optedIn}, id ${state.current.id}');
});
```

`await Takeed.User.getOnesignalId()` returns the Takeed user ID (named like OneSignal's for easy
migration); `getExternalId()` returns the ID passed to `login`.

## Branches

If your app serves several companies or locations (branches in the dashboard), tie the device to one:

```dart
await Takeed.initialize('YOUR-APP-ID', branch: 'north');
```

Notifications sent to that branch then reach it. A branch can have its own Firebase project in the
dashboard; the SDK picks the branch's settings automatically.

## Sending notifications

From the dashboard (the app's **Push** page), or from your backend with an API key:

```bash
curl https://takeed-iq.com/api/v1/notifications \
  -H "Authorization: Key $TAKEED_KEY" -H "Content-Type: application/json" \
  -d '{
    "app_id": "YOUR-APP-ID",
    "include_aliases": {"external_id": ["user-42"]},
    "headings": {"en": "Order shipped", "ar": "تم شحن الطلب"},
    "contents": {"en": "Arrives tomorrow", "ar": "يصل غداً"},
    "data": {"order_id": "7"},
    "buttons": [{"id": "track", "text": "Track"}],
    "big_picture": "https://cdn.example.com/box.jpg"
  }'
```

Full reference: [Sending notifications](https://takeed-iq.com/docs/notifications) and the
[API reference](https://takeed-iq.com/docs/api).

## Troubleshooting

The SDK reports problems with `debugPrint`, prefixed `Takeed:`. Run the app in debug and watch the log.

| Message or symptom | Cause and fix |
|---|---|
| `no Firebase settings for com.your.app` | The dashboard has no `google-services.json` listing this package. Add the Android app to the Firebase project, download `google-services.json` again, and upload it on the key (**Replace google-services.json**). |
| `could not get Firebase settings` | Takeed couldn't be reached. The settings saved last time are used; on a first launch without internet, it tries again on the next start. |
| `no push token` | Firebase couldn't start or give a token: usually the settings above, or Google Play services missing on the device. |
| `registration failed … unknown_platform_config` | The device's Firebase project or iOS Bundle ID matches no key in the app (or its branch). Add the key in the dashboard. |
| `registration failed … app_not_found` | The App ID passed to `initialize` is wrong. |
| Registered, but nothing arrives on Android | The service account and `google-services.json` must be from the same Firebase project (the dashboard checks this). See the delivery's error on the app's **Push** page. |
| Nothing arrives on iOS | The Push Notifications capability is missing, or the `.p8` key, Key ID, Team ID or Bundle ID don't match the app. |
| No image or buttons on iOS | The Notification Service Extension is missing or still has Xcode's default file. |
| Square icon on Android | Add `ic_stat_notification` (see [Android](#3-android)). |

## Coming from OneSignal

| OneSignal | Takeed |
|---|---|
| `onesignal_flutter: ^5.x` | `takeed: ^2.1.0` |
| `OneSignal.initialize(appId)` | `await Takeed.initialize(appId)` |
| `OneSignal.login(id)` / `logout()` | `Takeed.login(id)` / `logout()` |
| `OneSignal.Notifications.*` | `Takeed.Notifications.*` |
| `OneSignal.User.*` | `Takeed.User.*` |
| `OneSignal.User.pushSubscription.*` | `Takeed.User.pushSubscription.*` |
| `OSNotificationClickEvent`, `OSNotification` | `TakeedNotificationClickEvent`, `TakeedNotification` |

Also remove `google-services.json` and the Google services plugin if they were only there for
OneSignal, and replace the iOS extension's file. Devices exported from OneSignal can be imported in
the dashboard and keep receiving notifications until users update.

## API reference

**`Takeed`**

| Member | |
|---|---|
| `initialize(appId, {branch})` | Start the SDK and register the device. |
| `login(externalId, {identityHash})` | Link the device to your user. |
| `logout()` | Unlink it. |
| `Notifications` | Permission and listeners, below. |
| `User` | Tags, details and the push subscription, below. |

**`Takeed.Notifications`**

| Member | |
|---|---|
| `permission` | Whether notifications are allowed. |
| `requestPermission(fallbackToSettings)` | Ask; returns whether granted. |
| `canRequest()` | True while notifications aren't allowed yet. |
| `addClickListener` / `removeClickListener` | Taps and button presses. |
| `addForegroundWillDisplayListener` / `removeForegroundWillDisplayListener` | Notifications that arrive while the app is open. |
| `addPermissionObserver` / `removePermissionObserver` | Permission changes. |

**`Takeed.User`**

| Member | |
|---|---|
| `addTag`, `addTags`, `removeTag`, `removeTags` | Tags. `addTagWithKey` is the OneSignal name. |
| `setLanguage`, `setEmail`, `setPhone`, `setLocation` | Details. `addEmail` / `addSms` are the OneSignal names. |
| `getOnesignalId()`, `getExternalId()` | The Takeed user ID; the ID given to `login`. |
| `pushSubscription` | `id`, `token`, `optedIn`, `optIn()`, `optOut()`, `addObserver`, `removeObserver`. |

## License

MIT. The SDK is open source; the Takeed service it connects to is not.
