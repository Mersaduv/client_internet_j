/// Parses MikroTik queue / hotspot counters into bit-per-second rates.
abstract final class TrafficRateParser {
  /// Minimum interval for byte-delta rate math (avoids spike on short polls).
  static const int minDeltaElapsedMs = 350;

  /// Deltas older than this are a new baseline, not an instant rate.
  ///
  /// Must cover a slow `/ip/firewall/connection/print` on busy routers
  /// (several seconds). Off-viewport IPs already drop their baseline.
  static const int maxInstantElapsedMs = 20000;

  /// Ignore absurd delta spikes from counter resets or bad intervals.
  static const int maxReasonableBps = 500000000;
  /// Extract host IP from queue target, connection endpoint, or accounting row.
  ///
  /// Handles `192.168.1.5/32`, `192.168.1.5:443`, and bare IPv4.
  static String? hostFromEndpoint(String? endpoint) {
    final value = endpoint?.trim();
    if (value == null || value.isEmpty || value == '0.0.0.0') {
      return null;
    }

    if (value.contains('/')) {
      return ipFromQueueTarget(value);
    }

    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 1) {
        return value.substring(1, end);
      }
      return null;
    }

    final colonCount = ':'.allMatches(value).length;
    if (colonCount == 1 && value.contains('.')) {
      final split = value.split(':');
      if (split.length == 2 && int.tryParse(split[1]) != null) {
        return split[0];
      }
    }

    if (colonCount == 0 && value.contains('.')) {
      return value;
    }

    return null;
  }

  /// Extract IPv4 from queue target like `192.168.1.5/32`.
  ///
  /// Group / subnet targets are not a single host — use
  /// [isDedicatedHostQueueTarget] before mapping a rate to one client.
  static String? ipFromQueueTarget(String? target) {
    final value = target?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final first = value.split(',').first.trim();
    final slash = first.indexOf('/');
    final ip = slash >= 0 ? first.substring(0, slash) : first;
    if (ip.isEmpty || ip == '0.0.0.0') {
      return null;
    }
    return ip;
  }

  /// True only for a single host queue (`1.2.3.4` or `1.2.3.4/32`).
  ///
  /// Skips PCQ/subnet (`172.16.0.0/24`) and department group targets
  /// (`ip/32,ip/32,...`) so their shared rate is not shown on one client.
  static bool isDedicatedHostQueueTarget(String? target) {
    final value = target?.trim();
    if (value == null || value.isEmpty || value.contains(',')) {
      return false;
    }

    final slash = value.indexOf('/');
    if (slash < 0) {
      return hostFromEndpoint(value) != null;
    }

    final prefix = value.substring(slash + 1).trim();
    if (prefix != '32') {
      return false;
    }
    final ip = value.substring(0, slash).trim();
    return ip.isNotEmpty && ip != '0.0.0.0' && ip.contains('.');
  }

  /// Queue `print stats` row → download (rx) / upload (tx) in bps.
  static ({int rxBps, int txBps})? fromQueueStatsRow(Map<String, String> row) {
    final explicitRx = _parseBitsPerSecond(row['rx-rate']);
    final explicitTx = _parseBitsPerSecond(row['tx-rate']);
    if (explicitRx != null || explicitTx != null) {
      return (
        rxBps: explicitRx ?? 0,
        txBps: explicitTx ?? 0,
      );
    }

    final rate = row['rate']?.trim();
    if (rate == null || rate.isEmpty || !rate.contains('/')) {
      return null;
    }

    final parts = rate.split('/');
    if (parts.length < 2) {
      return null;
    }

    // MikroTik queue stats: rate is upload/download (tx/rx from client view).
    final tx = _parseBitsPerSecond(parts[0]) ?? 0;
    final rx = _parseBitsPerSecond(parts[1]) ?? 0;
    return (rxBps: rx, txBps: tx);
  }

  /// Hotspot byte counters delta → bps (client download = bytes-in).
  static ({int rxBps, int txBps})? fromHotspotByteDelta({
    required int prevBytesIn,
    required int prevBytesOut,
    required int bytesIn,
    required int bytesOut,
    required Duration elapsed,
  }) {
    if (elapsed.inMilliseconds < minDeltaElapsedMs) {
      return null;
    }
    final seconds = elapsed.inMilliseconds / 1000.0;
    final rx = ((bytesIn - prevBytesIn).clamp(0, 1 << 62) * 8 / seconds).round();
    final tx =
        ((bytesOut - prevBytesOut).clamp(0, 1 << 62) * 8 / seconds).round();
    if (rx == 0 && tx == 0) {
      return null;
    }
    return (rxBps: rx, txBps: tx);
  }

  /// Cumulative queue `bytes` field delta (upload/download pair in row).
  static ({int rxBps, int txBps})? fromQueueBytesDelta({
    required String? bytesField,
    required int prevRxBytes,
    required int prevTxBytes,
    required Duration elapsed,
  }) {
    if (bytesField == null || !bytesField.contains('/')) {
      return null;
    }
    final parts = bytesField.split('/');
    if (parts.length < 2) {
      return null;
    }
    final txBytes = int.tryParse(parts[0].trim()) ?? 0;
    final rxBytes = int.tryParse(parts[1].trim()) ?? 0;
    return fromByteDelta(
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      rxBytes: rxBytes,
      txBytes: txBytes,
      elapsed: elapsed,
    );
  }

  /// Valid window for instant byte-delta math, or null to recapture baseline.
  static Duration? instantElapsed(DateTime? baselineAt, DateTime now) {
    if (baselineAt == null) {
      return null;
    }
    final elapsed = now.difference(baselineAt);
    final ms = elapsed.inMilliseconds;
    if (ms < minDeltaElapsedMs || ms > maxInstantElapsedMs) {
      return null;
    }
    return elapsed;
  }

  static ({int rxBps, int txBps})? fromByteDelta({
    required int prevRxBytes,
    required int prevTxBytes,
    required int rxBytes,
    required int txBytes,
    required Duration elapsed,
  }) {
    if (elapsed.inMilliseconds < minDeltaElapsedMs) {
      return null;
    }
    final seconds = elapsed.inMilliseconds / 1000.0;
    final rx = ((rxBytes - prevRxBytes).clamp(0, 1 << 62) * 8 / seconds).round();
    final tx = ((txBytes - prevTxBytes).clamp(0, 1 << 62) * 8 / seconds).round();
    if (rx > maxReasonableBps || tx > maxReasonableBps) {
      return null;
    }
    return (rxBps: rx, txBps: tx);
  }

  /// IP accounting snapshot rows → per-IP byte totals for one interval.
  static Map<String, ({int rxBytes, int txBytes})> aggregateAccountingRows({
    required Iterable<Map<String, String>> rows,
    required bool Function(String ip) isLocalIp,
    required Set<String> trackedIps,
  }) {
    final totals = <String, ({int rxBytes, int txBytes})>{};
    for (final ip in trackedIps) {
      totals[ip] = (rxBytes: 0, txBytes: 0);
    }

    for (final row in rows) {
      final src = hostFromEndpoint(row['src-address']);
      final dst = hostFromEndpoint(row['dst-address']);
      final bytes = int.tryParse(row['bytes'] ?? '') ?? 0;
      if (bytes <= 0 || src == null || dst == null) {
        continue;
      }

      final srcLocal = isLocalIp(src);
      final dstLocal = isLocalIp(dst);

      if (srcLocal && dstLocal) {
        if (trackedIps.contains(src)) {
          final prev = totals[src]!;
          totals[src] = (rxBytes: prev.rxBytes, txBytes: prev.txBytes + bytes);
        }
        if (trackedIps.contains(dst)) {
          final prev = totals[dst]!;
          totals[dst] = (rxBytes: prev.rxBytes + bytes, txBytes: prev.txBytes);
        }
      } else if (srcLocal && !dstLocal && trackedIps.contains(src)) {
        final prev = totals[src]!;
        totals[src] = (rxBytes: prev.rxBytes, txBytes: prev.txBytes + bytes);
      } else if (!srcLocal && dstLocal && trackedIps.contains(dst)) {
        final prev = totals[dst]!;
        totals[dst] = (rxBytes: prev.rxBytes + bytes, txBytes: prev.txBytes);
      }
    }

    return totals;
  }

  /// Live total from one `/queue/simple/print stats` response.
  ///
  /// RouterOS gives each packet to the first matching top-level queue, so
  /// those queues are slices and must be added. An empty target is one slice,
  /// not a substitute for the rest. A child queue is skipped when a live
  /// top-level queue already covers its addresses.
  static QueueLiveTotal? liveTotalFromQueueRows(
    Iterable<Map<String, String>> rows,
  ) {
    final top = <_QueueRateTarget>[];
    final children = <_QueueRateTarget>[];

    for (final row in rows) {
      final target = row['target']?.trim() ?? '';
      final parsed = fromQueueStatsRow(row);
      if (parsed == null) {
        continue;
      }
      if (parsed.rxBps > maxReasonableBps || parsed.txBps > maxReasonableBps) {
        continue;
      }
      final entry = _QueueRateTarget(
        target: target,
        rxBps: parsed.rxBps,
        txBps: parsed.txBps,
      );
      if (isChildQueue(row['parent'])) {
        children.add(entry);
      } else {
        top.add(entry);
      }
    }

    final liveTop = top
        .where((queue) => queue.rxBps > 0 || queue.txBps > 0)
        .toList(growable: false);
    if (liveTop.isNotEmpty) {
      final extra = children.where((child) {
        if (child.rxBps == 0 && child.txBps == 0) {
          return false;
        }
        return !_coveredBy(liveTop, child);
      });
      return _sumQueueTargets(
        [...liveTop, ...extra],
        authoritative: true,
      );
    }

    final liveChildren = children
        .where((queue) => queue.rxBps > 0 || queue.txBps > 0)
        .toList(growable: false);
    if (liveChildren.isEmpty) {
      return null;
    }
    return _sumQueueTargets(liveChildren, authoritative: true);
  }

  /// Per-device download/upload from one connection print.
  ///
  /// `orig-rate` / `repl-rate` are already bits per second, refreshed by
  /// RouterOS every second. Every connected IP is present, including idle
  /// zeros, so the list does not depend on which row is on screen.
  static Map<String, ({int rxBps, int txBps})>? perIpFromConnectionRates({
    required Iterable<Map<String, String>> rows,
    required Set<String> connectedIps,
  }) {
    if (connectedIps.isEmpty) {
      return null;
    }
    var sawRate = false;
    final totals = <String, ({int rxBps, int txBps})>{
      for (final ip in connectedIps) ip: (rxBps: 0, txBps: 0),
    };
    for (final row in rows) {
      if (row.containsKey('orig-rate') || row.containsKey('repl-rate')) {
        sawRate = true;
      }
      final orig = _parseBitsPerSecond(row['orig-rate']) ?? 0;
      final repl = _parseBitsPerSecond(row['repl-rate']) ?? 0;
      if (orig > maxReasonableBps || repl > maxReasonableBps) {
        continue;
      }
      final src = hostFromEndpoint(row['src-address']);
      final dst = hostFromEndpoint(row['dst-address']);
      if (src != null && totals.containsKey(src)) {
        final prev = totals[src]!;
        totals[src] = (rxBps: prev.rxBps + repl, txBps: prev.txBps + orig);
      }
      if (dst != null && dst != src && totals.containsKey(dst)) {
        final prev = totals[dst]!;
        totals[dst] = (rxBps: prev.rxBps + orig, txBps: prev.txBps + repl);
      }
    }
    if (!sawRate) {
      return null;
    }
    return totals;
  }

  /// Sum of [perIpFromConnectionRates]. Kept for tests of the same direction rules.
  static ({int rxBps, int txBps, int deviceCount})? liveTotalFromConnectionRates({
    required Iterable<Map<String, String>> rows,
    required Set<String> connectedIps,
  }) {
    final perIp = perIpFromConnectionRates(rows: rows, connectedIps: connectedIps);
    if (perIp == null) {
      return null;
    }
    var rx = 0;
    var tx = 0;
    var devices = 0;
    for (final rate in perIp.values) {
      rx += rate.rxBps;
      tx += rate.txBps;
      if (rate.rxBps > 0 || rate.txBps > 0) {
        devices++;
      }
    }
    return (rxBps: rx, txBps: tx, deviceCount: devices);
  }

  /// Interface that owns the default-gateway address, such as `10.10.10.2/30`
  /// on ether1 when the route gateway is `10.10.10.1`.
  static List<String> interfacesForGateways({
    required Iterable<String> gateways,
    required Iterable<Map<String, String>> addresses,
  }) {
    final names = <String>[];
    for (final gateway in gateways) {
      final host = gateway.split('%').first.trim();
      if (!_looksLikeIpv4(host)) {
        continue;
      }
      for (final row in addresses) {
        final disabled = row['disabled']?.trim().toLowerCase();
        if (disabled == 'true' || disabled == 'yes') {
          continue;
        }
        final iface = row['interface']?.trim();
        final cidr = row['address']?.trim();
        if (iface == null || iface.isEmpty || cidr == null || cidr.isEmpty) {
          continue;
        }
        if (!isIpInCidr(host, cidr) || names.contains(iface)) {
          continue;
        }
        names.add(iface);
      }
    }
    return names;
  }

  /// IPv4 next hop of an active default route, when the gateway is an address.
  static String? gatewayAddressFromRoute(Map<String, String> row) {
    if (wanInterfaceFromRoute(row) != null) {
      return null;
    }
    final dst = row['dst-address']?.trim();
    if (dst != null && dst.isNotEmpty && dst != '0.0.0.0/0') {
      return null;
    }
    final active = row['active']?.trim().toLowerCase();
    if (active != null &&
        active.isNotEmpty &&
        active != 'true' &&
        active != 'yes') {
      return null;
    }
    final host = (row['gateway'] ?? '').split('%').first.trim();
    if (!_looksLikeIpv4(host)) {
      return null;
    }
    return host;
  }

  static bool _coveredBy(List<_QueueRateTarget> parents, _QueueRateTarget child) {
    if (child.cidrs.isEmpty) {
      return false;
    }
    return parents.any(
      (parent) => parent.cidrs.any(
        (outer) => child.cidrs.every((inner) => _cidrContains(outer, inner)),
      ),
    );
  }

  /// `rx-bits-per-second` on the WAN is client download; `tx` is upload.
  static ({int rxBps, int txBps})? fromInterfaceMonitor(
    Map<String, String> row,
  ) {
    final rx = _parseBitsPerSecond(row['rx-bits-per-second']);
    final tx = _parseBitsPerSecond(row['tx-bits-per-second']);
    if (rx == null && tx == null) {
      return null;
    }
    return (rxBps: rx ?? 0, txBps: tx ?? 0);
  }

  /// Active default-route egress interface, or null when the row is not one.
  static String? wanInterfaceFromRoute(Map<String, String> row) {
    final dst = row['dst-address']?.trim();
    if (dst != null && dst.isNotEmpty && dst != '0.0.0.0/0') {
      return null;
    }
    final active = row['active']?.trim().toLowerCase();
    if (active != null &&
        active.isNotEmpty &&
        active != 'true' &&
        active != 'yes') {
      return null;
    }

    final via = _interfaceAfterVia(row['gateway-status']);
    if (via != null) {
      return via;
    }
    final immediate = _interfaceFromGateway(row['immediate-gw']);
    if (immediate != null) {
      return immediate;
    }
    return _interfaceFromGateway(row['gateway']);
  }

  /// True when this simple queue sits under another queue.
  static bool isChildQueue(String? parent) {
    final value = parent?.trim().toLowerCase();
    return value != null && value.isNotEmpty && value != 'none';
  }

  static bool isIpInCidr(String ip, String cidr) {
    try {
      final parts = cidr.split('/');
      if (parts.length != 2) {
        return ip == cidr;
      }
      final base = _ipv4ToInt(parts[0]);
      final prefix = int.parse(parts[1]);
      final mask = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;
      final target = _ipv4ToInt(ip);
      return (base & mask) == (target & mask);
    } catch (_) {
      return false;
    }
  }

  static int _ipv4ToInt(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) {
      return 0;
    }
    var value = 0;
    for (final octet in octets) {
      value = (value << 8) + (int.tryParse(octet) ?? 0);
    }
    return value;
  }

  static int? _parseBitsPerSecond(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final lower = value.toLowerCase();
    if (RegExp(r'^\d+$').hasMatch(lower)) {
      return int.tryParse(lower);
    }

    final match = RegExp(
      r'^([\d.]+)\s*([kmgt]?)(?:bps|bit)?$',
      caseSensitive: false,
    ).firstMatch(lower.replaceAll(' ', ''));
    if (match == null) {
      return int.tryParse(lower);
    }

    final amount = double.tryParse(match.group(1)!);
    if (amount == null) {
      return null;
    }

    final unit = match.group(2) ?? '';
    final multiplier = switch (unit) {
      'k' => 1000,
      'm' => 1000000,
      'g' => 1000000000,
      't' => 1000000000000,
      _ => 1,
    };
    return (amount * multiplier).round();
  }

  static QueueLiveTotal _sumQueueTargets(
    List<_QueueRateTarget> rows, {
    required bool authoritative,
  }) {
    var rx = 0;
    var tx = 0;
    for (final row in rows) {
      rx += row.rxBps;
      tx += row.txBps;
    }
    return QueueLiveTotal(
      rxBps: rx,
      txBps: tx,
      queueCount: rows.length,
      authoritative: authoritative,
    );
  }

  static bool _cidrContains(_Cidr outer, _Cidr inner) {
    if (inner.prefix < outer.prefix) {
      return false;
    }
    return (inner.network & outer.mask) == outer.network;
  }

  static String? _interfaceAfterVia(String? status) {
    final value = status?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final match = RegExp(r'\bvia\s+(\S+)').firstMatch(value);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    return name;
  }

  static String? _interfaceFromGateway(String? gateway) {
    final value = gateway?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.contains('%')) {
      final name = value.split('%').last.trim();
      if (name.isEmpty || _looksLikeIpv4(name)) {
        return null;
      }
      return name;
    }
    if (_looksLikeIpv4(value)) {
      return null;
    }
    return value;
  }

  static bool _looksLikeIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) {
      return false;
    }
    return parts.every((part) => int.tryParse(part) != null);
  }
}

