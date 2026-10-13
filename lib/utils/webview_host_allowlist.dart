import '../data/internet_packages_data.dart';
import 'private_network_host.dart';
import 'wifi_panel_url_resolver.dart';

/// Hostهای مجاز WebView برای پنل ISP و CPE — مطابق سیاست فروشگاه‌ها.
///
/// قاعده امنیتی:
/// - فقط میزبان‌های allowlist
/// - HTTP فقط برای شبکه خصوصی/محلی
/// - میزبان‌های عمومی فقط HTTPS
class WebViewHostAllowlist {
  WebViewHostAllowlist._();

  static final Set<String> _hosts = {
    for (final province in PackageProvince.values)
      Uri.parse(province.servicePanelUrl).host.toLowerCase(),
    Uri.parse(WifiPanelUrlResolver.cpeWifiPanelUrl).host.toLowerCase(),
    // HTTPS عمومی پایدار (Cloudflare Workers)
    'jb-herat.mersadkarimi001.workers.dev',
    'jb-nimroz.mersadkarimi001.workers.dev',
    'jb-farah.mersadkarimi001.workers.dev',
    // پنل‌های LAN ولایتی
    '192.168.12.12',
    '192.168.10.10',
  };

  static Set<String> get allowedHosts => Set.unmodifiable(_hosts);

  /// آیا این URL برای بارگذاری/ناوبری داخل WebView مجاز است؟
  static bool isAllowedUrl(String? rawUrl) {
    if (rawUrl == null) return false;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;

    final lower = trimmed.toLowerCase();
    if (lower == 'about:blank') return true;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    return isAllowedUri(uri);
  }

  static bool isAllowedUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (!_hosts.contains(host)) return false;

    // Public hosts must use TLS — no cleartext over the internet.
    if (scheme == 'http' && !PrivateNetworkHost.isPrivateOrLocal(host)) {
      return false;
    }
    return true;
  }
}
