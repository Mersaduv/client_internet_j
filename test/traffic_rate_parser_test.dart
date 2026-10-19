import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/utils/format_traffic_rate.dart';
import 'package:jahan_bit/utils/traffic_rate_parser.dart';

void main() {
  group('TrafficRateParser', () {
    test('ipFromQueueTarget strips CIDR suffix', () {
      expect(
        TrafficRateParser.ipFromQueueTarget('192.168.1.10/32'),
        '192.168.1.10',
      );
    });

    test('isDedicatedHostQueueTarget rejects PCQ and group queues', () {
      expect(
        TrafficRateParser.isDedicatedHostQueueTarget('172.16.0.63/32'),
        isTrue,
      );
      expect(
        TrafficRateParser.isDedicatedHostQueueTarget('172.16.0.63'),
        isTrue,
      );
      expect(
        TrafficRateParser.isDedicatedHostQueueTarget('172.16.0.0/24'),
        isFalse,
      );
      expect(
        TrafficRateParser.isDedicatedHostQueueTarget(
          '172.16.0.72/32,172.16.0.73/32',
        ),
        isFalse,
      );
    });

    test('fromQueueStatsRow parses rate tx/rx pair', () {
      final parsed = TrafficRateParser.fromQueueStatsRow({
        'rate': '512000/2048000',
      });
      expect(parsed?.txBps, 512000);
      expect(parsed?.rxBps, 2048000);
    });

    test('fromQueueStatsRow parses human readable Mbps', () {
      final parsed = TrafficRateParser.fromQueueStatsRow({
        'rate': '3.2Mbps/18.5Mbps',
      });
      expect(parsed?.txBps, 3200000);
      expect(parsed?.rxBps, 18500000);
    });

    test('fromHotspotByteDelta computes bps', () {
      final delta = TrafficRateParser.fromHotspotByteDelta(
        prevBytesIn: 0,
        prevBytesOut: 0,
        bytesIn: 125000,
        bytesOut: 25000,
        elapsed: const Duration(seconds: 1),
      );
      expect(delta?.rxBps, 1000000);
      expect(delta?.txBps, 200000);
    });

    test('hostFromEndpoint strips port suffix', () {
      expect(
        TrafficRateParser.hostFromEndpoint('192.168.1.10:443'),
        '192.168.1.10',
      );
      expect(
        TrafficRateParser.hostFromEndpoint('10.0.0.5/32'),
        '10.0.0.5',
      );
      expect(
        TrafficRateParser.hostFromEndpoint('172.16.0.20'),
        '172.16.0.20',
      );
    });

    test('fromByteDelta returns zero rates for idle interval', () {
      final delta = TrafficRateParser.fromByteDelta(
        prevRxBytes: 1000,
        prevTxBytes: 500,
        rxBytes: 1000,
        txBytes: 500,
        elapsed: const Duration(seconds: 1),
      );
      expect(delta?.rxBps, 0);
      expect(delta?.txBps, 0);
    });

    test('fromByteDelta rejects rates above maxReasonableBps', () {
      final delta = TrafficRateParser.fromByteDelta(
        prevRxBytes: 0,
        prevTxBytes: 0,
        rxBytes: 80 * 1000 * 1000,
        txBytes: 0,
        elapsed: const Duration(milliseconds: 500),
      );
      expect(delta, isNull);
    });

    test('instantElapsed accepts only the live window', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(TrafficRateParser.instantElapsed(null, now), isNull);
      expect(
        TrafficRateParser.instantElapsed(
          now.subtract(const Duration(milliseconds: 200)),
          now,
        ),
        isNull,
      );
      expect(
        TrafficRateParser.instantElapsed(
          now.subtract(const Duration(milliseconds: 500)),
          now,
        ),
        const Duration(milliseconds: 500),
      );
      expect(
        TrafficRateParser.instantElapsed(
          now.subtract(const Duration(seconds: 4)),
          now,
        ),
        const Duration(seconds: 4),
      );
      expect(
        TrafficRateParser.instantElapsed(
          now.subtract(const Duration(seconds: 21)),
          now,
        ),
        isNull,
      );
    });
  });

  group('formatTrafficRateCompact', () {
    test('shortens Mbps and Kbps', () {
      expect(formatTrafficRateCompact(2048000), '2.0M');
      expect(formatTrafficRateCompact(850000), '850K');
      expect(formatTrafficRateCompact(42), '42');
      expect(formatTrafficRateCompact(0, measured: true), '0');
      expect(formatTrafficRateCompact(1, measured: true), '1');
    });
  });

  group('aggregateAccountingRows', () {
    test('sums wan rx/tx per tracked ip', () {
      bool isLocal(String ip) => ip.startsWith('192.168.1.');
      final totals = TrafficRateParser.aggregateAccountingRows(
        rows: [
          {
            'src-address': '192.168.1.10',
            'dst-address': '8.8.8.8',
            'bytes': '1000',
          },
          {
            'src-address': '8.8.8.8',
            'dst-address': '192.168.1.10',
            'bytes': '5000',
          },
        ],
        isLocalIp: isLocal,
        trackedIps: {'192.168.1.10'},
      );

      expect(totals['192.168.1.10']?.txBytes, 1000);
      expect(totals['192.168.1.10']?.rxBytes, 5000);
    });
  });

  group('network live total', () {
    test('parent subnet replaces the host queues it contains', () {
      final total = TrafficRateParser.liveTotalFromQueueRows([
        {
          'target': '192.168.88.0/24',
          'parent': 'none',
          'rate': '1000000/9000000',
        },
        {
          'target': '192.168.88.10/32',
          'parent': 'lan',
          'rate': '1000/9000',
        },
        {
          'target': '192.168.88.21/32',
          'parent': 'none',
          'rate': '500000/500000',
        },
      ]);

      expect(total?.txBps, 1000000);
      expect(total?.rxBps, 9000000);
      expect(total?.queueCount, 1);
    });

    test('sums every host queue when no parent is carrying traffic', () {
      final total = TrafficRateParser.liveTotalFromQueueRows([
        for (var i = 1; i <= 20; i++)
          {
            'target': '10.0.0.$i/32',
            'parent': 'none',
            'rate': '1000/2000',
          },
      ]);

      expect(total?.txBps, 20000);
      expect(total?.rxBps, 40000);
      expect(total?.queueCount, 20);
    });

    test('idle parent falls through to every child host queue', () {
      final total = TrafficRateParser.liveTotalFromQueueRows([
        {
          'target': '192.168.88.0/24',
          'parent': 'none',
          'rate': '0/0',
        },
        {
          'target': '192.168.88.10/32',
          'parent': 'lan',
          'rate': '1000/4000',
        },
        {
          'target': '192.168.88.21/32',
          'parent': 'lan',
          'rate': '2000/6000',
        },
      ]);

      expect(total?.txBps, 3000);
      expect(total?.rxBps, 10000);
      expect(total?.queueCount, 2);
    });

    test('idle parent does not hide host rates outside a live total', () {
      final total = TrafficRateParser.liveTotalFromQueueRows([
        {
          'target': '192.168.88.0/24',
          'parent': 'none',
          'rate': '0/0',
        },
        {
          'target': '192.168.88.10/32',
          'parent': 'none',
          'rate': '100/400',
        },
        {
          'target': '10.1.1.5/32',
          'parent': 'none',
          'rate': '50/50',
        },
      ]);

      expect(total?.txBps, 150);
      expect(total?.rxBps, 450);
      expect(total?.queueCount, 2);
    });

    test('broader root queue is not added to the subnet inside it', () {
      final total = TrafficRateParser.liveTotalFromQueueRows([
        {
          'target': '10.0.0.0/8',
          'parent': 'none',
          'rate': '10/20',
        },
        {
          'target': '10.1.0.0/16',
          'parent': 'none',
          'rate': '100/200',
        },
      ]);

      expect(total?.txBps, 10);
      expect(total?.rxBps, 20);
      expect(total?.queueCount, 1);
    });

    test('all-zero host queues are not a network total', () {
      expect(
        TrafficRateParser.liveTotalFromQueueRows([
          {'target': '10.0.0.2/32', 'rate': '0/0'},
          {'target': '10.0.0.3/32', 'rate': '0/0'},
        ]),
        isNull,
      );
    });

    test('interface monitor maps wan rx to download', () {
      final parsed = TrafficRateParser.fromInterfaceMonitor({
        'rx-bits-per-second': '18.5Mbps',
        'tx-bits-per-second': '3.2Mbps',
      });
      expect(parsed?.rxBps, 18500000);
      expect(parsed?.txBps, 3200000);
    });

    test('wan interface comes from the active default route', () {
      expect(
        TrafficRateParser.wanInterfaceFromRoute({
          'dst-address': '0.0.0.0/0',
          'active': 'true',
          'gateway': '1.2.3.4',
          'immediate-gw': '1.2.3.4%pppoe-out1',
        }),
        'pppoe-out1',
      );
      expect(
        TrafficRateParser.wanInterfaceFromRoute({
          'dst-address': '0.0.0.0/0',
          'active': 'true',
          'gateway-status': '1.2.3.4 reachable via ether1',
        }),
        'ether1',
      );
      expect(
        TrafficRateParser.wanInterfaceFromRoute({
          'dst-address': '192.168.88.0/24',
          'active': 'true',
          'gateway': 'bridge',
        }),
        isNull,
      );
      expect(
        TrafficRateParser.wanInterfaceFromRoute({
          'dst-address': '0.0.0.0/0',
          'active': 'false',
          'gateway': 'pppoe-out1',
        }),
        isNull,
      );
    });
  });

  group('aggregateAccountingRows', () {
    test('parses endpoint ports in accounting rows', () {
      bool isLocal(String ip) => ip.startsWith('192.168.1.');
      final totals = TrafficRateParser.aggregateAccountingRows(
        rows: [
          {
            'src-address': '192.168.1.10:54321',
            'dst-address': '8.8.8.8:443',
            'bytes': '2000',
          },
        ],
        isLocalIp: isLocal,
        trackedIps: {'192.168.1.10'},
      );

      expect(totals['192.168.1.10']?.txBytes, 2000);
    });
  });
}
