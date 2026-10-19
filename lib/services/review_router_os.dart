import '../models/client_traffic_rate.dart';
import '../models/live_traffic_capabilities.dart';

/// In-memory RouterOS that answers the same API sentences as [MikroTikService].
///
/// Used only while the store-review account has no live router session.
class ReviewRouterOs {
  ReviewRouterOs._();

  static final ReviewRouterOs instance = ReviewRouterOs._();

  final Map<String, List<Map<String, String>>> _tables =
      <String, List<Map<String, String>>>{};

  int _nextId = 100;
  bool _seeded = false;

  void reset() {
    _tables.clear();
    _nextId = 100;
    _seeded = false;
  }

  void ensureSeeded() {
    if (_seeded) {
      return;
    }
    _seeded = true;
    _seed();
  }

  List<Map<String, String>> execute(List<String> command) {
    ensureSeeded();
    if (command.isEmpty) {
      return const [];
    }

    final path = command.first;
    final slash = path.lastIndexOf('/');
    if (slash <= 0) {
      return const [];
    }
    final verb = path.substring(slash + 1);
    final table = path.substring(0, slash);
    final words = command.skip(1).toList();

    switch (verb) {
      case 'print':
        return _print(table, words);
      case 'add':
        _add(table, words);
        return const [];
      case 'set':
        _set(table, words);
        return const [];
      case 'remove':
        _remove(table, words);
        return const [];
      case 'make-static':
        _makeStatic(table, words);
        return const [];
      case 'run':
        _run(table, words);
        return const [];
      default:
        return const [];
    }
  }

