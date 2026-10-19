import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/client_traffic_rate.dart';
import '../models/live_traffic_capabilities.dart';
import '../models/mikrotik_connection.dart';
import '../utils/traffic_rate_parser.dart';
import 'mikrotik_timeouts.dart';
import 'routeros_client_v2.dart';
import 'traffic_monitor_queue_sync.dart';

/// Adaptive live traffic sampler for home and company RouterOS boards.
///
/// The network banner is not the sum of on-screen devices. Each sample reads
/// one router total: a parent/subnet queue rate, otherwise every host queue
/// in the same print, otherwise `/interface/monitor-traffic` on the WAN.
///
/// Per-device badges stay on the scroll window and read whatever already exists:
/// 1. Dedicated host Simple Queue (`ip/32`) instant `rate` when non-zero
/// 2. `/ip/kid-control/device/print` — RouterOS v7+ per-MAC counters
/// 3. `/ip/accounting/snapshot` — if accounting is already enabled
/// 4. `/ip/hotspot/active/print` — hotspot byte delta
/// 5. `/ip/firewall/connection/print` — per-IP byte delta (PCQ/group/pending)
class LiveTrafficEngine {
  RouterOSClientV2? _client;
  MikroTikConnection? _connection;

  LiveTrafficCapabilities _caps = LiveTrafficCapabilities.none;
  bool _capsProbed = false;
  bool _warmupPending = true;
  DateTime? _lastSampleAt;
  int _sampleFailures = 0;

  final Map<String, DateTime> _byteBaselineAt = {};
  final Map<String, ({int rxBytes, int txBytes})> _prevQueueBytes = {};
  final Map<String, ({int bytesUp, int bytesDown})> _prevKidBytes = {};
  final Map<String, ({int bytesIn, int bytesOut})> _prevHotspotBytes = {};
  final Map<String, ({int rxBytes, int txBytes})> _prevConnectionBytes = {};
  /// Absolute volumes for all discovered hosts (not limited to viewport).
  final Map<String, ({int rxBytes, int txBytes, LiveTrafficSource source})>
      _networkVolumes = {};

  /// Full-network live rate. Never the sum of viewport device streams.
  AggregateLiveTrafficRate _networkLive = const AggregateLiveTrafficRate(
    rxBps: 0,
    txBps: 0,
    deviceCount: 0,
  );
  List<Map<String, String>>? _queueRowsThisSample;
  List<String>? _wanInterfaces;
  final TrafficMonitorQueueSync _queueSync = TrafficMonitorQueueSync();

  LiveTrafficCapabilities get capabilities => _caps;
  bool get isReady => _client?.isConnected ?? false;
  bool get usesInstantQueueRates =>
      _caps.queueStats && _caps.primary == LiveTrafficSource.queueStats;

  /// Network-wide cumulative usage from the latest full counter prints.
  AggregateTrafficVolume get networkAggregateVolume {
    var rx = 0;
    var tx = 0;
    var count = 0;
    for (final entry in _networkVolumes.values) {
      rx += entry.rxBytes;
      tx += entry.txBytes;
      count++;
    }
    return AggregateTrafficVolume(
      rxBytes: rx,
      txBytes: tx,
      deviceCount: count,
    );
  }

  /// Network-wide live download/upload rate (bits/s).
  ///
  /// Parent/subnet queue `rate`, otherwise every dedicated host queue in the
  /// same print, otherwise one WAN `monitor-traffic` sample. Viewport polls
  /// do not contribute.
  AggregateLiveTrafficRate get networkAggregateLiveRate => _networkLive;

  Future<void> connect(MikroTikConnection connection) async {
    if (_connection == connection && (_client?.isConnected ?? false)) {
      return;
    }

    await disconnect();

    final client = RouterOSClientV2(
      address: connection.host,
      user: connection.username,
      password: connection.password,
      useSsl: connection.useSsl,
      port: connection.port,
    );

    final ok = await client
        .login()
        .timeout(MikrotikTimeouts.isolatedConnect, onTimeout: () => false);
    if (!ok) {
      client.close();
      throw StateError('live traffic connect failed');
    }

    _client = client;
    _connection = connection;
    _capsProbed = false;
    _warmupPending = true;
    _lastSampleAt = null;
    _clearBaselines();
    debugPrint('[LIVE_TRAFFIC] connected');
  }

