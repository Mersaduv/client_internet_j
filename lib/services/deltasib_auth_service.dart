import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'sib_http.dart';

/// کلاینت REST دلتاسیب (WebService 1.0).
///
  /// ورود واقعی روی پنل هرات (همان صفحهٔ تست که از ورکر جواب می‌دهد):
/// POST {origin}/test/webservice/api/restfull/test.login.php
/// فیلدها: Api_Username و Api_Password
/// پاسخ HTML شامل JSON با token و SessionTimeout است.
/// مسیر /1.0/auth/ روی پورت 1043 از اینجا 521 می‌دهد و استفاده نمی‌شود.
///
/// توکن در اپ منقضی نمی‌شود. اگر سرور SessionTimeout بدهد، قبل از پایان
/// با همان یوزر/رمز تمدید می‌شود تا از دید کاربر همیشگی بماند.
class DeltaSibAuthService {
  DeltaSibAuthService._();
  static final DeltaSibAuthService instance = DeltaSibAuthService._();
  factory DeltaSibAuthService() => instance;

  /// پیش‌فرض فقط وقتی ولایت ذخیره نشده باشد (هرات).
  static const String defaultOrigin =
      'https://jb-herat.mersadkarimi001.workers.dev';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyToken = 'sib_token';
  static const _keyUsername = 'sib_username';
  static const _keyPassword = 'sib_password';

  Timer? _renewTimer;
  String? _cachedToken;
  Future<String>? _pending;

  /// تمام می‌شود وقتی ورودِ در حال اجرا، اگر باشد، تمام شود.
  Future<void> get ready => _pending ?? Future<void>.value();

  static String apiKeyForPassword(String password) {
    return sha512.convert(utf8.encode(password)).toString();
  }

  Future<String?> savedUsername() => _storage.read(key: _keyUsername);

  Future<String?> currentToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) return _cachedToken;
    _cachedToken = await _storage.read(key: _keyToken);
    return _cachedToken;
  }

  /// دریافت توکن و ذخیرهٔ دائمی. خطا را throw می‌کند.
  Future<String> login({
    required String username,
    required String password,
    String origin = defaultOrigin,
  }) {
    late final Future<String> run;
    run = _login(
      username: username,
      password: password,
      origin: origin,
    ).whenComplete(() {
      if (identical(_pending, run)) _pending = null;
    });
    _pending = run;
    return run;
  }

  Future<String> _login({
    required String username,
    required String password,
    required String origin,
  }) async {
    final session = await _requestToken(
      username: username,
      password: password,
      origin: origin,
    );
    await Future.wait<void>([
      _storage.write(key: _keyToken, value: session.token),
      _storage.write(key: _keyUsername, value: username),
      _storage.write(key: _keyPassword, value: password),
    ]);
    _cachedToken = session.token;
    _scheduleRenew(session.sessionTimeoutSeconds, origin);
    return session.token;
  }

  /// اگر توکن ذخیره شده باشد همان را برمی‌گرداند؛ وگرنه با اعتبار ذخیره تمدید می‌کند.
  Future<String?> ensureToken({String origin = defaultOrigin}) async {
    final existing = await currentToken();
    if (existing != null && existing.isNotEmpty) {
      _scheduleRenew(null, origin);
      return existing;
    }
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    if (username == null || password == null) return null;
    return login(username: username, password: password, origin: origin);
  }

  Future<void> clear() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    _cachedToken = null;
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
  }

  void _scheduleRenew(int? timeoutSeconds, String origin) {
    _renewTimer?.cancel();
    // بدون SessionTimeout یا مقدار صفر = توکن سرور همیشگی است.
    if (timeoutSeconds == null || timeoutSeconds <= 0) return;
    final wait = Duration(
      seconds: timeoutSeconds > 120 ? timeoutSeconds - 60 : (timeoutSeconds * 0.8).floor(),
    );
    if (wait.inSeconds < 5) return;
    _renewTimer = Timer(wait, () async {
      try {
        final username = await _storage.read(key: _keyUsername);
        final password = await _storage.read(key: _keyPassword);
        if (username == null || password == null) return;
        await login(username: username, password: password, origin: origin);
      } catch (e) {
        debugPrint('[SIB] renew failed: $e');
      }
    });
  }

  Future<_SibSession> _requestToken({
    required String username,
    required String password,
    required String origin,
  }) async {
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final uri = Uri.parse(
      '$base/test/webservice/api/restfull/test.login.php',
    );
    final body = {
      'Api_Username': username,
      'Api_Password': password,
      'submit': 'Submit',
    };

    try {
      final request = await SibHttp.client
          .postUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: body).query);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200 || text.contains('error code: 521')) {
        throw DeltaSibAuthException(
          'دلتاسیب HTTP ${response.statusCode}',
        );
      }
      final parsed = parseLoginPage(text);
      if (parsed == null) {
        throw DeltaSibAuthException('توکن دلتاسیب در پاسخ پیدا نشد');
      }
      return _SibSession(
        token: parsed.token,
        sessionTimeoutSeconds: parsed.sessionTimeoutSeconds,
      );
    } on DeltaSibAuthException {
      rethrow;
    } catch (e) {
      throw DeltaSibAuthException('اتصال به دلتاسیب برقرار نشد: $e');
    }
  }

  /// HTML صفحهٔ test.login.php یا JSON خام را به توکن تبدیل می‌کند.
  static SibLoginResult? parseLoginPage(String body) {
    final jsonMatch = RegExp(
      r'\{\s*"token"\s*:\s*"([^"]+)"\s*,\s*"SessionTimeout"\s*:\s*"?(\d+)"?\s*\}',
    ).firstMatch(body);
    if (jsonMatch != null) {
      return SibLoginResult(
        token: jsonMatch.group(1)!.replaceAll(RegExp(r'\s+'), ''),
        sessionTimeoutSeconds: int.tryParse(jsonMatch.group(2)!),
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final token = decoded['token']?.toString();
        if (token != null && token.isNotEmpty) {
          final raw = decoded['SessionTimeout'];
          final timeout = raw is num ? raw.toInt() : int.tryParse('$raw');
          return SibLoginResult(
            token: token,
            sessionTimeoutSeconds: timeout,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  String? _errorText(Map<String, dynamic> json) {
    final code = json['ErrorCode'];
    final desc = json['ErrorDesc']?.toString();
    if (code == null && (desc == null || desc.isEmpty)) return null;
    if (desc != null && desc.isNotEmpty) {
      return code == null ? desc : '$desc ($code)';
    }
    return 'خطای دلتاسیب $code';
  }
}

class SibLoginResult {
  const SibLoginResult({required this.token, this.sessionTimeoutSeconds});
  final String token;
  final int? sessionTimeoutSeconds;
}

class DeltaSibAuthException implements Exception {
  DeltaSibAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _SibSession {
  _SibSession({required this.token, this.sessionTimeoutSeconds});
  final String token;
  final int? sessionTimeoutSeconds;
}
