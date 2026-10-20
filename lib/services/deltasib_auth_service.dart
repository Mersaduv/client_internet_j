import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'app_secure_storage.dart';
import 'settings_service.dart';
import 'sib_http.dart';

/// نام کاربری مشترک روی همین گوشی.
///
/// توکن ریسلر Api روی گوشی نیست. حجم را ورکر با یوزر Api سرور و
/// Filter=Username همان مشترک می‌گیرد.
class DeltaSibAuthService {
  DeltaSibAuthService._();
  static final DeltaSibAuthService instance = DeltaSibAuthService._();
  factory DeltaSibAuthService() => instance;

  /// پیش‌فرض فقط وقتی ولایت ذخیره نشده باشد (هرات).
  static const String defaultOrigin =
      'https://jb-herat.mersadkarimi001.workers.dev';

  static final _storage = AppSecureStorage.instance;

  static const _keyToken = 'sib_token';
  static const _keyUsername = 'sib_username';
  static const _keyPassword = 'sib_password';
  static const _keySession = 'sib_session';

  Future<void>? _pending;

  /// تمام می‌شود وقتی ذخیرهٔ نام مشترک، اگر در جریان باشد، تمام شود.
  Future<void> get ready => _pending ?? Future<void>.value();

  static String apiKeyForPassword(String password) {
    return sha512.convert(utf8.encode(password)).toString();
  }

  Future<String?> savedUsername() => _storage.read(key: _keyUsername);

  Future<String?> savedSession() => _storage.read(key: _keySession);

  /// خروج: نشست سرور پاک می‌شود و کلید گوشی هم حذف می‌شود.
  Future<void> logout() async {
    final session = await savedSession();
    if (session != null && session.isNotEmpty) {
      try {
        final uri = Uri.parse('$defaultOrigin/jahanbit/sib/logout');
        final request = await SibHttp.client
            .postUrl(uri)
            .timeout(const Duration(seconds: 8));
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.write(jsonEncode({'session': session}));
        await request.close().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[SIB_LOGOUT] $e');
      }
    }
    await clear();
  }

  /// کد ۱۰ رقمی را با نام مشترکِ ذخیره‌شده روی سرور عوض می‌کند.
  /// کد یک‌بارمصرف می‌سوزد و رمز Winbox را فقط همین یک بار برمی‌گرداند.
  /// کد همیشگی دوباره قابل استفاده است و رمز روتر ندارد.
  Future<RedeemedAccess> redeemAccessCode({
    required String code,
    required String origin,
  }) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      throw DeltaSibAuthException('کد باید ۱۰ رقم باشد.');
    }
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final uri = Uri.parse('$base/jahanbit/sib/redeem');
    final request = await SibHttp.client
        .postUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    request.write(jsonEncode({'code': digits}));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw DeltaSibAuthException(_redeemError(text, response.statusCode));
    }
    final decoded = jsonDecode(text);
    final session = decoded is Map ? decoded['session']?.toString() : null;
    final username = decoded is Map ? decoded['username']?.toString().trim() : null;
    final routerPassword = decoded is Map
        ? decoded['routerPassword']?.toString()
        : null;
    if (session == null || session.isEmpty || username == null || username.isEmpty) {
      throw DeltaSibAuthException('نشست حجم ساخته نشد.');
    }
    try {
      await _storage.write(key: _keySession, value: session);
      await _storage.write(key: _keyUsername, value: username);
    } catch (e) {
      debugPrint('[SIB] session persist failed: $e');
    }
    return RedeemedAccess(
      username: username,
      routerPassword: routerPassword != null && routerPassword.isNotEmpty
          ? routerPassword
          : null,
    );
  }

  /// نام مشترک را نگه می‌دارد و توکن/رمز Api ذخیره‌شدهٔ قبلی را پاک می‌کند.
  /// رمز روتر به دلتاسیب فرستاده نمی‌شود.
  Future<void> rememberSubscriber(String username) {
    late final Future<void> run;
    run = _remember(username).whenComplete(() {
      if (identical(_pending, run)) _pending = null;
    });
    _pending = run;
    return run;
  }

  Future<void> _remember(String username) async {
    final name = username.trim();
    if (name.isEmpty) {
      throw DeltaSibAuthException('نام کاربری مشترک خالی است.');
    }
    final previous = (await _storage.read(key: _keyUsername))?.trim();
    await _storage.write(key: _keyUsername, value: name);
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyPassword);
    if (previous != null && previous != name) {
      await _storage.delete(key: _keySession);
    }
  }

  Future<void> clear() async {
    _pending = null;
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keySession);
  }

  static String _redeemError(String text, int status) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return 'کد ورود پذیرفته نشد (HTTP $status)';
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
}

class SibLoginResult {
  const SibLoginResult({required this.token, this.sessionTimeoutSeconds});
  final String token;
  final int? sessionTimeoutSeconds;
}

class RedeemedAccess {
  const RedeemedAccess({required this.username, this.routerPassword});

  final String username;
  final String? routerPassword;
}

class DeltaSibAuthException implements Exception {
  DeltaSibAuthException(this.message, {this.sessionExpired = false});
  final String message;
  final bool sessionExpired;
  @override
  String toString() => message;
}

/// خانه این را می‌شنود و به صفحهٔ ورود برمی‌گردد.
final ValueNotifier<int> subscriberSessionEnded = ValueNotifier(0);
bool _endingSubscriberSession = false;

Future<void> endSubscriberSession() async {
  if (_endingSubscriberSession) return;
  _endingSubscriberSession = true;
  try {
    await DeltaSibAuthService().logout();
    final settings = SettingsService();
    await settings.clearLoginTimestamp();
    await settings.clearLastActivity();
    subscriberSessionEnded.value++;
  } finally {
    _endingSubscriberSession = false;
  }
}
