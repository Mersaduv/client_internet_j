import 'dart:convert';
import 'dart:io';

import 'deltasib_auth_service.dart';
import 'review_demo_account.dart';
import 'review_router_log.dart';
import 'sib_http.dart';

/// حجم یک مشترک. ورکر با یوزر Api سرور فقط همین نام کاربری را می‌خواند.
class SibVolume {
  const SibVolume({required this.username, this.name, this.credit});

  final String username;
  final String? name;
  final Map<String, dynamic>? credit;
}

class SibVolumeClient {
  SibVolumeClient._();

  static Future<SibVolume>? _inflight;
  static String? _inflightKey;

  static Future<SibVolume> fetch({
    required String username,
    required String origin,
  }) {
    final user = username.trim();
    final key = '$origin|$user';
    final current = _inflight;
    if (current != null && _inflightKey == key) return current;
    late final Future<SibVolume> tracked;
    tracked = _request(username: user, origin: origin).whenComplete(() {
      if (identical(_inflight, tracked)) {
        _inflight = null;
        _inflightKey = null;
      }
    });
    _inflight = tracked;
    _inflightKey = key;
    return tracked;
  }

  static Future<SibVolume> _request({
    required String username,
    required String origin,
  }) async {
    final user = username.trim();
    if (user.isEmpty) {
      throw DeltaSibAuthException('نام کاربری مشترک خالی است.');
    }
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final uri = Uri.parse('$base/jahanbit/sib/volume');
    final review = user == ReviewDemoAccount.username;
    final session = await DeltaSibAuthService().savedSession();
    if (session == null || session.isEmpty) {
      throw DeltaSibAuthException('برای دیدن حجم، کد ورود را یک‌بار وارد کنید.');
    }

    try {
      final request = await SibHttp.client
          .postUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.write(jsonEncode({'username': user, 'session': session}));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      if (review) {
        ReviewRouterLog.instance.recordNote(
          label: 'DeltaSIB live',
          lines: [
            'POST $uri',
            'username=$user',
          ],
          body: 'HTTP ${response.statusCode}\n${redactSibBody(text)}',
        );
      }
      if (response.statusCode != 200) {
        throw DeltaSibAuthException(
          _errorFromBody(text, response.statusCode),
          sessionExpired: _sessionExpired(text, response.statusCode),
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw DeltaSibAuthException('پاسخ حجم مشترک نامعتبر است.');
      }
      final error = decoded['error']?.toString();
      if (error != null && error.isNotEmpty) {
        throw DeltaSibAuthException(error);
      }
      final creditRaw = decoded['credit'];
      Map<String, dynamic>? credit;
      if (creditRaw is Map) {
        credit = creditRaw.map((key, value) => MapEntry('$key', value));
      }
      final name = decoded['name']?.toString().trim();
      return SibVolume(
        username: user,
        name: (name == null || name.isEmpty) ? null : name,
        credit: credit,
      );
    } on DeltaSibAuthException {
      rethrow;
    } catch (e) {
      if (review) {
        ReviewRouterLog.instance.recordNote(
          label: 'DeltaSIB live',
          lines: [
            'POST $uri',
            'username=$user',
          ],
          body: 'FAILED  $e',
        );
      }
      throw DeltaSibAuthException('حجم مشترک خوانده نشد: $e');
    }
  }

  static Object? sibDecodePayload(String html) {
    final extracted = sibExtractResultCell(html);
    if (extracted == null || extracted.isEmpty) return null;
    try {
      return jsonDecode(extracted);
    } catch (_) {
      return null;
    }
  }

  static bool _sessionExpired(String text, int status) {
    if (status != 401) return false;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['code'] == 'session_expired') return true;
    } catch (_) {}
    return true;
  }

  static String _errorFromBody(String text, int status) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return 'حجم مشترک در دسترس نیست (HTTP $status)';
  }
}

String? sibExtractResultCell(String html) {
  final cell = RegExp(
    r'Result</td>\s*<td[^>]*>(.*?)</td>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  if (cell != null) {
    final json = _jsonSlice(_cleanSibHtml(cell.group(1)!));
    if (json != null) return json;
  }

  final resultAt = html.toLowerCase().lastIndexOf('result');
  final region = resultAt >= 0 ? html.substring(resultAt) : html;
  final pres = RegExp(
    r'<pre[^>]*>(.*?)</pre>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(region);
  for (final match in pres) {
    final json = _jsonSlice(_cleanSibHtml(match.group(1)!));
    if (json != null) return json;
  }
  final loose = _jsonSlice(_cleanSibHtml(region));
  if (loose != null) return loose;
  if (html.toLowerCase().contains('invalid token')) return html;
  return null;
}

Map<String, dynamic>? sibCreditRecord(Object? payload) {
  final rows = _sibRows(payload);
  if (rows.isEmpty) return null;
  rows.sort((a, b) {
    final aActive = '${a['ServiceStatus']}'.toLowerCase() == 'active' ? 0 : 1;
    final bActive = '${b['ServiceStatus']}'.toLowerCase() == 'active' ? 0 : 1;
    return aActive.compareTo(bActive);
  });
  final row = rows.first;
  if (row['ServiceName'] == null && row['STrA'] == null && row['STrR'] == null) {
    return null;
  }
  return row;
}

String? sibPersonName(Object? payload) {
  final rows = _sibRows(payload);
  if (rows.isEmpty) return null;
  final row = rows.first;
  final name = '${row['Name'] ?? row['name'] ?? ''}'.trim();
  final family = '${row['Family'] ?? row['family'] ?? ''}'.trim();
  final full = '$name $family'.trim();
  return full.isEmpty ? null : full;
}

List<Map<String, dynamic>> _sibRows(Object? payload) {
  if (payload is List) {
    return payload.whereType<Map>().map(_stringKeyMap).toList();
  }
  if (payload is Map) return [_stringKeyMap(payload)];
  return const [];
}

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> row) {
  return row.map((key, value) => MapEntry('$key', value));
}

String _cleanSibHtml(String raw) {
  return raw
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

String? _jsonSlice(String text) {
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