  Future<Map<String, ClientTrafficRate>> sample({
    required Set<String> trackedIps,
    required Map<String, String> macToIp,
  }) async {
    _queueRowsThisSample = null;
    if (trackedIps.isNotEmpty) {
      _dropBaselinesNotIn(trackedIps);
    }

    final client = _client;
    if (client == null || !client.isConnected) {
      return {};
    }

    final pollTimeout = MikrotikTimeouts.trafficPollForClients(
      trackedIps.isEmpty ? 1 : trackedIps.length,
    );

    if (!_capsProbed) {
      _caps = await _probeCapabilities(client, pollTimeout);
      _capsProbed = true;
      debugPrint('[LIVE_TRAFFIC] primary=${_caps.primary}');
    }

    final now = DateTime.now();
    final elapsed = _lastSampleAt == null ? null : now.difference(_lastSampleAt!);
    _lastSampleAt = now;

    if (_warmupPending && trackedIps.isNotEmpty) {
      await _captureBaselines(
        client,
        trackedIps,
        macToIp,
        pollTimeout,
      );
      _touchBaselines(trackedIps, now);
      _warmupPending = false;
    }

    if (elapsed != null && elapsed.inMilliseconds < 200) {
      return {};
    }

    try {
      await _refreshNetworkLiveTotal(client, pollTimeout);
    } catch (e) {
      debugPrint('[LIVE_TRAFFIC] network total failed: $e');
    }

    if (trackedIps.isEmpty) {
      return {};
    }

    final sampledAt = now;
    final rates = <String, ClientTrafficRate>{};
    final allowByteDelta =
        elapsed != null &&
        elapsed.inMilliseconds >= TrafficRateParser.minDeltaElapsedMs;

    try {
      final canUsePrimary = allowByteDelta ||
          _caps.primary == LiveTrafficSource.queueStats ||
          _caps.primary == LiveTrafficSource.none;
      if (canUsePrimary) {
        switch (_caps.primary) {
          case LiveTrafficSource.queueStats:
            await _mergeQueueStats(
              client,
              trackedIps,
              sampledAt,
              rates,
              pollTimeout,
            );
          case LiveTrafficSource.kidControl:
            await _mergeKidControl(
              client,
              macToIp,
              sampledAt,
              rates,
            );
          case LiveTrafficSource.ipAccounting:
            await _mergeAccounting(
              client,
              trackedIps,
              elapsed ?? const Duration(milliseconds: 500),
              sampledAt,
              rates,
              pollTimeout,
            );
          case LiveTrafficSource.hotspotActive:
            await _mergeHotspot(
              client,
              trackedIps,
              sampledAt,
              rates,
            );
          case LiveTrafficSource.firewallConnection:
            await _mergeConnectionTracking(
              client,
              trackedIps,
              sampledAt,
              rates,
              pollTimeout: pollTimeout,
            );
          case LiveTrafficSource.none:
            break;
        }
      }

      final missingIps = trackedIps.where((ip) => _needsFallbackRate(rates, ip));
      if (missingIps.isNotEmpty && allowByteDelta) {
        await _mergeSecondarySources(
          client,
          missingIps.toSet(),
          macToIp,
          elapsed,
          sampledAt,
          rates,
          pollTimeout,
        );
      }
      _sampleFailures = 0;
    } catch (e) {
      debugPrint('[LIVE_TRAFFIC] sample failed: $e');
      _sampleFailures++;
      if (_sampleFailures >= 3) {
        await disconnect();
      }
      return {};
    }

    // Attach absolute counters already cached for delta math — no extra API.
    _attachKnownVolumes(rates, trackedIps, sampledAt);
    return rates;
  }

  /// One counter for every connected device, independent of the scroll window.
  Future<void> _refreshNetworkLiveTotal(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    List<Map<String, String>> rows = const [];
    try {
      rows = await _fetchQueueStats(client, pollTimeout);
    } catch (e) {
      debugPrint('[LIVE_TRAFFIC] queue total unavailable: $e');
    }

    final fromQueues = TrafficRateParser.liveTotalFromQueueRows(rows);
    if (fromQueues != null && fromQueues.hasTraffic) {
      _networkLive = AggregateLiveTrafficRate(
        rxBps: fromQueues.rxBps,
        txBps: fromQueues.txBps,
        deviceCount: fromQueues.queueCount,
        measured: true,
      );
      return;
    }

    final wan = await _sampleWanThroughput(client, pollTimeout);
    if (wan != null) {
      _networkLive = wan;
      return;
    }

    if (fromQueues != null && fromQueues.authoritative) {
      _networkLive = AggregateLiveTrafficRate(
        rxBps: fromQueues.rxBps,
        txBps: fromQueues.txBps,
        deviceCount: fromQueues.queueCount,
        measured: true,
      );
    }
  }

