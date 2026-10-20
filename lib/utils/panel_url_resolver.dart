import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/internet_packages_data.dart';
import 'webview_host_allowlist.dart';

/// انتخاب بهترین URL پنل با health-check و failover چندمنبعی.
///
/// سیاست فروشگاه: میزبان عمومی فقط HTTPS؛ LAN می‌تواند HTTP باشد.
class PanelUrlResolver {
  PanelUrlResolver._();

  static const Duration _probeTimeout = Duration(seconds: 4);

  /// کاندیدها به‌ترتیب اولویت (اولین سالم برنده است).
  static List<String> candidatesFor(PackageProvince province) {
    switch (province) {
      case PackageProvince.herat:
      case PackageProvince.farah:
        return const [
          'https://jb-herat.mersadkarimi001.workers.dev/users/',
        ];
      case PackageProvince.nimroz:
        return const [
          'https://jb-nimroz.mersadkarimi001.workers.dev/users/',
        ];
    }
  }

  static String primaryFor(PackageProvince province) {
    final list = _allowed(candidatesFor(province));
    return list.isNotEmpty ? list.first : province.servicePanelUrl;
  }

  /// کاندید بعدی بعد از [current]؛ اگر نباشد null.
  static String? nextAfter(PackageProvince province, String current) {
    final list = _allowed(candidatesFor(province));
    final idx = list.indexWhere(
      (u) => _norm(u) == _norm(current),
    );
    if (idx < 0) return list.isEmpty ? null : list.first;
    if (idx + 1 >= list.length) return null;
    return list[idx + 1];
  }

  static Future<String> resolveBest(PackageProvince province) async {
    final allowed = _allowed(candidatesFor(province));
    if (allowed.isEmpty) return province.servicePanelUrl;

    for (final url in allowed) {
      if (await isHealthy(url)) return url;
    }
    return allowed.first;
  }

  static Future<bool> isHealthy(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _probeTimeout;
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri).timeout(_probeTimeout);
      req.headers.set(HttpHeaders.userAgentHeader, 'JahanBit-PanelProbe/1.0');
      final res = await req.close().timeout(_probeTimeout);
      final code = res.statusCode;
      if (code == 530 ||
          code == 502 ||
          code == 503 ||
          code == 403 ||
          code >= 500) {
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(_probeTimeout);
        if (looksLikeCloudflareEdgeFailure(body) || code >= 400) {
          return false;
        }
      }
      await res.drain<void>();
      return code < 400 || code == 401;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  static bool looksLikeCloudflareEdgeFailure(String? htmlOrText) {
    if (htmlOrText == null || htmlOrText.isEmpty) return false;
    return htmlOrText.contains('error code: 1016') ||
        htmlOrText.contains('error code: 1033') ||
        htmlOrText.contains('error code: 1003') ||
        htmlOrText.contains('error code: 1042') ||
        htmlOrText.contains('Cloudflare');
  }

  static List<String> _allowed(List<String> urls) =>
      urls.where(WebViewHostAllowlist.isAllowedUrl).toList(growable: false);

  static String _norm(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '');
}
