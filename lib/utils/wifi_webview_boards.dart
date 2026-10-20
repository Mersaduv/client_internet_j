/// Exact Type / Model pairs that use the CPE WiFi WebView at http://10.10.10.2/
class WifiWebViewBoardEntry {
  const WifiWebViewBoardEntry({
    required this.types,
    required this.model,
  });

  /// RouterOS board-name / product type labels.
  final List<String> types;
  final String model;
}

/// Catalog — must match product list exactly (no extra boards).
const List<WifiWebViewBoardEntry> kWifiWebViewBoardCatalog = [
  WifiWebViewBoardEntry(types: ['LHG5', 'RBLHG-5nD'], model: 'RBLHG-5nD'),
  WifiWebViewBoardEntry(types: ['SXTsq lite5'], model: 'RBSXTsq5nD'),
  WifiWebViewBoardEntry(types: ['SXT Lite5'], model: 'SXT 5nD r2'),
  WifiWebViewBoardEntry(types: ['LHG5 ac'], model: 'RBLHGG-5acD'),
  WifiWebViewBoardEntry(types: ['QRT 5'], model: '911G-5HPnD'),
  WifiWebViewBoardEntry(types: ['QRT 5 ac'], model: '911G-5HPacD'),
  WifiWebViewBoardEntry(types: ['LHG-5 XL'], model: 'RBLHGG-5acD'),
  WifiWebViewBoardEntry(types: ['SEXTANT 5'], model: '911G-5HPnD'),
  WifiWebViewBoardEntry(types: ['SXT 6'], model: 'RBSXTG-6HPnD'),
];

String normalizeWifiBoardKey(String? value) {
  return (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _wifiFieldMatchesCatalog(String raw) {
  final norm = normalizeWifiBoardKey(raw);
  if (norm.isEmpty || norm == 'unknown') return false;

  for (final entry in kWifiWebViewBoardCatalog) {
    final entryModel = normalizeWifiBoardKey(entry.model);
    if (entryModel.isNotEmpty &&
        (norm == entryModel || norm.contains(entryModel))) {
      return true;
    }
    for (final type in entry.types) {
      final entryType = normalizeWifiBoardKey(type);
      if (entryType.isNotEmpty &&
          (norm == entryType || norm.contains(entryType))) {
        return true;
      }
    }
  }

  // نام‌های واقعی RouterOS اغلب فاصله یا پسوند دارند: «LHG 5»، «RBLHG-5nD».
  const families = ['lhg', 'sxt', 'qrt', 'sextant'];
  for (final family in families) {
    if (norm.contains(family)) return true;
  }
  return false;
}

/// True when [routerInfo] is an antenna whose Wi‑Fi page is http://10.10.10.2/.
bool isWifiWebViewBoard(Map<String, dynamic>? routerInfo) {
  if (routerInfo == null) return false;
  final fields = [
    routerInfo['board-name'],
    routerInfo['model'],
    routerInfo['board'],
    routerInfo['identity'],
    routerInfo['platform'],
  ];
  for (final field in fields) {
    if (_wifiFieldMatchesCatalog(field?.toString() ?? '')) return true;
  }
  return false;
}