  Future<AggregateLiveTrafficRate?> _sampleWanThroughput(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    final interfaces = await _resolveWanInterfaces(client, pollTimeout);
    if (interfaces.isEmpty) {
      return null;
    }

    var rx = 0;
    var tx = 0;
    var sampled = 0;
    for (final name in interfaces) {
      try {
        final rows = await client.talk(
          [
            '/interface/monitor-traffic',
            '=interface=$name',
            '=once=',
          ],
          timeout: pollTimeout,
        );
        if (rows.isEmpty) {
          continue;
        }
        final parsed = TrafficRateParser.fromInterfaceMonitor(rows.first);
        if (parsed == null) {
          continue;
        }
        rx += parsed.rxBps;
        tx += parsed.txBps;
        sampled++;
      } catch (e) {
        debugPrint('[LIVE_TRAFFIC] monitor $name failed: $e');
        _wanInterfaces = null;
      }
    }
    if (sampled == 0) {
      return null;
    }
    return AggregateLiveTrafficRate(
      rxBps: rx,
      txBps: tx,
      deviceCount: sampled,
      measured: true,
    );
  }

  Future<List<String>> _resolveWanInterfaces(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    final cached = _wanInterfaces;
    if (cached != null) {
      return cached;
    }

    final names = <String>{};
    var lookupSucceeded = false;
    try {
      final routes = await client.talk(
        [
          '/ip/route/print',
          '=.proplist=dst-address,gateway,immediate-gw,gateway-status,active',
        ],
        timeout: pollTimeout,
      );
      lookupSucceeded = true;
      for (final row in routes) {
        final name = TrafficRateParser.wanInterfaceFromRoute(row);
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
    } catch (e) {
      debugPrint('[LIVE_TRAFFIC] default route lookup failed: $e');
      try {
        final routes = await client.talk(
          [
            '/ip/route/print',
            '=.proplist=dst-address,gateway,active',
          ],
          timeout: pollTimeout,
        );
        lookupSucceeded = true;
        for (final row in routes) {
          final name = TrafficRateParser.wanInterfaceFromRoute(row);
          if (name != null && name.isNotEmpty) {
            names.add(name);
          }
        }
      } catch (fallbackError) {
        debugPrint('[LIVE_TRAFFIC] route fallback failed: $fallbackError');
      }
    }

    if (lookupSucceeded && names.isEmpty) {
      names.addAll(await _fallbackWanInterfaces(client, pollTimeout));
    }

    if (!lookupSucceeded) {
      return const [];
    }
    _wanInterfaces = names.toList(growable: false);
    return _wanInterfaces!;
  }

  Future<Set<String>> _fallbackWanInterfaces(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    try {
      final rows = await client.talk(
        [
          '/interface/print',
          '=.proplist=name,type,running',
        ],
        timeout: pollTimeout,
      );
      final names = <String>{};
      for (final row in rows) {
        final running = row['running']?.trim().toLowerCase();
        if (running != 'true' && running != 'yes') {
          continue;
        }
        final name = row['name']?.trim();
        if (name == null || name.isEmpty) {
          continue;
        }
        final type = row['type']?.trim().toLowerCase() ?? '';
        final lowerName = name.toLowerCase();
        final uplink = type.contains('pppoe') ||
            type == 'lte' ||
            lowerName.startsWith('pppoe') ||
            lowerName.startsWith('lte') ||
            lowerName == 'wan';
        if (uplink) {
          names.add(name);
        }
      }
      return names;
    } catch (e) {
      debugPrint('[LIVE_TRAFFIC] interface fallback failed: $e');
      return const {};
    }
  }

  /// Prefer durable counters: dedicated queue → hotspot session → kid-control.
  /// Firewall connection totals are skipped (reset when connections close).
  void _attachKnownVolumes(
    Map<String, ClientTrafficRate> rates,
    Set<String> trackedIps,
    DateTime sampledAt,
  ) {
    for (final ip in trackedIps) {
      int? rx;
      int? tx;
      LiveTrafficSource? source;

      final queue = _prevQueueBytes[ip];
      if (queue != null) {
        rx = queue.rxBytes;
        tx = queue.txBytes;
        source = LiveTrafficSource.queueStats;
      } else {
        final hotspot = _prevHotspotBytes[ip];
        if (hotspot != null) {
          rx = hotspot.bytesIn;
          tx = hotspot.bytesOut;
          source = LiveTrafficSource.hotspotActive;
        } else {
          final kid = _prevKidBytes[ip];
          if (kid != null) {
            rx = kid.bytesDown;
            tx = kid.bytesUp;
            source = LiveTrafficSource.kidControl;
          }
        }
      }

      if (source == null || rx == null || tx == null) {
        continue;
      }

      final existing = rates[ip];
      if (existing != null) {
        rates[ip] = existing.withVolume(
          rxBytes: rx,
          txBytes: tx,
          source: source,
        );
      } else {
        rates[ip] = ClientTrafficRate(
          rxBps: 0,
          txBps: 0,
          sampledAt: sampledAt,
          rxBytesTotal: rx,
          txBytesTotal: tx,
          volumeSource: source,
        );
      }
    }
  }

  Future<void> _mergeSecondarySources(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    Map<String, String> macToIp,
    Duration elapsed,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates,
    Duration pollTimeout,
  ) async {
    if (_caps.primary != LiveTrafficSource.queueStats && _caps.queueStats) {
      await _mergeQueueStats(
        client,
        trackedIps,
        sampledAt,
        rates,
        pollTimeout,
        onlyMissing: true,
      );
    }
    if (_caps.primary != LiveTrafficSource.kidControl && _caps.kidControl) {
      await _mergeKidControl(
        client,
        macToIp,
        sampledAt,
        rates,
        onlyMissing: true,
      );
    }
    if (_caps.primary != LiveTrafficSource.ipAccounting && _caps.ipAccounting) {
      await _mergeAccounting(
        client,
        trackedIps,
        elapsed,
        sampledAt,
        rates,
        pollTimeout,
        onlyMissing: true,
      );
    }
    if (_caps.primary != LiveTrafficSource.hotspotActive && _caps.hotspotActive) {
      await _mergeHotspot(
        client,
        trackedIps,
        sampledAt,
        rates,
        onlyMissing: true,
      );
    }
    if (_caps.firewallConnection) {
      await _mergeConnectionTracking(
        client,
        trackedIps,
        sampledAt,
        rates,
        pollTimeout: pollTimeout,
        onlyMissing: true,
      );
    }
  }

  void _setInstantRate(
    Map<String, ClientTrafficRate> rates,
    String ip,
    ClientTrafficRate incoming,
  ) {
    if (incoming.rxBps > TrafficRateParser.maxReasonableBps ||
        incoming.txBps > TrafficRateParser.maxReasonableBps) {
      return;
    }
    rates[ip] = incoming;
  }

  bool _needsFallbackRate(Map<String, ClientTrafficRate> rates, String ip) {
    final existing = rates[ip];
    if (existing == null) {
      return true;
    }
    // Host-queue `rate` is often 0 while real traffic is on a parent PCQ.
    return existing.rxBps == 0 && existing.txBps == 0;
  }

  Future<void> _captureBaselines(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    Map<String, String> macToIp,
    Duration pollTimeout,
  ) async {
    if (_caps.queueStats) {
      final rows = await _fetchQueueStats(client, pollTimeout);
      _ingestQueueNetworkVolumes(rows);
      for (final row in rows) {
        final ip = TrafficRateParser.ipFromQueueTarget(row['target']);
        if (ip == null) {
          continue;
        }
        _storeQueueBytes(ip, row['bytes']);
      }
    }

    if (_caps.kidControl) {
      final rows = await _fetchKidControlDevices(client);
      for (final row in rows) {
        final mac = _normalizeMac(row['mac-address']);
        final ip = mac != null ? macToIp[mac] : null;
        if (ip == null) {
          continue;
        }
        _prevKidBytes[ip] = (
          bytesUp: int.tryParse(row['bytes-up'] ?? '') ?? 0,
          bytesDown: int.tryParse(row['bytes-down'] ?? '') ?? 0,
        );
      }
    }

    if (_caps.ipAccounting) {
      await _takeAccountingSnapshot(client, pollTimeout);
    }

    if (_caps.hotspotActive) {
      final rows = await _fetchHotspotActive(client);
      for (final row in rows) {
        final ip = row['address']?.trim();
        if (ip == null || ip.isEmpty) {
          continue;
        }
        _prevHotspotBytes[ip] = (
          bytesIn: int.tryParse(row['bytes-in'] ?? '') ?? 0,
          bytesOut: int.tryParse(row['bytes-out'] ?? '') ?? 0,
        );
      }
    }

    if (_caps.firewallConnection) {
      await _captureConnectionBaselines(client, trackedIps, pollTimeout);
    }
  }

  Future<void> _mergeQueueStats(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates,
    Duration pollTimeout, {
    bool onlyMissing = false,
  }) async {
    final rows = await _fetchQueueStats(client, pollTimeout);
    _ingestQueueNetworkVolumes(rows);
    for (final row in rows) {
      if (!TrafficRateParser.isDedicatedHostQueueTarget(row['target'])) {
        continue;
      }
      final ip = TrafficRateParser.ipFromQueueTarget(row['target']);
      if (ip == null || !trackedIps.contains(ip)) {
        continue;
      }
      if (onlyMissing && !_needsFallbackRate(rates, ip)) {
        _storeQueueBytes(ip, row['bytes']);
        continue;
      }

      final parsed = TrafficRateParser.fromQueueStatsRow(row);
      final prevBytes = _prevQueueBytes[ip];

      if (parsed != null && (parsed.rxBps > 0 || parsed.txBps > 0)) {
        _setInstantRate(
          rates,
          ip,
          ClientTrafficRate(
            rxBps: parsed.rxBps,
            txBps: parsed.txBps,
            sampledAt: sampledAt,
          ),
        );
        _storeQueueBytes(ip, row['bytes']);
        continue;
      }

      final parts = row['bytes']?.split('/');
      if (parts != null && parts.length >= 2) {
        final txBytes = int.tryParse(parts[0].trim()) ?? 0;
        final rxBytes = int.tryParse(parts[1].trim()) ?? 0;
        final commit = _emitOrRecaptureByteDelta(
          rates: rates,
          ip: ip,
          sampledAt: sampledAt,
          prevRxBytes: prevBytes?.rxBytes,
          prevTxBytes: prevBytes?.txBytes,
          rxBytes: rxBytes,
          txBytes: txBytes,
        );
        if (commit) {
          _storeQueueBytes(ip, row['bytes']);
        }
      }

      // Idle host queues must not hide PCQ/connection traffic.
      final stamped = rates[ip];
      if (stamped != null && stamped.rxBps == 0 && stamped.txBps == 0) {
        rates.remove(ip);
      }
    }
  }

  Future<void> _mergeKidControl(
    RouterOSClientV2 client,
    Map<String, String> macToIp,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates, {
    bool onlyMissing = false,
  }) async {
    final rows = await _fetchKidControlDevices(client);
    _ingestKidNetworkVolumes(rows, macToIp);
    for (final row in rows) {
      final mac = _normalizeMac(row['mac-address']);
      if (mac == null) {
        continue;
      }
      final ip = macToIp[mac];
      if (ip == null) {
        continue;
      }
      if (onlyMissing && !_needsFallbackRate(rates, ip)) {
        _prevKidBytes[ip] = (
          bytesUp: int.tryParse(row['bytes-up'] ?? '') ?? 0,
          bytesDown: int.tryParse(row['bytes-down'] ?? '') ?? 0,
        );
        continue;
      }

      final bytesUp = int.tryParse(row['bytes-up'] ?? '') ?? 0;
      final bytesDown = int.tryParse(row['bytes-down'] ?? '') ?? 0;
      final prev = _prevKidBytes[ip];
      final commit = _emitOrRecaptureByteDelta(
        rates: rates,
        ip: ip,
        sampledAt: sampledAt,
        prevRxBytes: prev?.bytesDown,
        prevTxBytes: prev?.bytesUp,
        rxBytes: bytesDown,
        txBytes: bytesUp,
      );
      if (commit) {
        _prevKidBytes[ip] = (bytesUp: bytesUp, bytesDown: bytesDown);
      }
    }
  }

  Future<void> _mergeAccounting(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    Duration elapsed,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates,
    Duration pollTimeout, {
    bool onlyMissing = false,
  }) async {
    if (onlyMissing && trackedIps.every((ip) => !_needsFallbackRate(rates, ip))) {
      return;
    }

    await _takeAccountingSnapshot(client, pollTimeout);
    final rows = await _fetchAccountingSnapshot(client, pollTimeout);
    final totals = TrafficRateParser.aggregateAccountingRows(
      rows: rows,
      isLocalIp: _isLocalIp,
      trackedIps: trackedIps,
    );

    final seconds = elapsed.inMilliseconds / 1000.0;
    if (seconds <= 0) {
      return;
    }

    for (final ip in trackedIps) {
      if (onlyMissing && !_needsFallbackRate(rates, ip)) {
        continue;
      }
      final current = totals[ip];
      if (current == null) {
        continue;
      }
      final rxBps = (current.rxBytes * 8 / seconds).round();
      final txBps = (current.txBytes * 8 / seconds).round();
      if (rxBps > TrafficRateParser.maxReasonableBps ||
          txBps > TrafficRateParser.maxReasonableBps) {
        continue;
      }
      _setInstantRate(
        rates,
        ip,
        ClientTrafficRate(
          rxBps: rxBps,
          txBps: txBps,
          sampledAt: sampledAt,
        ),
      );
    }
  }

  Future<void> _mergeHotspot(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates, {
    bool onlyMissing = false,
  }) async {
    final rows = await _fetchHotspotActive(client);
    _ingestHotspotNetworkVolumes(rows);
    for (final row in rows) {
      final ip = row['address']?.trim();
      if (ip == null || !trackedIps.contains(ip)) {
        continue;
      }
      if (onlyMissing && !_needsFallbackRate(rates, ip)) {
        _prevHotspotBytes[ip] = (
          bytesIn: int.tryParse(row['bytes-in'] ?? '') ?? 0,
          bytesOut: int.tryParse(row['bytes-out'] ?? '') ?? 0,
        );
        continue;
      }
      if (!onlyMissing && rates.containsKey(ip)) {
        continue;
      }

      final bytesIn = int.tryParse(row['bytes-in'] ?? '') ?? 0;
      final bytesOut = int.tryParse(row['bytes-out'] ?? '') ?? 0;
      final prev = _prevHotspotBytes[ip];
      final commit = _emitOrRecaptureByteDelta(
        rates: rates,
        ip: ip,
        sampledAt: sampledAt,
        prevRxBytes: prev?.bytesIn,
        prevTxBytes: prev?.bytesOut,
        rxBytes: bytesIn,
        txBytes: bytesOut,
      );
      if (commit) {
        _prevHotspotBytes[ip] = (bytesIn: bytesIn, bytesOut: bytesOut);
      }
    }
  }

  Future<void> _captureConnectionBaselines(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    Duration pollTimeout,
  ) async {
    final totals = await _aggregateConnectionBytes(
      client,
      trackedIps,
      pollTimeout,
    );
    for (final entry in totals.entries) {
      _prevConnectionBytes[entry.key] = entry.value;
    }
  }

  Future<void> _mergeConnectionTracking(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    DateTime sampledAt,
    Map<String, ClientTrafficRate> rates, {
    bool onlyMissing = false,
    required Duration pollTimeout,
  }) async {
    final totals = await _aggregateConnectionBytes(
      client,
      trackedIps,
      pollTimeout,
    );

    for (final ip in trackedIps) {
      if (onlyMissing && !_needsFallbackRate(rates, ip)) {
        final current = totals[ip];
        if (current != null) {
          _prevConnectionBytes[ip] = current;
        }
        continue;
      }

      final current = totals[ip];
      if (current == null) {
        continue;
      }

      final prev = _prevConnectionBytes[ip];
      final commit = _emitOrRecaptureByteDelta(
        rates: rates,
        ip: ip,
        sampledAt: sampledAt,
        prevRxBytes: prev?.rxBytes,
        prevTxBytes: prev?.txBytes,
        rxBytes: current.rxBytes,
        txBytes: current.txBytes,
      );
      if (commit) {
        _prevConnectionBytes[ip] = current;
      }
    }
  }

  Future<Map<String, ({int rxBytes, int txBytes})>> _aggregateConnectionBytes(
    RouterOSClientV2 client,
    Set<String> trackedIps,
    Duration pollTimeout,
  ) async {
    final totals = <String, ({int rxBytes, int txBytes})>{
      for (final ip in trackedIps) ip: (rxBytes: 0, txBytes: 0),
    };

    final rows = await _fetchFirewallConnections(client, pollTimeout);
    for (final row in rows) {
      final src = TrafficRateParser.hostFromEndpoint(row['src-address']);
      final dst = TrafficRateParser.hostFromEndpoint(row['dst-address']);
      final origBytes = int.tryParse(row['orig-bytes'] ?? '') ?? 0;
      final replBytes = int.tryParse(row['repl-bytes'] ?? '') ?? 0;

      if (src != null && totals.containsKey(src)) {
        final prev = totals[src]!;
        totals[src] = (
          rxBytes: prev.rxBytes + replBytes,
          txBytes: prev.txBytes + origBytes,
        );
      }
      if (dst != null && totals.containsKey(dst)) {
        final prev = totals[dst]!;
        totals[dst] = (
          rxBytes: prev.rxBytes + origBytes,
          txBytes: prev.txBytes + replBytes,
        );
      }
    }

    return totals;
  }

  Future<LiveTrafficCapabilities> _probeCapabilities(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    var queueStats = false;
    var kidControl = false;
    var ipAccounting = false;
    var hotspotActive = false;
    var firewallConnection = false;
    var accountingLocalTraffic = false;
    final localNetworks = <String>[];

    final probeResults = await Future.wait<Object?>([
      _fetchQueueStats(client, pollTimeout).then((rows) {
        queueStats = rows.isNotEmpty;
        return null;
      }).catchError((_) => null),
      _fetchKidControlDevices(client).then((rows) {
        kidControl = rows.isNotEmpty;
        return null;
      }).catchError((_) => null),
      client
          .talk(
            [
              '/ip/accounting/print',
              '=.proplist=enabled,account-local-traffic',
            ],
            timeout: MikrotikTimeouts.trafficPoll,
          )
          .then((accounting) {
            for (final row in accounting) {
              final enabled = row['enabled']?.toLowerCase();
              ipAccounting = enabled == 'true' || enabled == 'yes';
              final local = row['account-local-traffic']?.toLowerCase();
              accountingLocalTraffic = local == 'true' || local == 'yes';
            }
            return null;
          })
          .catchError((_) => null),
      client
          .talk(
            [
              '/ip/dhcp-server/network/print',
              '=.proplist=address',
            ],
            timeout: MikrotikTimeouts.trafficPoll,
          )
          .then((networks) {
            for (final row in networks) {
              final cidr = row['address']?.trim();
              if (cidr != null && cidr.isNotEmpty) {
                localNetworks.add(cidr);
              }
            }
            return null;
          })
          .catchError((_) => null),
      _fetchHotspotActive(client).then((hotspot) {
        hotspotActive = hotspot.isNotEmpty;
        return null;
      }).catchError((_) => null),
    ]);

    assert(probeResults.length == 5);

    try {
      await _fetchFirewallConnections(client, pollTimeout);
      firewallConnection = true;
    } catch (_) {}

    final primary = queueStats
        ? LiveTrafficSource.queueStats
        : kidControl
            ? LiveTrafficSource.kidControl
            : ipAccounting
                ? LiveTrafficSource.ipAccounting
                : hotspotActive
                    ? LiveTrafficSource.hotspotActive
                    : firewallConnection
                        ? LiveTrafficSource.firewallConnection
                        : LiveTrafficSource.none;

    return LiveTrafficCapabilities(
      primary: primary,
      queueStats: queueStats,
      kidControl: kidControl,
      ipAccounting: ipAccounting,
      hotspotActive: hotspotActive,
      firewallConnection: firewallConnection,
      accountingLocalTraffic: accountingLocalTraffic,
      localNetworkCidrs: localNetworks,
    );
  }

  bool _isLocalIp(String ip) {
    for (final cidr in _caps.localNetworkCidrs) {
      if (TrafficRateParser.isIpInCidr(ip, cidr)) {
        return true;
      }
    }
    return false;
  }

  Future<List<Map<String, String>>> _fetchQueueStats(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    final cached = _queueRowsThisSample;
    if (cached != null) {
      return cached;
    }
    final rows = await client.talk(
      [
        '/queue/simple/print',
        '=stats=',
        '=.proplist=target,parent,rate,rx-rate,tx-rate,bytes',
      ],
      timeout: pollTimeout,
    );
    _queueRowsThisSample = rows;
    return rows;
  }

  Future<List<Map<String, String>>> _fetchKidControlDevices(
    RouterOSClientV2 client,
  ) {
    return client.talk(
      [
        '/ip/kid-control/device/print',
        '=.proplist=mac-address,bytes-up,bytes-down,disabled',
      ],
      timeout: MikrotikTimeouts.trafficPoll,
    );
  }

  Future<void> _takeAccountingSnapshot(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) async {
    await client.talk(
      ['/ip/accounting/snapshot/take'],
      timeout: pollTimeout,
    );
  }

  Future<List<Map<String, String>>> _fetchAccountingSnapshot(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) {
    return client.talk(
      [
        '/ip/accounting/snapshot/print',
        '=.proplist=src-address,dst-address,bytes',
      ],
      timeout: pollTimeout,
    );
  }

  Future<List<Map<String, String>>> _fetchHotspotActive(
    RouterOSClientV2 client,
  ) {
    return client.talk(
      [
        '/ip/hotspot/active/print',
        '=.proplist=address,bytes-in,bytes-out',
      ],
      timeout: MikrotikTimeouts.trafficPoll,
    );
  }

  Future<List<Map<String, String>>> _fetchFirewallConnections(
    RouterOSClientV2 client,
    Duration pollTimeout,
  ) {
    return client.talk(
      [
        '/ip/firewall/connection/print',
        '=.proplist=src-address,dst-address,orig-bytes,repl-bytes',
      ],
      timeout: pollTimeout,
    );
  }

  void _storeQueueBytes(String ip, String? bytesField) {
    if (bytesField == null || !bytesField.contains('/')) {
      return;
    }
    final parts = bytesField.split('/');
    if (parts.length < 2) {
      return;
    }
    _prevQueueBytes[ip] = (
      rxBytes: int.tryParse(parts[1].trim()) ?? 0,
      txBytes: int.tryParse(parts[0].trim()) ?? 0,
    );
  }

  void _rememberNetworkVolume({
    required String ip,
    required int rxBytes,
    required int txBytes,
    required LiveTrafficSource source,
  }) {
    final existing = _networkVolumes[ip];
    if (existing != null &&
        !_volumeSourcePreferred(source, existing.source)) {
      return;
    }
    _networkVolumes[ip] = (
      rxBytes: rxBytes,
      txBytes: txBytes,
      source: source,
    );
  }

  bool _volumeSourcePreferred(
    LiveTrafficSource candidate,
    LiveTrafficSource current,
  ) {
    const rank = {
      LiveTrafficSource.queueStats: 3,
      LiveTrafficSource.hotspotActive: 2,
      LiveTrafficSource.kidControl: 1,
    };
    return (rank[candidate] ?? 0) >= (rank[current] ?? 0);
  }

  void _ingestQueueNetworkVolumes(List<Map<String, String>> rows) {
    for (final row in rows) {
      if (!TrafficRateParser.isDedicatedHostQueueTarget(row['target'])) {
        continue;
      }
      final ip = TrafficRateParser.ipFromQueueTarget(row['target']);
      if (ip == null) {
        continue;
      }
      final bytesField = row['bytes'];
      if (bytesField != null && bytesField.contains('/')) {
        final parts = bytesField.split('/');
        if (parts.length >= 2) {
          _rememberNetworkVolume(
            ip: ip,
            rxBytes: int.tryParse(parts[1].trim()) ?? 0,
            txBytes: int.tryParse(parts[0].trim()) ?? 0,
            source: LiveTrafficSource.queueStats,
          );
        }
      }
    }
  }

  void _ingestHotspotNetworkVolumes(List<Map<String, String>> rows) {
    for (final row in rows) {
      final ip = row['address']?.trim();
      if (ip == null || ip.isEmpty) {
        continue;
      }
      _rememberNetworkVolume(
        ip: ip,
        rxBytes: int.tryParse(row['bytes-in'] ?? '') ?? 0,
        txBytes: int.tryParse(row['bytes-out'] ?? '') ?? 0,
        source: LiveTrafficSource.hotspotActive,
      );
    }
  }

  void _ingestKidNetworkVolumes(
    List<Map<String, String>> rows,
    Map<String, String> macToIp,
  ) {
    for (final row in rows) {
      final mac = _normalizeMac(row['mac-address']);
      if (mac == null) {
        continue;
      }
      final ip = macToIp[mac];
      if (ip == null) {
        continue;
      }
      _rememberNetworkVolume(
        ip: ip,
        rxBytes: int.tryParse(row['bytes-down'] ?? '') ?? 0,
        txBytes: int.tryParse(row['bytes-up'] ?? '') ?? 0,
        source: LiveTrafficSource.kidControl,
      );
    }
  }

  void _touchBaselines(Set<String> ips, DateTime at) {
    for (final ip in ips) {
      _byteBaselineAt[ip] = at;
    }
  }

  void _dropBaselinesNotIn(Set<String> trackedIps) {
    final known = {
      ..._byteBaselineAt.keys,
      ..._prevQueueBytes.keys,
      ..._prevKidBytes.keys,
      ..._prevHotspotBytes.keys,
      ..._prevConnectionBytes.keys,
    };
    for (final ip in known.difference(trackedIps)) {
      _byteBaselineAt.remove(ip);
      _prevQueueBytes.remove(ip);
      _prevKidBytes.remove(ip);
      _prevHotspotBytes.remove(ip);
      _prevConnectionBytes.remove(ip);
    }
  }

  /// Emits a rate only inside the instant window. Returns whether counters
  /// should be replaced (false = interval too short, keep previous baseline).
  bool _emitOrRecaptureByteDelta({
    required Map<String, ClientTrafficRate> rates,
    required String ip,
    required DateTime sampledAt,
    required int? prevRxBytes,
    required int? prevTxBytes,
    required int rxBytes,
    required int txBytes,
  }) {
    if (prevRxBytes == null || prevTxBytes == null) {
      _byteBaselineAt[ip] = sampledAt;
      return true;
    }

    final baselineAt = _byteBaselineAt[ip];
    final instant = TrafficRateParser.instantElapsed(baselineAt, sampledAt);
    if (instant != null) {
      final delta = TrafficRateParser.fromByteDelta(
        prevRxBytes: prevRxBytes,
        prevTxBytes: prevTxBytes,
        rxBytes: rxBytes,
        txBytes: txBytes,
        elapsed: instant,
      );
      if (delta != null) {
        _setInstantRate(
          rates,
          ip,
          ClientTrafficRate(
            rxBps: delta.rxBps,
            txBps: delta.txBps,
            sampledAt: sampledAt,
          ),
        );
      }
      _byteBaselineAt[ip] = sampledAt;
      return true;
    }

    if (baselineAt != null &&
        sampledAt.difference(baselineAt).inMilliseconds <
            TrafficRateParser.minDeltaElapsedMs) {
      return false;
    }

    _byteBaselineAt[ip] = sampledAt;
    return true;
  }

  void _clearBaselines() {
    _byteBaselineAt.clear();
    _prevQueueBytes.clear();
    _prevKidBytes.clear();
    _prevHotspotBytes.clear();
    _prevConnectionBytes.clear();
    _networkVolumes.clear();
    _networkLive = const AggregateLiveTrafficRate(
      rxBps: 0,
      txBps: 0,
      deviceCount: 0,
    );
    _queueRowsThisSample = null;
    _wanInterfaces = null;
  }

  String? _normalizeMac(String? mac) => mac?.trim().toUpperCase();

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _connection = null;
    _caps = LiveTrafficCapabilities.none;
    _capsProbed = false;
    _warmupPending = true;
    _lastSampleAt = null;
    _sampleFailures = 0;
    _queueSync.reset();
    _clearBaselines();
  }
}