  void applyScript(String source) {
    ensureSeeded();
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final find = RegExp(r'\[find name="((?:\\.|[^"\\])*)"\]').firstMatch(line);
      if (find == null) {
        continue;
      }
      final name = _unescape(find.group(1) ?? '');
      final head = line.substring(0, line.indexOf('[find')).trim();
      final verbAt = head.lastIndexOf(' ');
      if (verbAt <= 0) {
        continue;
      }
      final verb = head.substring(verbAt + 1).trim();
      final path = head.substring(0, verbAt).trim().split(RegExp(r'\s+')).join('/');
      final rows = _tables.putIfAbsent(path, () => <Map<String, String>>[]);
      if (verb == 'remove') {
        rows.removeWhere((row) => row['name'] == name);
        continue;
      }
      if (verb != 'set') {
        continue;
      }
      final tail = line.substring(find.end).trim();
      final updates = _scriptAssignments(tail);
      for (final row in rows) {
        if (row['name'] == name) {
          updates.forEach((key, value) {
            row[key] = _normalizeFlag(key, value);
          });
        }
      }
    }
  }

  /// Live rates for the home traffic badges. Varies slightly so polls move.
  Map<String, ClientTrafficRate> sampleTraffic(Set<String> trackedIps) {
    ensureSeeded();
    final now = DateTime.now();
    final wobble = (now.second % 7) * 180000;
    final banned = _bannedIps();
    final rates = <String, ClientTrafficRate>{};
    for (final ip in trackedIps) {
      if (banned.contains(ip)) {
        continue;
      }
      final lease = _tables['/ip/dhcp-server/lease']?.any(
            (row) => row['address'] == ip && row['status'] == 'bound',
          ) ??
          false;
      if (!lease) {
        continue;
      }
      final rx = 1800000 + wobble + (ip.hashCode.abs() % 400000);
      final tx = 320000 + (wobble ~/ 5);
      rates[ip] = ClientTrafficRate(
        rxBps: rx,
        txBps: tx,
        sampledAt: now,
        rxBytesTotal: 240000000 + now.second * 1000,
        txBytesTotal: 48000000 + now.second * 200,
        volumeSource: LiveTrafficSource.queueStats,
      );
      _upsertQueue(ip, rx, tx);
    }
    return rates;
  }

  /// Sum of every online lease, including devices the list has not polled yet.
  AggregateLiveTrafficRate networkLiveRate() {
    ensureSeeded();
    final now = DateTime.now();
    final wobble = (now.second % 7) * 180000;
    final banned = _bannedIps();
    var rx = 0;
    var tx = 0;
    var count = 0;
    for (final lease in _tables['/ip/dhcp-server/lease'] ?? const []) {
      if (lease['status'] != 'bound') {
        continue;
      }
      if (lease['block-access'] == 'yes') {
        continue;
      }
      final ip = lease['address']?.trim();
      if (ip == null || ip.isEmpty || banned.contains(ip)) {
        continue;
      }
      rx += 1800000 + wobble + (ip.hashCode.abs() % 400000);
      tx += 320000 + (wobble ~/ 5);
      count++;
    }
    return AggregateLiveTrafficRate(
      rxBps: rx,
      txBps: tx,
      deviceCount: count,
      measured: true,
    );
  }

  void _seed() {
    _tables['/system/resource'] = [
      {
        '.id': '*1',
        'uptime': '3d2h10m',
        'version': '7.15.3',
        'build-time': 'Jun/20/2024 08:22:10',
        'factory-software': '6.49.10',
        'free-memory': '198000000',
        'total-memory': '256000000',
        'cpu': 'ARM',
        'cpu-count': '4',
        'cpu-frequency': '896',
        'cpu-load': '7',
        'free-hdd-space': '100000000',
        'total-hdd-space': '128000000',
        'architecture-name': 'arm',
        'board-name': 'hAP ac^2',
        'platform': 'MikroTik',
      },
    ];
    _tables['/system/routerboard'] = [
      {'.id': '*1', 'board-name': 'hAP ac^2', 'model': 'RBD52G-5HacD2HnD'},
    ];
    _tables['/system/identity'] = [
      {'.id': '*1', 'name': 'JahanBit-Review'},
    ];
    _tables['/ip/pool'] = [
      {'.id': '*1', 'name': 'dhcp'},
      {'.id': '*2', 'name': 'static-only'},
    ];
    _tables['/ip/dhcp-server'] = [
      {
        '.id': '*1',
        'name': 'dhcp1',
        'address-pool': 'dhcp',
        'disabled': 'false',
        'interface': 'bridge',
      },
    ];
    _tables['/ip/route'] = [
      {
        '.id': '*1',
        'dst-address': '0.0.0.0/0',
        'gateway': '192.168.88.1',
        'active': 'true',
      },
    ];
    _tables['/interface/wireless'] = [
      {
        '.id': '*1',
        'name': 'wlan1',
        'ssid': 'JahanBit-Review',
        'hide-ssid': 'false',
        'security-profile': 'default',
        'disabled': 'false',
      },
    ];
    _tables['/interface/wireless/security-profiles'] = [
      {
        '.id': '*1',
        'name': 'default',
        'wpa2-pre-shared-key': 'review-wifi',
        'wpa-pre-shared-key': 'review-wifi',
        'authentication-types': 'wpa2-psk',
      },
    ];
    _tables['/interface/wireless/access-list'] = [];
    _tables['/interface/wireless/registration-table'] = [];
    _tables['/ip/firewall/raw'] = [
      {
        '.id': '*20',
        'chain': 'prerouting',
        'action': 'drop',
        'src-address': '192.168.88.50',
        'comment': '[JahanBit BAN] Manual ban @192.168.88.50 - IP',
      },
      {
        '.id': '*21',
        'chain': 'prerouting',
        'action': 'drop',
        'src-mac-address': 'AA:BB:CC:DD:EE:50',
        'comment': '[JahanBit BAN] Manual ban @192.168.88.50 - MAC',
      },
    ];
    _tables['/ip/dhcp-server/lease'] = [
      _lease(
        id: '*10',
        address: '192.168.88.10',
        mac: 'AA:BB:CC:DD:EE:10',
        host: 'Review Phone',
        dynamic: 'false',
        lastSeen: '4s',
        comment: 'This phone',
      ),
      _lease(
        id: '*11',
        address: '192.168.88.21',
        mac: 'AA:BB:CC:DD:EE:21',
        host: 'Ahmad Phone',
        dynamic: 'true',
        lastSeen: '6s',
      ),
      _lease(
        id: '*12',
        address: '192.168.88.34',
        mac: 'AA:BB:CC:DD:EE:34',
        host: 'Office Laptop',
        dynamic: 'false',
        lastSeen: '8s',
      ),
      _lease(
        id: '*13',
        address: '192.168.88.50',
        mac: 'AA:BB:CC:DD:EE:50',
        host: 'Smart TV',
        dynamic: 'false',
        lastSeen: '20s',
        blockAccess: 'yes',
        comment: '[JahanBit BAN] Manual ban @192.168.88.50',
      ),
      _lease(
        id: '*14',
        address: '192.168.88.60',
        mac: 'AA:BB:CC:DD:EE:60',
        host: 'Shop Camera',
        dynamic: 'false',
        lastSeen: '12m',
      ),
    ];
    _tables['/ip/arp'] = [
      _arp('192.168.88.10', 'AA:BB:CC:DD:EE:10'),
      _arp('192.168.88.21', 'AA:BB:CC:DD:EE:21'),
      _arp('192.168.88.34', 'AA:BB:CC:DD:EE:34'),
      _arp('192.168.88.50', 'AA:BB:CC:DD:EE:50'),
    ];
    _tables['/ip/neighbor'] = [];
    _tables['/ip/hotspot/active'] = [];
    _tables['/ppp/active'] = [];
    _tables['/queue/simple'] = [];
    _tables['/system/script'] = [];
    for (final ip in ['192.168.88.10', '192.168.88.21', '192.168.88.34']) {
      _upsertQueue(ip, 2000000, 400000);
    }
  }

  Map<String, String> _lease({
    required String id,
    required String address,
    required String mac,
    required String host,
    required String dynamic,
    required String lastSeen,
    String blockAccess = 'no',
    String comment = '',
  }) {
    return {
      '.id': id,
      'address': address,
      'mac-address': mac,
      'host-name': host,
      'comment': comment,
      'dynamic': dynamic,
      'block-access': blockAccess,
      'status': 'bound',
      'last-seen': lastSeen,
      'server': 'dhcp1',
      'disabled': 'false',
    };
  }

  Map<String, String> _arp(String address, String mac) {
    return {
      '.id': _allocateId(),
      'address': address,
      'mac-address': mac,
      'interface': 'bridge',
      'complete': 'true',
    };
  }

  void _upsertQueue(String ip, int rxBps, int txBps) {
    final queues = _tables.putIfAbsent(
      '/queue/simple',
      () => <Map<String, String>>[],
    );
    final target = '$ip/32';
    Map<String, String>? existing;
    for (final candidate in queues) {
      if (candidate['target'] == target) {
        existing = candidate;
        break;
      }
    }
    final row = existing ??
        <String, String>{
          '.id': _allocateId(),
          'name': 'jb-$ip',
          'target': target,
        };
    row['rate'] = '$txBps/$rxBps';
    row['rx-rate'] = '$rxBps';
    row['tx-rate'] = '$txBps';
    row['bytes'] = '48000000/240000000';
    if (existing == null) {
      queues.add(row);
    }
  }

  Set<String> _bannedIps() {
    final ips = <String>{};
    for (final rule in _tables['/ip/firewall/raw'] ?? const []) {
      if (rule['action'] == 'drop' && rule['chain'] == 'prerouting') {
        final ip = rule['src-address']?.trim();
        if (ip != null && ip.isNotEmpty) {
          ips.add(ip);
        }
      }
    }
    return ips;
  }

  List<Map<String, String>> _print(String table, List<String> words) {
    final filters = <MapEntry<String, String>>[];
    List<String>? proplist;
    for (final word in words) {
      if (word.startsWith('?.')) {
        continue;
      }
      if (word.startsWith('?')) {
        final filter = _attribute(word.substring(1));
        if (filter != null) {
          filters.add(filter);
        }
        continue;
      }
      if (word.startsWith('=.proplist=')) {
        proplist = word.substring('=.proplist='.length).split(',');
      }
    }

    final rows = _tables[table] ?? const <Map<String, String>>[];
    final matched = <Map<String, String>>[];
    for (final row in rows) {
      if (_matches(row, filters)) {
        matched.add(_project(row, proplist));
      }
    }
    return matched;
  }

  void _add(String table, List<String> words) {
    final row = <String, String>{'.id': _allocateId()};
    for (final word in words) {
      final attr = _attribute(word);
      if (attr == null || attr.key == '.id' || attr.key == '.proplist') {
        continue;
      }
      row[attr.key] = attr.value;
    }
    _tables.putIfAbsent(table, () => <Map<String, String>>[]).add(row);
  }

  void _set(String table, List<String> words) {
    final attrs = <String, String>{};
    String? id;
    for (final word in words) {
      final attr = _attribute(word);
      if (attr == null) {
        continue;
      }
      if (attr.key == '.id' || attr.key == 'numbers') {
        id = attr.value;
      } else if (attr.key != '.proplist') {
        attrs[attr.key] = attr.value;
      }
    }
    if (id == null) {
      return;
    }
    final row = _findById(table, id);
    if (row == null) {
      return;
    }
    attrs.forEach((key, value) {
      row[key] = value;
    });
  }

  void _remove(String table, List<String> words) {
    String? id;
    for (final word in words) {
      final attr = _attribute(word);
      if (attr != null && (attr.key == '.id' || attr.key == 'numbers')) {
        id = attr.value;
      }
    }
    if (id == null) {
      return;
    }
    _tables[table]?.removeWhere((row) => row['.id'] == id);
  }

  void _makeStatic(String table, List<String> words) {
    String? id;
    for (final word in words) {
      final attr = _attribute(word);
      if (attr != null && (attr.key == 'numbers' || attr.key == '.id')) {
        id = attr.value;
      }
    }
    final row = id == null ? null : _findById(table, id);
    if (row == null) {
      return;
    }
    row['dynamic'] = 'false';
  }

  void _run(String table, List<String> words) {
    if (table != '/system/script') {
      return;
    }
    String? id;
    for (final word in words) {
      final attr = _attribute(word);
      if (attr != null && attr.key == '.id') {
        id = attr.value;
      }
    }
    final script = id == null ? null : _findById(table, id);
    final source = script?['source'];
    if (source != null && source.isNotEmpty) {
      applyScript(source);
    }
  }

  Map<String, String>? _findById(String table, String id) {
    for (final row in _tables[table] ?? const <Map<String, String>>[]) {
      if (row['.id'] == id) {
        return row;
      }
    }
    return null;
  }

  bool _matches(Map<String, String> row, List<MapEntry<String, String>> filters) {
    for (final filter in filters) {
      final actual = row[filter.key] ?? '';
      if (filter.key.contains('mac')) {
        if (actual.toUpperCase() != filter.value.toUpperCase()) {
          return false;
        }
      } else if (actual != filter.value) {
        return false;
      }
    }
    return true;
  }

  Map<String, String> _project(Map<String, String> row, List<String>? proplist) {
    if (proplist == null || proplist.isEmpty) {
      return Map<String, String>.from(row);
    }
    final projected = <String, String>{};
    for (final key in proplist) {
      final value = row[key];
      if (value != null) {
        projected[key] = value;
      }
    }
    return projected;
  }

  MapEntry<String, String>? _attribute(String word) {
    var body = word;
    if (body.startsWith('=')) {
      body = body.substring(1);
    }
    if (body.isEmpty) {
      return null;
    }
    final split = body.indexOf('=');
    if (split <= 0) {
      return null;
    }
    return MapEntry(body.substring(0, split), body.substring(split + 1));
  }

  Map<String, String> _scriptAssignments(String tail) {
    final updates = <String, String>{};
    final pattern = RegExp(r'([A-Za-z0-9\-]+)=("(?:\\.|[^"\\])*"|[^\s]+)');
    for (final match in pattern.allMatches(tail)) {
      final key = match.group(1)!;
      var value = match.group(2)!;
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = _unescape(value.substring(1, value.length - 1));
      }
      updates[key] = value;
    }
    return updates;
  }

  String _unescape(String value) {
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\$', r'$')
        .replaceAll(r'\\', r'\');
  }

  String _normalizeFlag(String key, String value) {
    if (key != 'hide-ssid' && key != 'disabled') {
      return value;
    }
    final normalized = value.toLowerCase();
    if (normalized == 'yes' || normalized == 'true') {
      return 'true';
    }
    if (normalized == 'no' || normalized == 'false') {
      return 'false';
    }
    return value;
  }

  String _allocateId() => '*${_nextId++}';
}
