/// تشخیص میزبان خصوصی/محلی برای سیاست cleartext فروشگاه‌ها.
abstract final class PrivateNetworkHost {
  /// RFC1918 + loopback — فقط این‌ها مجاز به HTTP بدون TLS هستند.
  static bool isPrivateOrLocal(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1') {
      return true;
    }

    final parts = normalized.split('.');
    if (parts.length != 4) return false;

    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if (a == null || b == null || c == null || d == null) return false;
    if ([a, b, c, d].any((octet) => octet < 0 || octet > 255)) return false;

    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 127) return true;
    return false;
  }
}
