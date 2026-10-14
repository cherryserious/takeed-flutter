import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'native.dart';

const _sdkVersion = 'takeed-flutter/2.1.0';
const _sessionGap = Duration(minutes: 30);

class _Keys {
  static const subscriptionId = 'takeed.subscription_id';
  static const userId = 'takeed.user_id';
  static const externalId = 'takeed.external_id';
  static const identityHash = 'takeed.identity_hash';
  static const optedOut = 'takeed.opted_out';
  static const token = 'takeed.token';
  static const lastSession = 'takeed.last_session';
}

/// Entry point. Mirrors `OneSignal` from onesignal_flutter v5.
class Takeed {
  Takeed._();

  // Capitalized like onesignal_flutter (OneSignal.User, OneSignal.Notifications).
  // ignore: non_constant_identifier_names
  static final TakeedUser User = TakeedUser._();
  // ignore: non_constant_identifier_names
  static final TakeedNotifications Notifications = TakeedNotifications._();

  static TakeedApi? _api;
  static TakeedNative _native = TakeedNative();
  static SharedPreferences? _prefs;
  static Completer<void> _ready = Completer<void>();
  static String? _branch;

  /// The Takeed service. Fixed: the SDK talks to nothing else.
  static const apiUrl = 'https://takeed-iq.com';

  /// Set up the SDK and register this device. Call once, early in `main()`.
  ///
  /// [branch] optionally ties this device to an app branch (its slug), so
  /// branch-targeted notifications reach it.
  static Future<void> initialize(String appId, {String? branch}) async {
    if (_ready.isCompleted) return;
    _api ??= TakeedApi(baseUrl: apiUrl, appId: appId);
    _branch = branch;
    _prefs = await SharedPreferences.getInstance();
    _native.setHandler(_onNativeCall);
    await _native.configure(appId);
    _ready.complete();

    await _register();
    await _pingSession();

    final initial = await _native.initialClick();
    if (initial != null) Notifications._dispatchClick(initial);
  }

  /// Link this device to your user. With identity verification on, pass the
  /// HMAC-SHA256 of [externalId] made by your backend as [identityHash].
  static Future<void> login(String externalId, {String? identityHash}) async {
    await _ready.future;
    await _prefs!.setString(_Keys.externalId, externalId);
    if (identityHash != null) {
      await _prefs!.setString(_Keys.identityHash, identityHash);
    } else {
      await _prefs!.remove(_Keys.identityHash);
    }
    await _update({'external_id': externalId, if (identityHash != null) 'identity_hash': identityHash});
  }

  static Future<void> logout() async {
    await _ready.future;
    await _prefs!.remove(_Keys.externalId);
    await _prefs!.remove(_Keys.identityHash);
    await _update({'external_id': null});
  }

  // --- internals ---

  /// On Android, Firebase starts from the settings uploaded to Takeed (the app has no
  /// google-services.json). Fetched on every start so a changed project is picked up; when
  /// Takeed can't be reached, the settings saved last time are used.
  static Future<void> _setupFirebase() async {
    final package = await _native.androidPackage();
    if (package == null) return;
    try {
      final config = await _api!.config(package: package, branch: _branch);
      final firebase = config['firebase'];
      if (firebase is Map) {
        await _native.configureFirebase(Map<String, dynamic>.from(firebase));
      } else {
        debugPrint('Takeed: no Firebase settings for $package. '
            "Add google-services.json to the app's Firebase key in the Takeed dashboard.");
      }
    } catch (e) {
      debugPrint('Takeed: could not get Firebase settings: $e');
    }
  }

  static Future<void> _register({String? token}) async {
    if (token == null) await _setupFirebase();
    Map<String, dynamic>? push;
    try {
      push = await _native.pushToken();
    } on PlatformException catch (e) {
      debugPrint('Takeed: no push token: ${e.message}');
      return;
    }
    if (push == null || (push['token'] ?? '').toString().isEmpty) return;
    if (token != null) push['token'] = token;

    final info = await _native.deviceInfo();
    final optedOut = _prefs!.getBool(_Keys.optedOut) ?? false;
    final permission = await _native.permission();
    final externalId = _prefs!.getString(_Keys.externalId);
    final hash = _prefs!.getString(_Keys.identityHash);

    final body = <String, dynamic>{
      'type': push['type'],
      'token': push['token'],
      'config_identifier': push['config_identifier'],
      if (push['type'] == 'ios') 'apns_sandbox': push['apns_sandbox'] == true,
      'notification_permission': permission && !optedOut,
      'sdk_version': _sdkVersion,
      if (_branch != null) 'branch': _branch,
      if (externalId != null) 'external_id': externalId,
      if (hash != null) 'identity_hash': hash,
      ...info.map((k, v) => MapEntry(k, v)),
    }..removeWhere((k, v) => v == null);

    try {
      final previous = User.pushSubscription._state();
      final res = await _api!.register(body);
      await _prefs!.setString(_Keys.subscriptionId, res['id'].toString());
      await _prefs!.setString(_Keys.userId, res['user_id'].toString());
      await _prefs!.setString(_Keys.token, push['token'].toString());
      await _prefs!.setInt(_Keys.lastSession, DateTime.now().millisecondsSinceEpoch);
      User.pushSubscription._notify(previous);
    } catch (e) {
      debugPrint('Takeed: registration failed: $e');
    }
  }

