import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:takeed/takeed.dart';
import 'package:takeed/src/api.dart';
import 'package:takeed/src/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('takeed');
  late List<http.Request> requests;
  late bool permission;

  setUp(() {
    requests = [];
    permission = true;
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'pushToken':
          return {'type': 'android', 'token': 'fcm-token-123', 'config_identifier': 'shop-firebase'};
        case 'permission':
          return permission;
        case 'requestPermission':
          permission = true;
          return true;
        case 'deviceInfo':
          return {
            'device_model': 'Pixel 8',
            'os_version': '15',
            'app_version': '2.1.0',
            'language': 'ar',
            'timezone': 'Asia/Baghdad'
          };
        case 'initialClick':
          return null;
      }
      return null;
    });

    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST' && request.url.path.endsWith('/subscriptions')) {
        return http.Response(jsonEncode({'id': 'sub-1', 'user_id': 'user-1'}), 201);
      }
      return http.Response(jsonEncode({'id': 'sub-1', 'user_id': 'user-1'}), 200);
    });

    Takeed.debugReset(
        native: TakeedNative(channel), api: TakeedApi(baseUrl: 'https://takeed.test', appId: 'app-1', client: client));
  });

  Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

  test('initialize registers the device with its details', () async {
    await Takeed.initialize('app-1', branch: 'north');

    final register = requests.single;
    expect(register.url.toString(), 'https://takeed.test/api/v1/apps/app-1/subscriptions');
    expect(body(register), containsPair('type', 'android'));
    expect(body(register), containsPair('token', 'fcm-token-123'));
    expect(body(register), containsPair('config_identifier', 'shop-firebase'));
    expect(body(register), containsPair('branch', 'north'));
    expect(body(register), containsPair('language', 'ar'));
    expect(body(register), containsPair('notification_permission', true));
    expect(body(register)['sdk_version'], startsWith('takeed-flutter/'));
    expect(Takeed.User.pushSubscription.id, 'sub-1');
  });

  test('login, tags and logout update the subscription', () async {
    await Takeed.initialize('app-1');
    await Takeed.login('user-42', identityHash: 'h' * 64);
    await Takeed.User.addTagWithKey('plan', 'gold');
    await Takeed.User.addTags({'visits': 3});
    await Takeed.User.removeTag('plan');
    await Takeed.logout();

    final patches = requests.where((r) => r.method == 'PATCH').toList();
    expect(patches.every((r) => r.url.path.endsWith('/subscriptions/sub-1')), isTrue);
    expect(patches.map(body).toList(), [
      {'external_id': 'user-42', 'identity_hash': 'h' * 64},
      {
        'tags': {'plan': 'gold'}
      },
      {
        'tags': {'visits': '3'}
      },
      {
        'tags': {'plan': null}
      },
      {'external_id': null},
    ]);
    expect(await Takeed.User.getExternalId(), isNull);
  });

  test('a login before initialize waits for it and is sent on registration', () async {
    final pending = Takeed.login('early');
    await Takeed.initialize('app-1');
    await pending;
    // The external ID reaches the server with a registration or an update.
    expect(requests.map(body).any((b) => b['external_id'] == 'early'), isTrue);
  });

  test('opting out tells the server and notifies observers', () async {
    await Takeed.initialize('app-1');
    await Takeed.Notifications.requestPermission(true);
    final changes = <bool>[];
    Takeed.User.pushSubscription.addObserver((s) => changes.add(s.current.optedIn));

    await Takeed.User.pushSubscription.optOut();
    expect(body(requests.last), {'notification_permission': false});
    expect(changes, [false]);
    expect(Takeed.User.pushSubscription.optedIn, isFalse);
  });

  test('clicks reach listeners, including a click that opened the app first', () async {
    await Takeed.initialize('app-1');

    final codec = const StandardMethodCodec();
    Future<void> nativeSends(String method, Map<String, dynamic> args) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage('takeed', codec.encodeMethodCall(MethodCall(method, args)), (_) {});

    await nativeSends('onClick', {
      'notification_id': 'n-1',
      'action_id': 'pay',
      'data': {'order': '7'}
    });

    TakeedNotificationClickEvent? got;
    Takeed.Notifications.addClickListener((e) => got = e);
    expect(got?.notification.notificationId, 'n-1');
    expect(got?.result.actionId, 'pay');
    expect(got?.notification.additionalData, {'order': '7'});
  });

  test('foreground listeners can stop a notification from showing', () async {
    await Takeed.initialize('app-1');
    Takeed.Notifications.addForegroundWillDisplayListener((e) => e.preventDefault());

    final codec = const StandardMethodCodec();
    bool? show;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'takeed',
      codec.encodeMethodCall(const MethodCall('onForeground', {'notification_id': 'n-2', 'title': 'Hi'})),
      (data) => show = codec.decodeEnvelope(data!) as bool,
    );
    expect(show, isFalse);
  });

  test('registration retries when an update finds the subscription gone', () async {
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'PATCH') {
        return http.Response(
            jsonEncode({
              'errors': [
                {'code': 'not_found', 'message': 'gone'}
              ]
            }),
            404);
      }
      return http.Response(jsonEncode({'id': 'sub-2', 'user_id': 'user-2'}), 201);
    });
    Takeed.debugReset(
        native: TakeedNative(channel), api: TakeedApi(baseUrl: 'https://takeed.test', appId: 'app-1', client: client));

    await Takeed.initialize('app-1');
    await Takeed.User.addTag('a', 'b');
    expect(requests.where((r) => r.method == 'POST').length, 2);
    expect(Takeed.User.pushSubscription.id, 'sub-2');
  });
}
