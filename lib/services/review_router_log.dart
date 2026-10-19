import 'package:flutter/foundation.dart';

/// One simulated RouterOS API exchange, visible in the review API log.
class ReviewRouterLogEntry {
  final DateTime at;
  final List<String> command;
  final int rowCount;
  final String detail;
  final String label;

  const ReviewRouterLogEntry({
    required this.at,
    required this.command,
    required this.rowCount,
    required this.detail,
    this.label = 'RouterOS simulated',
  });

  String get commandPath => command.isEmpty ? '(empty)' : command.first;

  /// Local date and time, newest entries stay unambiguous for reviewers.
  String get stamp {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        '  ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

/// In-app and debug log of RouterOS sentences executed for jb.admin only.
class ReviewRouterLog extends ChangeNotifier {
  ReviewRouterLog._();

  static final ReviewRouterLog instance = ReviewRouterLog._();

  static const int _maxEntries = 200;

  final List<ReviewRouterLogEntry> entries = <ReviewRouterLogEntry>[];
  final Map<String, DateTime> _throttledAt = <String, DateTime>{};

  void clear() {
    entries.clear();
    _throttledAt.clear();
    notifyListeners();
  }

  void record({
    required List<String> command,
    required List<Map<String, String>> rows,
    required String note,
    Duration? throttle,
    String? throttleKey,
  }) {
    if (throttle != null && throttleKey != null) {
      final last = _throttledAt[throttleKey];
      final now = DateTime.now();
      if (last != null && now.difference(last) < throttle) {
        return;
      }
      _throttledAt[throttleKey] = now;
    }

    final safeCommand = command.map(_redactWord).toList(growable: false);
    final preview = rows.take(6).map(_formatRow).join('\n');
    final detail = StringBuffer()
      ..writeln(note)
      ..writeln('!done  rows=${rows.length}');
    if (preview.isNotEmpty) {
      detail.writeln(preview);
    }
    if (rows.length > 6) {
      detail.writeln('… ${rows.length - 6} more rows');
    }

    final entry = ReviewRouterLogEntry(
      at: DateTime.now(),
      command: safeCommand,
      rowCount: rows.length,
      detail: detail.toString().trimRight(),
      label: 'RouterOS simulated',
    );
    entries.add(entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }

    final buffer = StringBuffer()
      ..writeln(
        '[REVIEW_SIM] RouterOS API  account=${ReviewDemoAccountName.username}  '
        'transport=simulated  socket=none',
      );
    for (final word in safeCommand) {
      buffer.writeln('  $word');
    }
    buffer.writeln(entry.detail);
    debugPrint(buffer.toString());
    notifyListeners();
  }

  /// Live HTTP exchange (DeltaSIB). Shown with the same newest-first log.
  void recordNote({
    required String label,
    required String body,
    List<String> lines = const [],
  }) {
    final entry = ReviewRouterLogEntry(
      at: DateTime.now(),
      command: lines,
      rowCount: 0,
      detail: body.trimRight(),
      label: label,
    );
    entries.add(entry);
    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }
    debugPrint('[REVIEW_LOG] ${entry.stamp}  $label\n${entry.detail}');
    notifyListeners();
  }

  static String _redactWord(String word) {
    const secretKeys = <String>[
      'password',
      'wpa-pre-shared-key',
      'wpa2-pre-shared-key',
      'pre-shared-key',
      'secret',
    ];
    if (!word.startsWith('=')) {
      return word;
    }
    final body = word.substring(1);
    final split = body.indexOf('=');
    if (split <= 0) {
      return word;
    }
    final key = body.substring(0, split).toLowerCase();
    if (secretKeys.any(key.contains) ||
        (key == 'source' && body.toLowerCase().contains('pre-shared-key'))) {
      return '=${body.substring(0, split)}=<redacted>';
    }
    return word;
  }

  static String _formatRow(Map<String, String> row) {
    final id = row['.id'] ?? row['ret'] ?? '';
    final address = row['address'] ?? row['src-address'] ?? row['target'] ?? '';
    final name = row['host-name'] ?? row['name'] ?? row['comment'] ?? '';
    return '  .id=$id  $address  $name'.trim();
  }
}

/// Shortens a DeltaSIB body and hides token / password values.
String redactSibBody(String body) {
  var value = body.replaceAll(
    RegExp(r'"token"\s*:\s*"[^"]*"', caseSensitive: false),
    '"token":"<redacted>"',
  );
  value = value.replaceAll(
    RegExp(r'(Api_Password=)[^&\s]+'),
    r'$1<redacted>',
  );
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length > 700) {
    value = '${value.substring(0, 700)}…';
  }
  return value;
}

/// Avoids a circular import: log only needs the account name string.
abstract final class ReviewDemoAccountName {
  static const String username = 'jb.admin';
}
