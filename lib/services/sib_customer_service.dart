import 'package:flutter/foundation.dart';

import '../utils/sib_package_insight.dart';
import 'deltasib_auth_service.dart';
import 'sib_volume_client.dart';

/// خواندن اطلاعات مشترک از صفحه‌های تست وب‌سرویس دلتاسیب (همان میزبان ورکر).
class SibCustomerService {
  SibCustomerService({DeltaSibAuthService? auth})
      : _auth = auth ?? DeltaSibAuthService();

  final DeltaSibAuthService _auth;

  Future<SibCustomerSnapshot> load({String? username}) async {
    final credit = await loadCredit(username: username);
    return SibCustomerSnapshot(
      username: (username ?? await _auth.savedUsername() ?? '').trim(),
      credit: credit,
      status: null,
      services: null,
    );
  }

  /// فقط creditinfo همین مشترک؛ ورکر فیلتر را با یوزر Api سرور می‌زند.
  Future<Map<String, dynamic>?> loadCredit({String? username}) async {
    final volume = await _volume(username);
    return volume.credit;
  }

  /// نام و تخلص از user/list.
  ///
  /// صفحهٔ test.user.list.php فیلتر را به API نمی‌فرستد و پورت ۱۰۴۳ از بیرون
  /// در دسترس نیست. همان صفحهٔ creditinfo پارامتر Action و Filter را به
  /// `https://127.0.0.1:1043/1.0/` می‌رساند، پس Action=list همان فهرست PDF است.
  Future<String?> loadDisplayName({String? username}) async {
    try {
      final volume = await _volume(username);
      if (volume.name != null && volume.name!.isNotEmpty) return volume.name;
      return SibPackageInsight.readPersonName(
        volume.credit?.map((key, value) => MapEntry(key, '$value')),
      );
    } catch (e) {
      debugPrint('[SIB_NAME] $e');
      return null;
    }
  }

  Future<SibVolume> _volume(String? username) async {
    final saved = await _auth.savedUsername();
    final user = (username ?? saved ?? '').trim();
    if (user.isEmpty) {
      throw DeltaSibAuthException('نام کاربری مشترک خالی است.');
    }
    return SibVolumeClient.fetch(username: user, origin: await _origin());
  }

  Future<String> _origin() async {
    // کد و نشست فقط روی ورکر هرات است. ولایت فقط کاتالوگ بسته را عوض می‌کند.
    return DeltaSibAuthService.defaultOrigin;
  }

  static String? extractResultCell(String html) => sibExtractResultCell(html);
}

class SibCustomerSnapshot {
  const SibCustomerSnapshot({
    required this.username,
    required this.credit,
    required this.status,
    required this.services,
  });

  final String username;
  final Object? credit;
  final Object? status;
  final Object? services;
}