  static Future<void> _update(Map<String, dynamic> body) async {
    final id = _prefs?.getString(_Keys.subscriptionId);
    if (id == null) {
      // Not registered yet (e.g. offline at start): registering sends the saved state.
      await _register();
      return;
    }
    try {
      await _api!.update(id, body);
    } on TakeedApiException catch (e) {
      if (e.status == 404) {
        await _prefs!.remove(_Keys.subscriptionId);
        await _register();
      } else {
        debugPrint('Takeed: update failed: $e');
      }
    } catch (e) {
      debugPrint('Takeed: update failed: $e');
    }
  }

  static Future<void> _pingSession() async {
    final last = _prefs!.getInt(_Keys.lastSession) ?? 0;
    if (_prefs!.getString(_Keys.subscriptionId) == null) return;
    if (DateTime.now().millisecondsSinceEpoch - last < _sessionGap.inMilliseconds) return;
    await _prefs!.setInt(_Keys.lastSession, DateTime.now().millisecondsSinceEpoch);
    await _update({'session': true, ...await _native.deviceInfo()}..removeWhere((k, v) => v == null));
  }

  static Future<dynamic> _onNativeCall(MethodCall call) async {
    final args = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : <String, dynamic>{};
    switch (call.method) {
      case 'onToken':
        if (args['token'] != null && args['token'] != _prefs?.getString(_Keys.token)) {
          await _register(token: args['token'].toString());
        }
      case 'onClick':
        Notifications._dispatchClick(args);
      case 'onForeground':
        return Notifications._dispatchForeground(args);
      case 'onPermission':
        await Notifications._permissionChanged(args['granted'] == true);
      case 'onResume':
        await _pingSession();
    }
    return null;
  }

  /// For tests: replace the native bridge and the API client, and reset state.
  @visibleForTesting
  static void debugReset({TakeedNative? native, TakeedApi? api}) {
    _native = native ?? TakeedNative();
    _api = api;
    _prefs = null;
    _ready = Completer<void>();
    _branch = null;
    Notifications._reset();
    User.pushSubscription._observers.clear();
  }
}

class TakeedUser {
  TakeedUser._();

  final TakeedPushSubscription pushSubscription = TakeedPushSubscription._();

  Future<void> addTag(String key, Object value) => addTags({key: value});

  /// onesignal_flutter name for [addTag].
  Future<void> addTagWithKey(String key, Object value) => addTag(key, value);

  Future<void> addTags(Map<String, Object> tags) async {
    await Takeed._ready.future;
    await Takeed._update({'tags': tags.map((k, v) => MapEntry(k, v.toString()))});
  }

  Future<void> removeTag(String key) => removeTags([key]);

  Future<void> removeTags(List<String> keys) async {
    await Takeed._ready.future;
    await Takeed._update({
      'tags': {for (final k in keys) k: null}
    });
  }

  Future<void> setLanguage(String language) async {
    await Takeed._ready.future;
    await Takeed._update({'language': language});
  }

  Future<void> setEmail(String email) async {
    await Takeed._ready.future;
    await Takeed._update({'email': email});
  }

  Future<void> addEmail(String email) => setEmail(email);

  /// E.164, e.g. +9647701234567.
  Future<void> setPhone(String phone) async {
    await Takeed._ready.future;
    await Takeed._update({'phone': phone});
  }

  Future<void> addSms(String phone) => setPhone(phone);

  /// Only send this if the app already has location permission.
  Future<void> setLocation(double latitude, double longitude) async {
    await Takeed._ready.future;
    await Takeed._update({
      'location': {'lat': latitude, 'lng': longitude}
    });
  }

  /// The platform's user ID (OneSignal ID equivalent).
  Future<String?> getOnesignalId() async => (await SharedPreferences.getInstance()).getString(_Keys.userId);

  Future<String?> getExternalId() async => (await SharedPreferences.getInstance()).getString(_Keys.externalId);
}

class TakeedPushSubscription {
  TakeedPushSubscription._();

  final List<void Function(TakeedPushSubscriptionChangedState)> _observers = [];

  String? get id => Takeed._prefs?.getString(_Keys.subscriptionId);
  String? get token => Takeed._prefs?.getString(_Keys.token);
  bool get optedIn =>
      id != null && !(Takeed._prefs?.getBool(_Keys.optedOut) ?? false) && Takeed.Notifications._permission;

