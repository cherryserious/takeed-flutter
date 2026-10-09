/// Takeed push notifications.
///
/// Same shape as `onesignal_flutter` v5, so migrating is mostly renaming
/// `OneSignal` to `Takeed`:
///
/// ```dart
/// await Takeed.initialize('YOUR-APP-ID', apiUrl: 'https://takeed.example.com');
/// await Takeed.Notifications.requestPermission(true);
/// await Takeed.login('user-42');
/// Takeed.User.addTagWithKey('plan', 'gold');
/// Takeed.Notifications.addClickListener((event) => print(event.notification.additionalData));
/// ```
library;

export 'src/models.dart';
export 'src/takeed_base.dart' show Takeed, TakeedUser, TakeedNotifications, TakeedPushSubscription;
