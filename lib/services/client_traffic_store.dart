import 'package:flutter/foundation.dart';

import '../models/client_info.dart';
import '../models/client_traffic_rate.dart';
import '../utils/client_display_policy.dart';

/// Tracks live traffic samples keyed by client IP.
///
/// Samples arrive from RouterOS at poll cadence; [syncDisplayTick] publishes
/// them to the UI once per second (Task Manager style).
class ClientTrafficStore {
  final Map<String, ClientTrafficRate> _sampleRatesByIp = {};
  final Map<String, ClientTrafficRate> _displayRatesByIp = {};
  final Set<String> _measuredIps = {};
  final Map<String, DateTime> _leftViewportAt = {};
  final Map<String, DateTime> _awaitingFirstAt = {};
  bool _pollReady = false;

  /// Bumps when a badge or the network total should repaint.
  /// The device list itself does not listen to this.
  final ValueNotifier<int> displayTick = ValueNotifier(0);

  void bumpDisplay() {
    displayTick.value++;
  }

  /// Keep last rate after a row leaves the viewport so re-entry is not a skeleton.
  Duration retainAfterLeave = const Duration(seconds: 5);

  /// After this, show idle instead of an infinite skeleton.
  Duration placeholderTimeout = const Duration(seconds: 3);

  /// IPs that left the poll viewport — allow fresh warmup when they re-enter.
  final Set<String> _viewportActiveIps = {};

  bool get pollReady => _pollReady;

  ({Set<String> ips, Map<String, String> macToIp}) trackingContext(
    List<ClientInfo> displayClients,
  ) {
    final ips = <String>{};
    final macToIp = <String, String>{};

    for (final client in displayClients) {
      if (!ClientDisplayPolicy.shouldShowInConnectedList(client)) {
        continue;
      }
      final ip = _normalizeIp(client.ipAddress);
      final mac = client.macAddress?.trim().toUpperCase();
      if (ip != null) {
        ips.add(ip);
      }
      if (mac != null && mac.isNotEmpty && ip != null) {
        macToIp[mac] = ip;
      }
    }

    return (ips: ips, macToIp: macToIp);
  }

  Set<String> newIpsSinceLastPoll(Set<String> currentIps) {
    if (!_pollReady) {
      return currentIps;
    }
    return currentIps.difference(_measuredIps);
  }

  bool isMeasured(String? ip) {
    final normalized = _normalizeIp(ip);
    if (normalized == null) {
      return false;
    }
    return _measuredIps.contains(normalized);
  }

  /// Latest one-second display frame (Task Manager cadence).
  ClientTrafficRate? rateFor(String? ip) {
    final normalized = _normalizeIp(ip);
    if (normalized == null) {
      return null;
    }
    return _displayRatesByIp[normalized] ?? _sampleRatesByIp[normalized];
  }

  /// True when a visible IP has waited too long for its first sample.
  bool awaitingFirstSampleTimedOut(String? ip, {DateTime? now}) {
    final normalized = _normalizeIp(ip);
    if (normalized == null || _measuredIps.contains(normalized)) {
      return false;
    }
    final started = _awaitingFirstAt[normalized];
    if (started == null) {
      return false;
    }
    return (now ?? DateTime.now()).difference(started) >= placeholderTimeout;
  }

  /// Any unmeasured IP currently in the poll window (for a one-shot UI timer).
  bool get hasUnmeasuredActiveIps {
    for (final ip in _viewportActiveIps) {
      if (!_measuredIps.contains(ip)) {
        return true;
      }
    }
    return false;
  }

  /// Viewport poll set changed — keep recent rates so scrolling is not a shock.
  void onViewportChanged(Set<String> activeIps, {DateTime? now}) {
    final clock = now ?? DateTime.now();

    for (final ip in _viewportActiveIps.difference(activeIps)) {
      _leftViewportAt.putIfAbsent(ip, () => clock);
    }
    for (final ip in activeIps) {
      _leftViewportAt.remove(ip);
      if (!_measuredIps.contains(ip)) {
        _awaitingFirstAt.putIfAbsent(ip, () => clock);
      }
    }

    _viewportActiveIps
      ..clear()
      ..addAll(activeIps);
    _pruneLeft(clock);
  }

