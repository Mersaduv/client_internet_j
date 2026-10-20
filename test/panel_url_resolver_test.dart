import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/data/internet_packages_data.dart';
import 'package:jahan_bit/services/deltasib_auth_service.dart';
import 'package:jahan_bit/utils/panel_url_resolver.dart';

void main() {
  test('access code accepts letters and digits', () {
    expect(DeltaSibAuthService.normalizeAccessCode('ab12cd34ef'), 'AB12CD34EF');
    expect(DeltaSibAuthService.normalizeAccessCode('1234567890'), '1234567890');
    expect(DeltaSibAuthService.normalizeAccessCode('abc'), isNull);
    expect(DeltaSibAuthService.normalizeAccessCode('کد۱۲۳۴۵۶۷۸۹۰'), isNull);
  });

  test('herat uses HTTPS worker only (no public cleartext)', () {
    final list = PanelUrlResolver.candidatesFor(PackageProvince.herat);
    expect(list, hasLength(1));
    expect(list.first, startsWith('https://'));
    expect(list.any((u) => u.startsWith('http://165.')), isFalse);
  });

  test('nimroz codes use the nimroz worker, herat and farah stay on herat', () {
    expect(
      DeltaSibAuthService.codeWorkerFor(PackageProvince.nimroz),
      'https://jb-nimroz.mersadkarimi001.workers.dev',
    );
    expect(
      DeltaSibAuthService.codeWorkerFor(PackageProvince.herat),
      DeltaSibAuthService.defaultOrigin,
    );
    expect(
      DeltaSibAuthService.codeWorkerFor(PackageProvince.farah),
      DeltaSibAuthService.defaultOrigin,
    );
  });

  test('nimroz panel is the HTTPS worker only', () {
    final list = PanelUrlResolver.candidatesFor(PackageProvince.nimroz);
    expect(list, [
      'https://jb-nimroz.mersadkarimi001.workers.dev/users/',
    ]);
    expect(PackageProvince.nimroz.servicePanelUrl, list.first);
    expect(list.join(' '), isNot(contains('http://')));
  });

  test('farah uses the same Herat panel link', () {
    expect(
      PanelUrlResolver.candidatesFor(PackageProvince.farah),
      PanelUrlResolver.candidatesFor(PackageProvince.herat),
    );
    expect(
      PackageProvince.farah.sibApiOrigin,
      PackageProvince.herat.sibApiOrigin,
    );
    expect(
      PackageProvince.farah.servicePanelUrl,
      'https://jb-herat.mersadkarimi001.workers.dev/users/',
    );
    expect(
      PanelUrlResolver.candidatesFor(PackageProvince.farah).join(' '),
      isNot(contains('jb-farah')),
    );
  });

  test('a single panel link has no failover', () {
    final first = PanelUrlResolver.primaryFor(PackageProvince.nimroz);
    expect(
      PanelUrlResolver.nextAfter(PackageProvince.nimroz, first),
      isNull,
    );
  });
}
