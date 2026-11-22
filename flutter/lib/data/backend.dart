import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../domain/planner.dart';
import 'config.dart';

abstract class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureCredentials implements CredentialStore {
  final FlutterSecureStorage storage;
  final String storageKey;
  SecureCredentials({
    this.storage = const FlutterSecureStorage(),
    this.storageKey = 'heist.auth.v1',
  });
  @override
  Future<String?> read() => storage.read(key: storageKey);
  @override
  Future<void> write(String value) async {
    await storage.write(key: storageKey, value: value);
  }

  @override
  Future<void> clear() async {
    await storage.delete(key: storageKey);
  }
}

class BackendFailure implements Exception {
  final int status;
  final String message;
  BackendFailure(this.status, this.message);
  bool get retryable =>
      status == 0 || status == 408 || status == 429 || status >= 500;
  @override
  String toString() => message;
}

class HeistBackend {
  final http.Client client;
  final CredentialStore credentials;
  final String url, publishableKey;
  Json? session;
  String? dataKey;
  Future<String>? _refresh;
  HeistBackend({
    http.Client? client,
    CredentialStore? credentials,
    this.url = AppConfig.supabaseUrl,
    this.publishableKey = AppConfig.publishableKey,
  }) : client = client ?? http.Client(),
       credentials = credentials ?? SecureCredentials();
  bool get configured =>
      url.startsWith('https://') && publishableKey.isNotEmpty;
  String? get uid => session?['user']?['id'] as String?;
  Future<void> initialize() async {
    final encoded = await credentials.read();
    if (encoded == null) return;
    try {
      final saved = jsonDecode(encoded) as Map;
      session = Map<String, dynamic>.from(saved['session']);
      dataKey = saved['dataKey'] as String?;
    } catch (_) {
      await credentials.clear();
    }
  }

  Future<void> persist() async =>
      credentials.write(jsonEncode({'session': session, 'dataKey': dataKey}));
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    bool auth = true,
    String? prefer,
    String? token,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!configured)
      throw BackendFailure(
        0,
        'Backend configuration is missing. Local data remains available.',
      );
    final headers = {
      'apikey': publishableKey,
      'Content-Type': 'application/json',
      if (prefer != null) 'Prefer': prefer,
    };
    if (auth)
      headers['Authorization'] = 'Bearer ${token ?? await accessToken()}';
    final request = http.Request(method, Uri.parse('$url$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(timeout);
    } catch (_) {
      throw BackendFailure(
        0,
        'Cannot reach the server. Changes remain saved on this device.',
      );
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw BackendFailure(
        response.statusCode,
        'The server returned an unreadable response.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['msg'] ??
                decoded['message'] ??
                decoded['error_description'] ??
                decoded['error']
          : null;
      throw BackendFailure(
        response.statusCode,
        message?.toString() ??
            'Server request failed (${response.statusCode}).',
      );
    }
    return decoded;
  }

  Future<void> setSession(Json value) async {
    final previousUid = uid;
    if (previousUid != null && previousUid != value['user']?['id'])
      dataKey = null;
    session = {
      ...value,
      'expires_at':
          DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          (value['expires_in'] as num? ?? 3600),
    };
    await persist();
  }

  Future<void> acceptAuthLink(Uri link) async {
    final values = Uri.splitQueryString(link.fragment);
    if (values['access_token'] == null || values['refresh_token'] == null)
      throw BackendFailure(401, 'The sign-in link is incomplete or expired.');
    final user = await request('/auth/v1/user', token: values['access_token']);
    if (uid != (user as Map)['id']) dataKey = null;
    await setSession({
      'access_token': values['access_token'],
      'refresh_token': values['refresh_token'],
      'expires_in': int.tryParse(values['expires_in'] ?? '') ?? 3600,
      'user': user,
    });
  }

  Future<String> accessToken() async {
    if (session == null) throw BackendFailure(401, 'Sign in to synchronize.');
    if (number(session!['expires_at']) >
        DateTime.now().millisecondsSinceEpoch / 1000 + 60)
      return session!['access_token'] as String;
    if (_refresh != null) return _refresh!;
    _refresh = (() async {
      final value = await request(
        '/auth/v1/token?grant_type=refresh_token',
        method: 'POST',
        auth: false,
        body: {'refresh_token': session!['refresh_token']},
      );
      await setSession(Map<String, dynamic>.from(value as Map));
      return session!['access_token'] as String;
    })();
    try {
      return await _refresh!;
    } finally {
      _refresh = null;
    }
  }

  Future<void> sendCode(String email) async => request(
    '/auth/v1/otp?redirect_to=${Uri.encodeComponent(AppConfig.authRedirect)}',
    method: 'POST',
    auth: false,
    body: {'email': email, 'create_user': true},
  );
  Future<void> verifyCode(String email, String code) async {
    final data = await request(
      '/auth/v1/verify',
      method: 'POST',
      auth: false,
      body: {'type': 'email', 'email': email, 'token': code},
    );
    await setSession(Map<String, dynamic>.from(data as Map));
  }

  Future<Json?> vault() async {
    final data = await request(
      '/rest/v1/vaults?user_id=eq.${Uri.encodeComponent(uid!)}&select=*',
    );
    return rows(data).firstOrNull;
  }

  Future<Json?> compareAndSwap(int version, String encrypted) async {
    final data = await request(
      '/rest/v1/vaults?user_id=eq.${Uri.encodeComponent(uid!)}&version=eq.$version',
      method: 'PATCH',
      prefer: 'return=representation',
      body: {'data': encrypted, 'version': version + 1, 'device': 'Flutter'},
    );
    return rows(data).firstOrNull;
  }

  Future<void> signOut() async {
    try {
      if (session != null)
        await request('/auth/v1/logout?scope=local', method: 'POST');
    } catch (_) {
      /* Local sign-out must work offline. */
    }
    session = null;
    dataKey = null;
    await credentials.clear();
  }
}
