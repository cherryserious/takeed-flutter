/// A notification as the app sees it.
class TakeedNotification {
  TakeedNotification({
    required this.notificationId,
    this.title,
    this.body,
    this.launchUrl,
    this.additionalData,
    this.buttons = const [],
    this.rawPayload = const {},
  });

  final String notificationId;
  final String? title;
  final String? body;
  final String? launchUrl;
  final Map<String, dynamic>? additionalData;
  final List<TakeedActionButton> buttons;
  final Map<String, dynamic> rawPayload;

  factory TakeedNotification.fromMap(Map<dynamic, dynamic> map) {
    final data = map['data'];
    final buttons = map['buttons'];
    return TakeedNotification(
      notificationId: (map['notification_id'] ?? '').toString(),
      title: map['title']?.toString(),
      body: map['body']?.toString(),
      launchUrl: map['url']?.toString(),
      additionalData: data is Map ? Map<String, dynamic>.from(data) : null,
      buttons: buttons is List
          ? buttons
              .whereType<Map>()
              .map((b) =>
                  TakeedActionButton(id: b['id'].toString(), text: b['text'].toString(), url: b['url']?.toString()))
              .toList()
          : const [],
      rawPayload: Map<String, dynamic>.from(map),
    );
  }
}

class TakeedActionButton {
  const TakeedActionButton({required this.id, required this.text, this.url});
  final String id;
  final String text;
  final String? url;
}

/// Passed to click listeners. [result.actionId] is the button id, or null for a tap on the notification.
class TakeedNotificationClickEvent {
  TakeedNotificationClickEvent(this.notification, this.result);
  final TakeedNotification notification;
  final TakeedNotificationClickResult result;
}

class TakeedNotificationClickResult {
  TakeedNotificationClickResult({this.actionId, this.url});
  final String? actionId;
  final String? url;
}

/// Passed to foreground listeners. Call [preventDefault] to not show it; [display] to show it later.
class TakeedNotificationWillDisplayEvent {
  TakeedNotificationWillDisplayEvent(this.notification, this._display);
  final TakeedNotification notification;
  final void Function(bool show) _display;
  bool _handled = false;

  void preventDefault() {
    _handled = true;
    _display(false);
  }

  void display() {
    _handled = true;
    _display(true);
  }

  bool get handled => _handled;
}

class TakeedPushSubscriptionState {
  const TakeedPushSubscriptionState({this.id, this.token, this.optedIn = false});
  final String? id;
  final String? token;
  final bool optedIn;
}

class TakeedPushSubscriptionChangedState {
  const TakeedPushSubscriptionChangedState(this.previous, this.current);
  final TakeedPushSubscriptionState previous;
  final TakeedPushSubscriptionState current;
}