  /// Stores raw poll samples (bps). UI reads via [syncDisplayTick].
  ///
  /// Returns true when at least one IP got its first measurement (hide skeleton).
  bool applyPoll({
    required Set<String> trackedIps,
    required Map<String, ClientTrafficRate> samples,
    required bool Function(int?, int?) rateChanged,
    DateTime? fallbackSampledAt,
  }) {
    if (samples.isNotEmpty) {
      _pollReady = true;
    }
    var firstMeasurement = false;

    for (final ip in trackedIps) {
      final sample = samples[ip];
      if (sample == null) {
        continue;
      }

      final wasMeasured = _measuredIps.contains(ip);
      _sampleRatesByIp[ip] = sample;
      _measuredIps.add(ip);
      _awaitingFirstAt.remove(ip);

      if (!wasMeasured) {
        _displayRatesByIp[ip] = sample;
        firstMeasurement = true;
      }
    }

    return firstMeasurement;
  }

  /// Publishes the latest samples to the UI on a fixed one-second cadence.
  bool syncDisplayTick() {
    var changed = false;
    for (final entry in _sampleRatesByIp.entries) {
      final ip = entry.key;
      if (!_viewportActiveIps.contains(ip) && !_displayRatesByIp.containsKey(ip)) {
        continue;
      }
      final sample = entry.value;
      final previous = _displayRatesByIp[ip];
      if (previous != null &&
          previous.rxBps == sample.rxBps &&
          previous.txBps == sample.txBps &&
          previous.rxBytesTotal == sample.rxBytesTotal &&
          previous.txBytesTotal == sample.txBytesTotal) {
        continue;
      }
      _displayRatesByIp[ip] = sample;
      changed = true;
    }
    if (changed) {
      bumpDisplay();
    }
    return changed;
  }

  /// Sum of live rates for [ips] that currently have samples.
  AggregateLiveTrafficRate aggregateLiveRateFor(Iterable<String?> ips) {
    var rx = 0;
    var tx = 0;
    var count = 0;
    final seen = <String>{};

    for (final raw in ips) {
      final ip = _normalizeIp(raw);
      if (ip == null || !seen.add(ip)) {
        continue;
      }
      final sample = _displayRatesByIp[ip] ?? _sampleRatesByIp[ip];
      if (sample == null) {
        continue;
      }
      rx += sample.rxBps;
      tx += sample.txBps;
      count++;
    }

    return AggregateLiveTrafficRate(
      rxBps: rx,
      txBps: tx,
      deviceCount: count,
    );
  }

  /// Sum of cumulative volume for [ips] that currently have counters.
  AggregateTrafficVolume aggregateVolumeFor(Iterable<String?> ips) {
    var rx = 0;
    var tx = 0;
    var count = 0;
    final seen = <String>{};

    for (final raw in ips) {
      final ip = _normalizeIp(raw);
      if (ip == null || !seen.add(ip)) {
        continue;
      }
      final sample = _displayRatesByIp[ip] ?? _sampleRatesByIp[ip];
      if (sample == null || !sample.hasVolume) {
        continue;
      }
      rx += sample.rxBytesTotal ?? 0;
      tx += sample.txBytesTotal ?? 0;
      count++;
    }

    return AggregateTrafficVolume(
      rxBytes: rx,
      txBytes: tx,
      deviceCount: count,
    );
  }

  void reset() {
    _sampleRatesByIp.clear();
    _displayRatesByIp.clear();
    _measuredIps.clear();
    _viewportActiveIps.clear();
    _leftViewportAt.clear();
    _awaitingFirstAt.clear();
    _pollReady = false;
  }

  void _pruneLeft(DateTime now) {
    final expired = <String>[];
    for (final entry in _leftViewportAt.entries) {
      if (now.difference(entry.value) >= retainAfterLeave) {
        expired.add(entry.key);
      }
    }
    for (final ip in expired) {
      _leftViewportAt.remove(ip);
    }
  }

  String? _normalizeIp(String? ip) {
    final trimmed = ip?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == '0.0.0.0') {
      return null;
    }
    return trimmed;
  }
}
