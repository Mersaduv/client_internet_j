/// تشخیص نوع بستهٔ دلتاسیب از فیلدهای creditinfo.
enum SibPackageKind { volume, unlimited }

class SibDetailRow {
  const SibDetailRow(this.label, this.value);

  final String label;
  final String value;
}

class SibDetailGroup {
  const SibDetailGroup(this.title, this.rows);

  final String title;
  final List<SibDetailRow> rows;
}

class SibPackageInsight {
  const SibPackageInsight({
    required this.kind,
    required this.title,
    required this.fields,
    this.totalBytes,
    this.usedBytes,
    this.remainBytes,
    this.dailyBytes,
    this.dailyUsedBytes,
    this.notePrimary,
    this.noteSecondary,
    this.serviceName,
    this.statusLabel,
    this.start,
    this.end,
    this.startText,
    this.endText,
    this.totalDays,
    this.usedDays,
  });

  final SibPackageKind kind;
  final String title;
  final Map<String, String> fields;
  final int? totalBytes;
  final int? usedBytes;
  final int? remainBytes;
  final int? dailyBytes;
  final int? dailyUsedBytes;
  final String? notePrimary;
  final String? noteSecondary;
  final String? serviceName;
  final String? statusLabel;
  final DateTime? start;
  final DateTime? end;
  final String? startText;
  final String? endText;
  final int? totalDays;
  final int? usedDays;

  String get detectionLabel {
    if (kind == SibPackageKind.unlimited) return 'بسته نامحدود';
    if (dailyBytes != null) return 'بسته حجمی با سقف روزانه';
    return 'بسته حجمی';
  }

  String? get customerName => readPersonName(fields);

