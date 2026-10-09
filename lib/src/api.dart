import 'dart:convert';

import 'package:http/http.dart' as http;

class TakeedApiException implements Exception {
  TakeedApiException(this.status, this.code, this.message);
  final int status;
  final String? code;
  final String message;

  @override
  String toString() => 'TakeedApiException($status, $code): $message';
}

/// The SDK endpoints of Takeed (public App ID; no secret in the app).
class TakeedApi {
  TakeedApi({required this.baseUrl, required this.appId, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String appId;
  final http.Client _client;

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1/apps/${Uri.encodeComponent(appId)}$path');

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) => _send('POST', '/subscriptions', body);

  Future<Map<String, dynamic>> update(String subscriptionId, Map<String, dynamic> body) =>
      _send('PATCH', '/subscriptions/${Uri.encodeComponent(subscriptionId)}', body);

  Future<Map<String, dynamic>> event(String type, String receiptId, {String? buttonId}) =>
      _send('POST', '/events', {'type': type, 'receipt_id': receiptId, if (buttonId != null) 'button_id': buttonId});

  Future<Map<String, dynamic>> _send(String method, String path, Map<String, dynamic> body) async {
    final request = http.Request(method, _uri(path))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json'
      ..body = jsonEncode(body);
    final response = await http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 20)));
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode >= 400) {
      final error = (json['errors'] is List && (json['errors'] as List).isNotEmpty)
          ? (json['errors'] as List).first as Map
          : const {};
      throw TakeedApiException(
          response.statusCode, error['code']?.toString(), error['message']?.toString() ?? 'Request failed');
    }
    return json;
  }
}
