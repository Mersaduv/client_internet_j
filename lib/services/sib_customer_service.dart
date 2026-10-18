import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/internet_packages_data.dart';
import '../utils/sib_package_insight.dart';
import 'deltasib_auth_service.dart';
import 'settings_service.dart';
import 'sib_http.dart';

/// خواندن اطلاعات مشترک از صفحه‌های تست وب‌سرویس دلتاسیب (همان میزبان ورکر).
class SibCustomerService {
  SibCustomerService({DeltaSibAuthService? auth, SettingsService? settings})
      : _auth = auth ?? DeltaSibAuthService(),
        _settings = settings ?? SettingsService();

  final DeltaSibAuthService _auth;
  final SettingsService _settings;

  Future<SibCustomerSnapshot> load({String? username}) async {
    final credit = await loadCredit(username: username);
    return SibCustomerSnapshot(
      username: (username ?? await _auth.savedUsername() ?? '').trim(),
      credit: credit,
      status: null,
      services: null,
    );
  }

  /// فقط creditinfo؛ کارت بسته به وضعیت و فهرست سرویس نیاز ندارد.
  Future<Map<String, dynamic>?> loadCredit({String? username}) async {
    final token = await _auth.currentToken();
    if (token == null || token.isEmpty) {
      throw DeltaSibAuthException('اول وارد شوید تا توکن SIB ساخته شود.');
    }
    final saved = await _auth.savedUsername();
    final user = (username ?? saved ?? '').trim();
    if (user.isEmpty) {
      throw DeltaSibAuthException('نام کاربری مشترک خالی است.');
    }
    final origin = await _origin();
    final raw = await _post(
      origin,
      'test.user.creditinfo.php',
      {
        'token': token,
        'Object': 'user',
        'Action': 'creditinfo',
        'Filter': "Username='$user'",
        'submit': 'Submit',
      },
    );
    final decoded = _decode(raw);
    final records = SibPackageInsight.creditRecords(decoded);
    if (records.isNotEmpty) return records.first;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  /// نام و تخلص از user/list.
  ///
  /// صفحهٔ test.user.list.php فیلتر را به API نمی‌فرستد و پورت ۱۰۴۳ از بیرون
  /// در دسترس نیست. همان صفحهٔ creditinfo پارامتر Action و Filter را به
  /// `https://127.0.0.1:1043/1.0/` می‌رساند، پس Action=list همان فهرست PDF است.
  Future<String?> loadDisplayName({String? username}) async {
    try {
      final token = await _auth.currentToken();
      if (token == null || token.isEmpty) return null;
      final saved = await _auth.savedUsername();
      final user = (username ?? saved ?? '').trim();
      if (user.isEmpty) return null;
      final origin = await _origin();
      final raw = await _post(
        origin,
        'test.user.creditinfo.php',
        {
          'token': token,
          'Object': 'user',
          'Action': 'list',
          'Filter': "Username='$user'",
          'Field': 'User_Id,Username,Name,Family',
          'LimitFrom': '0',
          'LimitCount': '5',
          'submit': 'Submit',
        },
      );
      final decoded = _decode(raw);
      final records = SibPackageInsight.creditRecords(decoded);
      Map<String, dynamic>? source;
      for (final record in records) {
        final found = '${record['username'] ?? record['Username'] ?? record['UserName'] ?? ''}'.trim();
        if (found.toLowerCase() == user.toLowerCase()) {
          source = record;
          break;
        }
      }
      if (source == null && records.length == 1) source = records.first;
      if (source == null) return null;
      final fields = source.map((key, value) => MapEntry(key, '$value'));
      return SibPackageInsight.readPersonName(fields);
    } catch (e) {
      debugPrint('[SIB_NAME] $e');
      return null;
    }
  }

  Future<String> _origin() async {
    final id = await _settings.getPackageProvinceId();
    return PackageProvinceX.tryParse(id)?.sibApiOrigin ??
        DeltaSibAuthService.defaultOrigin;
  }

  Future<String> _post(
    String origin,
    String script,
    Map<String, String> fields,
  ) async {
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final uri = Uri.parse('$base/test/webservice/api/restfull/$script');
    final request = await SibHttp.client
        .postUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: fields).query);
    final response = await request.close().timeout(const Duration(seconds: 12));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw DeltaSibAuthException('SIB HTTP ${response.statusCode}');
    }
    return extractResultCell(text) ?? text;
  }

  static String? extractResultCell(String html) {
    final cell = RegExp(
      r'Result</td>\s*<td[^>]*>(.*?)</td>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (cell != null) {
      final cleaned = _cleanHtml(cell.group(1)!);
      return _jsonSlice(cleaned) ?? cleaned;
    }

    final resultAt = html.toLowerCase().lastIndexOf('result');
    final region = resultAt >= 0 ? html.substring(resultAt) : html;
    final pres = RegExp(
      r'<pre[^>]*>(.*?)</pre>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(region);
    for (final match in pres) {
      final json = _jsonSlice(_cleanHtml(match.group(1)!));
      if (json != null) return json;
    }
    final loose = _jsonSlice(_cleanHtml(region));
    if (loose != null) return loose;
    if (html.toLowerCase().contains('invalid token')) return html;
    return null;
  }

  static String _cleanHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static String? _jsonSlice(String text) {
    final objectAt = text.indexOf('{');
    final arrayAt = text.indexOf('[');
    if (objectAt < 0 && arrayAt < 0) return null;
    final start = objectAt < 0
        ? arrayAt
        : (arrayAt < 0 || objectAt < arrayAt)
            ? objectAt
            : arrayAt;
    final endChar = text[start] == '{' ? '}' : ']';
    final end = text.lastIndexOf(endChar);
    if (end <= start) return null;
    final slice = text.substring(start, end + 1).trim();
    try {
      jsonDecode(slice);
      return slice;
    } catch (_) {
      return null;
    }
  }

  static Object? _decode(String raw) {
    final extracted = extractResultCell(raw) ?? raw.trim();
    final text = extracted.trim();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return jsonDecode(text);
      } catch (_) {}
    }
    if (text.contains('<') && text.length > 180) return null;
    return text;
  }
}

class SibCustomerSnapshot {
  const SibCustomerSnapshot({
    required this.username,
    required this.credit,
    required this.status,
    required this.services,
  });

  final String username;
  final Object? credit;
  final Object? status;
  final Object? services;
}
