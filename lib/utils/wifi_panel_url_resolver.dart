/// Fixed HTTP URL for legacy CPE WiFi panels (LHG, SXT, QRT, …).
///
/// WebView boards must always use [cpeWifiPanelUrl] — not router API host
/// and not 10.10.10.1.
class WifiPanelUrlResolver {
  WifiPanelUrlResolver._();

  static const String cpeWifiPanelUrl = 'http://10.10.10.2/';

  /// میزبان پنل وای‌فای آنتن، با یا بدون اسکیما و پورت.
  static bool isCpeHost(String? value) {
    if (value == null) return false;
    var text = value.trim().toLowerCase();
    if (text.isEmpty) return false;
    text = text.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    text = text.split('/').first.split('?').first;
    if (text.startsWith('[')) return false;
    text = text.split(':').first;
    return text == '10.10.10.2';
  }

  /// Sole URL for CPE WiFi WebView (no fallbacks).
  static Future<String> resolve() async => cpeWifiPanelUrl;

  static Future<List<String>> buildCandidates() async => [cpeWifiPanelUrl];
}
