import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/data/internet_packages_data.dart';
import 'package:jahan_bit/utils/panel_url_resolver.dart';

void main() {
  test('herat uses HTTPS worker only (no public cleartext)', () {
    final list = PanelUrlResolver.candidatesFor(PackageProvince.herat);
    expect(list, hasLength(1));
    expect(list.first, startsWith('https://'));
    expect(list.any((u) => u.startsWith('http://165.')), isFalse);
  });

  test('nimroz prefers LAN then HTTPS worker', () {
    final list = PanelUrlResolver.candidatesFor(PackageProvince.nimroz);
    expect(list.first, contains('192.168.12.12'));
    expect(list.any((u) => u.contains('jb-nimroz')), isTrue);
  });

  test('nextAfter walks failover chain for LAN provinces', () {
    final first = PanelUrlResolver.primaryFor(PackageProvince.farah);
    final second = PanelUrlResolver.nextAfter(PackageProvince.farah, first);
    expect(second, isNotNull);
    expect(second, isNot(first));
    expect(
      PanelUrlResolver.nextAfter(PackageProvince.farah, second!),
      isNull,
    );
  });
}
