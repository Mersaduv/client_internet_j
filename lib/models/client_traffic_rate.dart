import 'live_traffic_capabilities.dart';

/// Instantaneous traffic for one client IP, with optional cumulative volume.
class ClientTrafficRate {
  final int rxBps;
  final int txBps;
  final DateTime sampledAt;

  /// Cumulative download bytes from RouterOS counters (queue / hotspot / kid).
  final int? rxBytesTotal;

  /// Cumulative upload bytes from RouterOS counters.
  final int? txBytesTotal;

  /// Which source supplied the cumulative counters (not used for firewall).
  final LiveTrafficSource? volumeSource;

  const ClientTrafficRate({
    required this.rxBps,
    required this.txBps,
    required this.sampledAt,
    this.rxBytesTotal,
    this.txBytesTotal,
    this.volumeSource,
  });

  bool get hasTraffic => rxBps > 0 || txBps > 0;

  bool get hasVolume =>
      (rxBytesTotal != null && rxBytesTotal! >= 0) ||
      (txBytesTotal != null && txBytesTotal! >= 0);

  ClientTrafficRate copyWith({
    int? rxBps,
    int? txBps,
    DateTime? sampledAt,
    int? rxBytesTotal,
    int? txBytesTotal,
    LiveTrafficSource? volumeSource,
  }) {
    return ClientTrafficRate(
      rxBps: rxBps ?? this.rxBps,
      txBps: txBps ?? this.txBps,
      sampledAt: sampledAt ?? this.sampledAt,
      rxBytesTotal: rxBytesTotal ?? this.rxBytesTotal,
      txBytesTotal: txBytesTotal ?? this.txBytesTotal,
      volumeSource: volumeSource ?? this.volumeSource,
    );
  }

  ClientTrafficRate withVolume({
    required int rxBytes,
    required int txBytes,
    required LiveTrafficSource source,
  }) {
    return copyWith(
      rxBytesTotal: rxBytes,
      txBytesTotal: txBytes,
      volumeSource: source,
    );
  }
}

/// Sum of cumulative traffic across devices that have volume samples.
class AggregateTrafficVolume {
  const AggregateTrafficVolume({
    required this.rxBytes,
    required this.txBytes,
    required this.deviceCount,
  });

  final int rxBytes;
  final int txBytes;
  final int deviceCount;

  bool get hasData => deviceCount > 0;

  int get totalBytes => rxBytes + txBytes;
}

/// Instantaneous network total from one router counter.
///
/// [measured] means the sample came from a parent queue or the WAN interface,
/// not from summing per-device viewport streams.
class AggregateLiveTrafficRate {
  const AggregateLiveTrafficRate({
    required this.rxBps,
    required this.txBps,
    required this.deviceCount,
    this.measured = false,
  });

  final int rxBps;
  final int txBps;
  final int deviceCount;

  /// True after a full-network sample, including a real zero.
  final bool measured;

  bool get hasData => measured;
}