  Future<void> optIn() async {
    await Takeed._ready.future;
    final previous = _state();
    await Takeed._prefs!.remove(_Keys.optedOut);
    if (!await Takeed._native.permission()) {
      await Takeed.Notifications.requestPermission(true);
    } else {
      await Takeed._update({'notification_permission': true});
    }
    _notify(previous);
  }

  Future<void> optOut() async {
    await Takeed._ready.future;
    final previous = _state();
    await Takeed._prefs!.setBool(_Keys.optedOut, true);
    await Takeed._update({'notification_permission': false});
    _notify(previous);
  }

  void addObserver(void Function(TakeedPushSubscriptionChangedState state) observer) => _observers.add(observer);

  void removeObserver(void Function(TakeedPushSubscriptionChangedState state) observer) => _observers.remove(observer);

  TakeedPushSubscriptionState _state() => TakeedPushSubscriptionState(id: id, token: token, optedIn: optedIn);

  void _notify(TakeedPushSubscriptionState previous) {
    final current = _state();
    if (previous.id == current.id && previous.token == current.token && previous.optedIn == current.optedIn) return;
    for (final o in List.of(_observers)) {
      o(TakeedPushSubscriptionChangedState(previous, current));
    }
  }
}

class TakeedNotifications {
  TakeedNotifications._();

  final List<void Function(TakeedNotificationClickEvent)> _clickListeners = [];
  final List<void Function(TakeedNotificationWillDisplayEvent)> _foregroundListeners = [];
  final List<void Function(bool)> _permissionObservers = [];
  final List<Map<String, dynamic>> _pendingClicks = [];
  bool _permission = false;

  bool get permission => _permission;

  /// Ask for permission (Android 13+ and iOS). Returns whether it is granted.
  Future<bool> requestPermission(bool fallbackToSettings) async {
    await Takeed._ready.future;
    final granted = await Takeed._native.requestPermission();
    await _permissionChanged(granted);
    return granted;
  }

  Future<bool> canRequest() async => !(await Takeed._native.permission());

  void addClickListener(void Function(TakeedNotificationClickEvent event) listener) {
    _clickListeners.add(listener);
    // Deliver a click that opened the app before any listener existed.
    final pending = List.of(_pendingClicks);
    _pendingClicks.clear();
    pending.forEach(_dispatchClick);
  }

  void removeClickListener(void Function(TakeedNotificationClickEvent event) listener) =>
      _clickListeners.remove(listener);

  /// Called when a notification arrives while the app is open.
  void addForegroundListener(void Function(TakeedNotificationWillDisplayEvent event) listener) =>
      _foregroundListeners.add(listener);

  /// onesignal_flutter name for [addForegroundListener].
  void addForegroundWillDisplayListener(void Function(TakeedNotificationWillDisplayEvent event) listener) =>
      addForegroundListener(listener);

  void removeForegroundWillDisplayListener(void Function(TakeedNotificationWillDisplayEvent event) listener) =>
      _foregroundListeners.remove(listener);

  void addPermissionObserver(void Function(bool granted) observer) => _permissionObservers.add(observer);

  void removePermissionObserver(void Function(bool granted) observer) => _permissionObservers.remove(observer);

  void _dispatchClick(Map<String, dynamic> payload) {
    if (_clickListeners.isEmpty) {
      _pendingClicks.add(payload);
      return;
    }
    final event = TakeedNotificationClickEvent(
      TakeedNotification.fromMap(payload),
      TakeedNotificationClickResult(actionId: payload['action_id']?.toString(), url: payload['url']?.toString()),
    );
    for (final l in List.of(_clickListeners)) {
      l(event);
    }
  }

  /// Returns whether the native side should show the notification.
  bool _dispatchForeground(Map<String, dynamic> payload) {
    if (_foregroundListeners.isEmpty) return true;
    final notification = TakeedNotification.fromMap(payload);
    var show = true;
    var decided = false;
    final event = TakeedNotificationWillDisplayEvent(notification, (s) {
      show = s;
      if (decided) Takeed._native.displayForeground(notification.notificationId, s);
    });
    for (final l in List.of(_foregroundListeners)) {
      l(event);
    }
    decided = true;
    return event.handled ? show : true;
  }

  Future<void> _permissionChanged(bool granted) async {
    final changed = granted != _permission;
    _permission = granted;
    if (!changed) return;
    final optedOut = Takeed._prefs?.getBool(_Keys.optedOut) ?? false;
    await Takeed._update({'notification_permission': granted && !optedOut});
    for (final o in List.of(_permissionObservers)) {
      o(granted);
    }
  }

  void _reset() {
    _clickListeners.clear();
    _foregroundListeners.clear();
    _permissionObservers.clear();
    _pendingClicks.clear();
    _permission = false;
  }
}
