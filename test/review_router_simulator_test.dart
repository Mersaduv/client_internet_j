import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/models/mikrotik_connection.dart';
import 'package:jahan_bit/services/mikrotik_service.dart';
import 'package:jahan_bit/services/review_demo_account.dart';
import 'package:jahan_bit/services/review_router_log.dart';
import 'package:jahan_bit/services/review_router_os.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReviewRouterOs.instance.reset();
    ReviewRouterLog.instance.clear();
  });

  test('review account is the tester username', () {
    expect(ReviewDemoAccount.matches('jb.admin', 'admin123'), isTrue);
    expect(ReviewDemoAccount.matches('jb.admin ', 'jb@admin120'), isTrue);
    expect(ReviewDemoAccount.matches('JB.admin', 'admin123'), isFalse);
    expect(ReviewDemoAccount.matches('jb.admin', ''), isFalse);
    expect(ReviewDemoAccount.matches('subscriber', 'admin123'), isFalse);
  });

  test('simulator lease print, ban, speed, and lock use RouterOS sentences', () async {
    final service = ReviewSimulatedMikroTikService();
    final connected = await service.connect(
      MikroTikConnection(
        host: '10.0.0.1',
        username: ReviewDemoAccount.username,
        password: ReviewDemoAccount.simulatorPassword,
      ),
    );
    expect(connected, isTrue);
    expect(service.isConnected, isTrue);

    final leases = await service.getPhase1BoundDhcpLeases();
    expect(
      leases.map((lease) => lease['address']),
      containsAll(<String>[
        '192.168.88.10',
        '192.168.88.21',
        '192.168.88.34',
      ]),
    );

    expect(await service.isNewConnectionsLocked(), isFalse);
    expect(await service.lockNewConnections(), isTrue);
    expect(await service.isNewConnectionsLocked(), isTrue);
    expect(await service.unlockNewConnections(), isTrue);
    expect(await service.isNewConnectionsLocked(), isFalse);

    expect(
      await service.banClient(
        '192.168.88.21',
        macAddress: 'AA:BB:CC:DD:EE:21',
      ),
      isTrue,
    );
    final banned = await service.getBannedClientsFast();
    expect(
      banned.any((row) => row['address'] == '192.168.88.21'),
      isTrue,
    );

    expect(await service.unbanClient('192.168.88.21', macAddress: 'AA:BB:CC:DD:EE:21'), isTrue);
    final bannedAfter = await service.getBannedClientsFast();
    expect(
      bannedAfter.any((row) => row['address'] == '192.168.88.21'),
      isFalse,
    );

    expect(await service.setClientSpeed('192.168.88.34', '2M/2M'), isTrue);
    final speed = await service.getClientSpeed('192.168.88.34');
    expect(speed, isNotNull);
    expect(speed!['max_limit'], '2M/2M');

    final paths = ReviewRouterLog.instance.entries.map((entry) => entry.commandPath);
    expect(paths, contains('/ip/dhcp-server/set'));
    expect(paths, contains('/ip/firewall/raw/add'));
    expect(paths, contains('/ip/dhcp-server/lease/set'));

    service.disconnect();
  });
}