/// One router-side live total derived from simple-queue stats.
class QueueLiveTotal {
  const QueueLiveTotal({
    required this.rxBps,
    required this.txBps,
    required this.queueCount,
    required this.authoritative,
  });

  final int rxBps;
  final int txBps;
  final int queueCount;

  /// Parent, subnet, or group queues. A zero here is a real idle shaper,
  /// not a missing per-device sample.
  final bool authoritative;

  bool get hasTraffic => rxBps > 0 || txBps > 0;
}

class _Cidr {
  const _Cidr(this.network, this.prefix, this.mask);

  final int network;
  final int prefix;
  final int mask;
}

class _QueueRateTarget {
  _QueueRateTarget({
    required this.target,
    required this.rxBps,
    required this.txBps,
  }) : cidrs = _cidrsOf(target);

  final String target;
  final int rxBps;
  final int txBps;
  final List<_Cidr> cidrs;

  static List<_Cidr> _cidrsOf(String target) {
    final cidrs = <_Cidr>[];
    for (final part in target.split(',')) {
      final parsed = _parseCidr(part);
      if (parsed != null) {
        cidrs.add(parsed);
      }
    }
    return cidrs;
  }

  static _Cidr? _parseCidr(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final slash = value.indexOf('/');
    final ip = slash >= 0 ? value.substring(0, slash).trim() : value;
    final prefix = slash >= 0
        ? int.tryParse(value.substring(slash + 1).trim())
        : 32;
    if (prefix == null || prefix < 0 || prefix > 32 || !ip.contains('.')) {
      return null;
    }
    final addr = TrafficRateParser._ipv4ToInt(ip);
    final mask = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;
    return _Cidr(addr & mask, prefix, mask);
  }
}
