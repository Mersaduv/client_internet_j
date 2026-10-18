import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/utils/shamsi_date.dart';
import 'package:jahan_bit/utils/sib_package_insight.dart';
import 'package:jahan_bit/widgets/sib_package_card.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  test('detects a volume package with daily cap and elapsed days', () {
    final insight = SibPackageInsight.fromMaps(
      credit: {
        'ServiceName': 'طلایی',
        'ServiceStatus': 'Active',
        'STrA': '${150 * gb}',
        'STrU': '${110 * gb}',
        'DTrA': '${5 * gb}',
        'StartDate': '2026-01-01 00:00:00',
        'EndDate': '2026-03-02 00:00:00',
        'CurrentDT': '2026-01-22 00:00:00',
        'FairMikrotikRate': '256 Kbps',
      },
    );
    expect(insight.kind, SibPackageKind.volume);
    expect(insight.totalBytes, 150 * gb);
    expect(insight.usedBytes, 110 * gb);
    expect(insight.remainBytes, 40 * gb);
    expect(insight.dailyBytes, 5 * gb);
    expect(insight.totalDays, 60);
    expect(insight.usedDays, 21);
    expect(insight.usageRatio, closeTo(110 / 150, 0.001));
    expect(insight.remainingRatio, closeTo(40 / 150, 0.001));
    expect(insight.notePrimary, '5GB رایگان بعد از تمام شدن محدودیت روزانه');
    expect(insight.noteSecondary, '256 Kbps');
    expect(insight.detectionLabel, 'بسته حجمی با سقف روزانه');
    expect(insight.statusLabel, 'فعال');
    expect(SibPackageInsight.formatBytes(150 * gb, compact: true), '150GB');
  });

  test('finite quota stays a volume package even if the name says unlimited', () {
    final insight = SibPackageInsight.fromMaps(
      credit: {'ServiceName': 'نامحدود شبانه', 'STrA': '${10 * gb}'},
    );
    expect(insight.kind, SibPackageKind.volume);
    expect(insight.title, 'حجم اینترنت');
  });

  test('detects unlimited when there is no finite traffic quota', () {
    final byName = SibPackageInsight.fromMaps(
      credit: {'ServiceName': 'اینترنت نامحدود', 'STrA': '0', 'Period': '30'},
    );
    expect(byName.kind, SibPackageKind.unlimited);
    expect(byName.title, 'اینترنت نامحدود');
    expect(byName.totalDays, 30);

    final byMark = SibPackageInsight.fromMaps(
      credit: {'ServiceName': 'Night', 'STrR': 'UL', 'STiA': '${60 * 86400}'},
    );
    expect(byMark.kind, SibPackageKind.unlimited);
    expect(byMark.totalDays, 60);
  });

  test('reads the live creditinfo shape with commas, slash dates and UL caps', () {
    const gb = 1024 * 1024 * 1024;
    final insight = SibPackageInsight.fromMaps(
      credit: {
        'ServiceStatus': 'Active',
        'ServiceName': '100GB-5Mb-1Month-FRH',
        'StartDate': '2026/10/17',
        'EndDate': '2026/11/16 22:00:12',
        'CurrentDT': '2026/10/17 22:16:49',
        'Period': '0Y, 0M, 30D',
        'STrA': '107,374,182,400',
        'STrU': '0',
        'STrR': '107,374,182,400',
        'DTrA': 'UL',
        'YTrA': 'UL',
        'MTrA': 'UL',
        'ISFairService': 'No',
        'FairRate': null,
        'GiftEndDT': ' 0/00/00 00:00:00',
      },
    );
    expect(insight.kind, SibPackageKind.volume);
    expect(insight.title, 'حجم اینترنت');
    expect(insight.totalBytes, 100 * gb);
    expect(insight.usedBytes, 0);
    expect(insight.remainBytes, 100 * gb);
    expect(insight.dailyBytes, isNull);
    expect(insight.totalDays, 30);
    expect(insight.usedDays, 0);
    expect(insight.noteSecondary, '5 Mbps');
    expect(insight.startText, '2026/10/17');
    expect(insight.endText, '2026/11/16');
    expect(SibPackageInsight.formatBytes(insight.totalBytes, compact: true), '100GB');
  });

  test('does not treat an API error as an unlimited package', () {
    expect(
      SibPackageInsight.creditRecords({'Error': -6, 'Message': 'Invalid token'}),
      isEmpty,
    );
    expect(
      SibPackageInsight.errorText({'Message': 'Invalid token'}),
      'Invalid token',
    );
  });

  test('converts a known gregorian day to Afghan solar قوس', () {
    final date = ShamsiDate.fromDateTime(DateTime(2024, 12, 14));
    expect(date.month, 9);
    expect(date.day, 24);
    expect(date.monthName, 'قوس');
    expect(ShamsiDate.label(DateTime(2024, 12, 14, 14, 34), withTime: true), contains('بعد از ظهر'));
  });

  test('prefers the active credit record', () {
    final records = SibPackageInsight.creditRecords([
      {'ServiceName': 'قدیمی', 'ServiceStatus': 'Expire', 'STrA': '1'},
      {'ServiceName': 'جاری', 'ServiceStatus': 'Active', 'STrA': '2'},
    ]);
    expect(records.first['ServiceName'], 'جاری');
  });

  testWidgets('volume card shows the package figures', (tester) async {
    final insight = SibPackageInsight.fromMaps(
      credit: {
        'STrA': '${150 * gb}',
        'STrU': '${110 * gb}',
        'DTrA': '${5 * gb}',
        'StartDate': '2026-01-01',
        'EndDate': '2026-03-02',
        'CurrentDT': '2026-01-22',
        'FairMikrotikRate': '256k',
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SibPackageCard(insight: insight))),
    );
    expect(find.text('حجم اینترنت'), findsOneWidget);
    expect(find.text('150GB'), findsOneWidget);
    expect(find.text('محدودیت روزانه 5GB'), findsOneWidget);
    expect(find.text('گراف مصرف بسته شما'), findsOneWidget);
    expect(find.textContaining('مانده 40GB'), findsOneWidget);
    expect(find.textContaining('شروع'), findsOneWidget);
    expect(find.textContaining('۶۰'), findsOneWidget);
    expect(find.textContaining('۲۱'), findsOneWidget);
    expect(find.text('256 Kbps'), findsOneWidget);
  });

  testWidgets('unlimited card shows start and end without a volume', (tester) async {
    final insight = SibPackageInsight.fromMaps(
      credit: {'ServiceName': 'اینترنت نامحدود'},
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SibPackageCard(insight: insight))),
    );
    expect(find.text('اینترنت نامحدود'), findsOneWidget);
    expect(find.textContaining('شروع'), findsOneWidget);
    expect(find.textContaining('ختم'), findsOneWidget);
    expect(find.textContaining('۰ روز'), findsNWidgets(2));
    expect(find.textContaining('GB'), findsNothing);
  });

  test('greeting uses the subscriber name from SIB', () {
    expect(
      SibPackageInsight.greetingLine('احمد کریمی عزیزی'),
      'سلام احمد کریمی عزیزی وقت بخیر',
    );
    expect(SibPackageInsight.greetingLine('  '), 'سلام وقت بخیر');
    expect(
      SibPackageInsight.readPersonName({
        'Name': 'احمد',
        'Family': 'کریمی عزیزی',
      }),
      'احمد کریمی عزیزی',
    );
    expect(
      SibPackageInsight.readPersonName({
        'username': 'api',
        'name': 'تست',
        'family': 'تست',
      }),
      'تست تست',
    );
    expect(SibPackageInsight.greetingLine('تست تست'), 'سلام تست تست وقت بخیر');
  });
}
