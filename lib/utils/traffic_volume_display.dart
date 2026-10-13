/// Human-readable cumulative traffic volume (bytes) — separate from live bps.
abstract final class TrafficVolumeDisplay {
  static String compact(int? bytes, {required bool measured}) {
    if (bytes == null) {
      return measured ? '0 B' : '—';
    }
    return _label(bytes);
  }

  static String pair({
    required int? rxBytes,
    required int? txBytes,
    required bool measured,
  }) {
    final down = compact(rxBytes, measured: measured);
    final up = compact(txBytes, measured: measured);
    if (!measured && down == '—' && up == '—') {
      return '—';
    }
    return '↓ $down  ·  ↑ $up';
  }

  static String _label(int bytes) {
    if (bytes < 0) {
      return '0 B';
    }
    if (bytes < 1000) {
      return '$bytes B';
    }
    if (bytes < 1000 * 1000) {
      return '${(bytes / 1000).toStringAsFixed(bytes < 10 * 1000 ? 1 : 0)} KB';
    }
    if (bytes < 1000 * 1000 * 1000) {
      final mb = bytes / (1000 * 1000);
      return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    }
    final gb = bytes / (1000 * 1000 * 1000);
    return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
  }
}