  static String greetingLine(String? name) {
    final clean = (name ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'سلام وقت بخیر';
    return 'سلام $clean وقت بخیر';
  }

  static String? readPersonName(Map<String, String>? source) {
    if (source == null || source.isEmpty) return null;
    final fields = <String, String>{};
    for (final entry in source.entries) {
      final value = entry.value.trim();
      if (value.isEmpty || value == 'null') continue;
      fields[entry.key.toLowerCase()] = value;
    }
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = fields[key.toLowerCase()];
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final full = pick(['fullname', 'realname', 'displayname']);
    if (full != null) return full;
    final parts = [
      pick(['name', 'firstname', 'fname']),
      pick(['family', 'lastname', 'lname']),
    ].whereType<String>();
    final text = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  String get heroLabel {
    final name = serviceName;
    if (name != null && name.isNotEmpty && name != title) return name;
    if (kind == SibPackageKind.volume && totalBytes != null) {
      return SibPackageInsight.formatBytes(totalBytes, compact: true);
    }
    return title;
  }

  /// سهم مانده از حجم، و اگر حجم نباشد سهم مانده از زمان.
  double get remainingRatio {
    final total = totalBytes;
    final remain = remainBytes;
    if (total != null && total > 0 && remain != null) {
      return (remain / total).clamp(0, 1);
    }
    final days = totalDays;
    final spent = usedDays;
    if (days != null && days > 0 && spent != null) {
      return ((days - spent) / days).clamp(0, 1);
    }
    return 0;
  }

  double get usageRatio {
    final total = totalBytes;
    final used = usedBytes;
    if (total != null && total > 0 && used != null) {
      return (used / total).clamp(0, 1);
    }
    final days = totalDays;
    final spent = usedDays;
    if (days != null && days > 0 && spent != null) {
      return (spent / days).clamp(0, 1);
    }
    return 0;
  }

  static List<Map<String, dynamic>> creditRecords(Object? credit) {
    final list = <Map<String, dynamic>>[];
    void add(Object? value) {
      final map = asMap(value);
      if (map == null) return;
      final unwrapped = _unwrap(map);
      if (unwrapped != null && !looksLikeError(unwrapped)) list.add(unwrapped);
    }

    if (credit is List) {
      for (final item in credit) {
        add(item);
      }
    } else {
      add(credit);
    }
    list.sort((a, b) => _statusRank(a).compareTo(_statusRank(b)));
    return list;
  }

  static bool looksLikeError(Map<String, dynamic> map) {
    final keys = map.keys.map((key) => key.toLowerCase()).toSet();
    final hasPackage = keys.contains('servicename') ||
        keys.contains('stra') ||
        keys.contains('startdate') ||
        keys.contains('service_name');
    if (hasPackage) return false;
    return keys.contains('error') ||
        keys.contains('errorcode') ||
        keys.contains('errormessage') ||
        keys.contains('message');
  }

  static String? errorText(Object? value) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text.startsWith('{') || text.startsWith('[')) return null;
      if (text.contains('<')) return 'پاسخ سرویس خوانده نشد. دوباره تلاش کنید.';
      return text;
    }
    final map = asMap(value);
    if (map == null || !looksLikeError(map)) return null;
    for (final key in ['Message', 'ErrorMessage', 'Error', 'error']) {
      final item = map[key];
      final text = item == null ? '' : '$item'.trim();
      if (text.isNotEmpty && text != 'null' && text != '0') return text;
    }
    return 'پاسخ سرویس بسته نامعتبر است.';
  }

  static Map<String, dynamic>? asMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
    return null;
  }

  static SibPackageInsight fromMaps({
    Map<String, dynamic>? credit,
    Map<String, dynamic>? status,
  }) {
    final fields = <String, String>{};
    void take(Map<String, dynamic>? source) {
      if (source == null) return;
      for (final entry in source.entries) {
        final value = _scalar(entry.value);
        if (value == null) continue;
        fields[entry.key] = value;
      }
    }

    take(asMap(status));
    take(credit);

    final name = fields['ServiceName'] ?? '';
    final quotas = <String, int?>{
      'S': _bytes(fields['STrA']),
      'Y': _bytes(fields['YTrA']),
      'M': _bytes(fields['MTrA']),
      'W': _bytes(fields['WTrA']),
      'E': _bytes(fields['ETrA']),
    };
    String? quotaKey;
    int? total;
    for (final entry in quotas.entries) {
      final positive = _positive(entry.value);
      if (positive != null) {
        quotaKey = entry.key;
        total = positive;
        break;
      }
    }

    int? used = quotaKey == null ? null : _bytes(fields['${quotaKey}TrU']);
    int? remain = quotaKey == null ? null : _bytes(fields['${quotaKey}TrR']);
    if (total != null && used == null && remain != null) {
      used = (total - remain).clamp(0, total);
    }
    if (total != null && remain == null && used != null) {
      remain = (total - used).clamp(0, total);
    }

    final dailyTotal = _positive(_bytes(fields['DTrA']));
    final dailyUsed = _bytes(fields['DTrU']);
    final kind = total == null ? SibPackageKind.unlimited : SibPackageKind.volume;

    final start = _date(fields['StartDate']);
    final end = _date(fields['EndDate']);
    final current = _date(fields['CurrentDT']);
    int? totalDays;
    int? usedDays;
    if (start != null && end != null && !end.isBefore(start)) {
      totalDays = end.difference(start).inDays;
    } else {
      totalDays = _periodDays(fields['Period']) ?? _daysFromSeconds(fields['STiA']);
    }
    if (start != null) {
      final cursor = current ?? DateTime.now();
      usedDays = cursor.difference(start).inDays;
      if (usedDays < 0) usedDays = 0;
      if (totalDays != null && usedDays > totalDays) usedDays = totalDays;
    } else {
      usedDays = _daysFromSeconds(fields['STiU']);
      if (usedDays != null && totalDays != null && usedDays > totalDays) {
        usedDays = totalDays;
      }
    }

    final fairRate = fields['FairMikrotikRate'] ?? fields['FairRate'];
    final rateLabel = (fairRate == null || fairRate == 'null' || fairRate == '0')
        ? _speedFromName(name)
        : formatRate(fairRate);
    final gift = _positive(
      _bytes(fields['GiftExtraTr']) ?? _bytes(fields['GiftTraffic']),
    );
    String? notePrimary;
    final noteAmount = gift ?? (rateLabel == null ? null : dailyTotal);
    if (noteAmount != null) {
      final amount = formatBytes(noteAmount, compact: true);
      notePrimary = dailyTotal == null
          ? '$amount رایگان'
          : '$amount رایگان بعد از تمام شدن محدودیت روزانه';
    }
    final noteSecondary =
        (rateLabel == null || rateLabel.isEmpty || rateLabel == '0')
            ? null
            : rateLabel;

    return SibPackageInsight(
      kind: kind,
      title: kind == SibPackageKind.unlimited ? 'اینترنت نامحدود' : 'حجم اینترنت',
      fields: fields,
      totalBytes: total,
      usedBytes: used,
      remainBytes: remain,
      dailyBytes: dailyTotal,
      dailyUsedBytes: dailyUsed,
      notePrimary: notePrimary,
      noteSecondary: noteSecondary,
      serviceName: name.isEmpty ? null : name,
      statusLabel: _statusLabel(fields),
      start: start,
      end: end,
      startText: _dateText(fields['StartDate'], start),
      endText: _dateText(fields['EndDate'], end),
      totalDays: totalDays,
      usedDays: usedDays,
    );
  }

  List<SibDetailGroup> detailGroups() {
    const sections = <String, List<String>>{
      'وضعیت': [
        'ServiceStatus',
        'Status_Name',
        'ServiceName',
        'Username',
        'Name',
        'Family',
        'CurrentDT',
      ],
      'زمان': [
        'StartDate',
        'EndDate',
        'Period',
        'STiA',
        'STiU',
        'STiR',
        'GiftEndDT',
      ],
      'حجم': [
        'STrA',
        'STrU',
        'STrR',
        'DTrA',
        'DTrU',
        'DTrR',
        'MTrA',
        'MTrU',
        'MTrR',
        'WTrA',
        'WTrU',
        'WTrR',
        'YTrA',
        'YTrU',
        'YTrR',
        'ETrA',
        'ETrU',
        'ETrR',
        'RealReceiveTr',
        'RealSendTr',
        'GiftExtraTr',
        'GiftTraffic',
        'FairMikrotikRate',
        'ISFairService',
      ],
    };
    final used = <String>{};
    final groups = <SibDetailGroup>[];
    for (final section in sections.entries) {
      final rows = <SibDetailRow>[];
      for (final key in section.value) {
        final raw = fields[key];
        if (raw == null) continue;
        used.add(key);
        rows.add(SibDetailRow(_label(key), formatField(key, raw)));
      }
      if (rows.isNotEmpty) groups.add(SibDetailGroup(section.key, rows));
    }
    final rest = <SibDetailRow>[];
    for (final entry in fields.entries) {
      if (used.contains(entry.key)) continue;
      rest.add(SibDetailRow(_label(entry.key), formatField(entry.key, entry.value)));
    }
    if (rest.isNotEmpty) groups.add(SibDetailGroup('سایر', rest));
    return groups;
  }

  static String formatField(String key, String raw) {
    if (_isUnlimitedMark(raw)) return 'نامحدود';
    final lower = raw.toLowerCase();
    if (key == 'ServiceStatus' || key == 'Status_Name' || key == 'ISFairService') {
      return _statusWord(raw);
    }
    if (key == 'FairMikrotikRate' || key == 'FairRate') return formatRate(raw);
    if (key.endsWith('Date') || key.endsWith('DT')) {
      return _dateText(raw, _date(raw)) ?? '—';
    }
    if (_isTrafficKey(key)) {
      final bytes = _bytes(raw);
      if (bytes != null) return formatBytes(bytes);
    }
    if (_isTimeKey(key)) {
      final seconds = int.tryParse(raw.split('.').first);
      if (seconds != null) return _formatDuration(seconds);
    }
    if (lower == 'yes') return 'بله';
    if (lower == 'no') return 'خیر';
    return raw;
  }

  static String formatBytes(int? value, {bool compact = false}) {
    if (value == null) return '—';
    final gap = compact ? '' : ' ';
    if (value == 0) return compact ? '0GB' : '0 B';
    if (value < 1024) return '$value${gap}B';
    final kb = value / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)}${gap}KB';
    final mb = kb / 1024;
    if (mb < 1024) {
      final digits = mb >= 100 ? 0 : 1;
      return '${_trim(mb.toStringAsFixed(digits))}${gap}MB';
    }
    final gb = mb / 1024;
    final digits = gb >= 10 ? 0 : 1;
    return '${_trim(gb.toStringAsFixed(digits))}${gap}GB';
  }

  static String formatRate(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '0' || text == 'null') return text;
    if (RegExp(r'bps', caseSensitive: false).hasMatch(text)) return text;
    final mega = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(mb|kb)(?:ps)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (mega != null) {
      final unit = mega.group(2)!.toLowerCase() == 'kb' ? 'Kbps' : 'Mbps';
      return '${_trim(mega.group(1)!)} $unit';
    }
    final kilo = RegExp(r'^(\d+(?:\.\d+)?)\s*[kK]$').firstMatch(text);
    if (kilo != null) return '${_trim(kilo.group(1)!)} Kbps';
    final pair = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(text);
    if (pair != null) {
      return '${formatRate(pair.group(1)!)} / ${formatRate(pair.group(2)!)}';
    }
    final number = num.tryParse(text);
    if (number == null) return text;
    if (number >= 1000000) {
      return '${_trim((number / 1000000).toStringAsFixed(number % 1000000 == 0 ? 0 : 1))} Mbps';
    }
    if (number >= 1000) return '${(number / 1000).round()} Kbps';
    return '${_trim(number.toString())} Kbps';
  }

  static String faDigits(int value) {
    const western = '0123456789';
    const eastern = '۰۱۲۳۴۵۶۷۸۹';
    return '$value'.split('').map((char) {
      final index = western.indexOf(char);
      return index < 0 ? char : eastern[index];
    }).join();
  }

  static int? _bytes(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().replaceAll(',', '').replaceAll(' ', '');
    if (text.isEmpty || text == 'null' || _isUnlimitedMark(text)) return null;
    return int.tryParse(text.split('.').first);
  }

  static int? _positive(int? value) => value != null && value > 0 ? value : null;

  static bool _isUnlimitedMark(String? raw) {
    if (raw == null) return false;
    final text = raw.trim().toUpperCase();
    return text == 'UL' || text == 'UNLIMITED' || text == 'نامحدود';
  }

  static bool _isTrafficKey(String key) {
    return key.endsWith('Tr') ||
        key.endsWith('TrA') ||
        key.endsWith('TrU') ||
        key.endsWith('TrR') ||
        key.endsWith('Traffic');
  }

  static bool _isTimeKey(String key) {
    return key.endsWith('TiA') || key.endsWith('TiU') || key.endsWith('TiR');
  }

  static DateTime? _date(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().replaceAll('/', '-');
    if (text.isEmpty ||
        text == 'null' ||
        text.startsWith('0000') ||
        text.startsWith('0-') ||
        text.contains('00-00')) {
      return null;
    }
    final parsed =
        DateTime.tryParse(text.replaceFirst(' ', 'T')) ?? DateTime.tryParse(text);
    if (parsed == null || parsed.year < 1971) return null;
    return parsed;
  }

  static String? _dateText(String? raw, DateTime? parsed) {
    if (parsed != null) {
      final month = parsed.month.toString().padLeft(2, '0');
      final day = parsed.day.toString().padLeft(2, '0');
      return '${parsed.year}/$month/$day';
    }
    return null;
  }

  static int? _periodDays(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    final plain = int.tryParse(text);
    if (plain != null) return plain;
    int part(String unit) {
      final match = RegExp(
        '(\\d+)\\s*$unit',
        caseSensitive: false,
      ).firstMatch(text);
      return int.tryParse(match?.group(1) ?? '') ?? 0;
    }

    if (!RegExp(r'\d+\s*[YMD]', caseSensitive: false).hasMatch(text)) return null;
    final days = part('Y') * 365 + part('M') * 30 + part('D');
    return days > 0 ? days : null;
  }

  static String? _speedFromName(String name) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(Mbps|Kbps|Mb|Kb)\b',
      caseSensitive: false,
    ).firstMatch(name);
    if (match == null) return null;
    return formatRate('${match.group(1)}${match.group(2)}');
  }

  static int? _daysFromSeconds(String? raw) {
    final seconds = int.tryParse((raw ?? '').split('.').first);
    if (seconds == null || seconds <= 0) return null;
    return seconds ~/ 86400;
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '۰';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    if (days > 0 && hours == 0) return '${faDigits(days)} روز';
    if (days > 0) return '${faDigits(days)} روز و ${faDigits(hours)} ساعت';
    if (hours > 0) return '${faDigits(hours)} ساعت';
    final minutes = seconds ~/ 60;
    return '${faDigits(minutes)} دقیقه';
  }

  static String _statusWord(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
      case 'enable':
      case 'enabled':
      case 'online':
      case 'yes':
        return 'فعال';
      case 'expire':
      case 'expired':
        return 'منقضی';
      case 'disable':
      case 'disabled':
      case 'no':
        return 'غیرفعال';
      case 'wait':
        return 'در انتظار';
      default:
        return raw;
    }
  }

  static String? _statusLabel(Map<String, String> fields) {
    final service = fields['ServiceStatus'];
    if (service != null) return _statusWord(service);
    final user = fields['Status_Name'];
    if (user != null) return _statusWord(user);
    return null;
  }

  static int _statusRank(Map<String, dynamic> map) {
    final status = '${map['ServiceStatus'] ?? ''}'.toLowerCase();
    return status == 'active' ? 0 : 1;
  }

  static Map<String, dynamic>? _unwrap(Map<String, dynamic> map) {
    for (final key in ['data', 'Data', 'Result', 'record', 'user']) {
      final inner = map[key];
      final innerMap = asMap(inner);
      if (innerMap != null && innerMap.length > 1) return innerMap;
      if (inner is List && inner.isNotEmpty) {
        final first = asMap(inner.first);
        if (first != null) return first;
      }
    }
    return map;
  }

  static String? _scalar(Object? value) {
    if (value == null) return null;
    if (value is Map || value is List) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static String _trim(String value) {
    return value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
  }

  static String _label(String key) {
    const labels = <String, String>{
      'ServiceStatus': 'وضعیت سرویس',
      'ServiceName': 'نام سرویس',
      'StartDate': 'شروع',
      'EndDate': 'پایان',
      'CurrentDT': 'زمان سرور',
      'Period': 'دوره',
      'Status_Name': 'وضعیت کاربر',
      'Username': 'نام کاربری',
      'Name': 'نام',
      'Family': 'تخلص',
      'STrA': 'حجم سرویس',
      'STrU': 'مصرف سرویس',
      'STrR': 'باقی‌مانده سرویس',
      'DTrA': 'سقف روزانه',
      'DTrU': 'مصرف روزانه',
      'DTrR': 'باقی‌مانده روزانه',
      'MTrA': 'حجم ماهانه',
      'MTrU': 'مصرف ماهانه',
      'MTrR': 'باقی‌مانده ماهانه',
      'WTrA': 'حجم هفتگی',
      'WTrU': 'مصرف هفتگی',
      'WTrR': 'باقی‌مانده هفتگی',
      'YTrA': 'حجم سالانه',
      'YTrU': 'مصرف سالانه',
      'YTrR': 'باقی‌مانده سالانه',
      'ETrA': 'حجم اضافه',
      'ETrU': 'مصرف اضافه',
      'ETrR': 'باقی‌مانده اضافه',
      'STiA': 'زمان سرویس',
      'STiU': 'زمان مصرف‌شده',
      'STiR': 'زمان باقی‌مانده',
      'RealReceiveTr': 'دریافت واقعی',
      'RealSendTr': 'ارسال واقعی',
      'GiftExtraTr': 'حجم هدیه',
      'GiftTraffic': 'ترافیک هدیه',
      'GiftEndDT': 'پایان هدیه',
      'FairMikrotikRate': 'سرعت بعد از سقف',
      'ISFairService': 'حالت منصفانه',
    };
    return labels[key] ?? key;
  }
}
