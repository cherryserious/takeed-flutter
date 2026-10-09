import 'package:flutter/services.dart';

/// The native side: APNs/FCM tokens, permission, device details, and events
/// (clicks, foreground notifications, token refresh).
class TakeedNative {
  TakeedNative([MethodChannel? channel]) : channel = channel ?? const MethodChannel('takeed');

  final MethodChannel channel;

  /// {type: android|ios, token, config_identifier, apns_sandbox}
  Future<Map<String, dynamic>?> pushToken() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>('pushToken');
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<bool> requestPermission() async => await channel.invokeMethod<bool>('requestPermission') ?? false;

  Future<bool> permission() async => await channel.invokeMethod<bool>('permission') ?? false;

  /// {device_model, os_version, app_version, language, timezone}
  Future<Map<String, dynamic>> deviceInfo() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>('deviceInfo');
    return result == null ? {} : Map<String, dynamic>.from(result);
  }

  /// Saves the App ID and API URL for native code that runs without Flutter (background messages, clicks).
  Future<void> configure(String appId, String apiUrl) =>
      channel.invokeMethod('configure', {'app_id': appId, 'api_url': apiUrl});

  /// The notification that launched the app, if any.
  Future<Map<String, dynamic>?> initialClick() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>('initialClick');
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  Future<void> displayForeground(String notificationId, bool show) =>
      channel.invokeMethod('displayForeground', {'notification_id': notificationId, 'show': show});

  void setHandler(Future<dynamic> Function(MethodCall call) handler) => channel.setMethodCallHandler(handler);
}
