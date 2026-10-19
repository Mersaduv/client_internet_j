import 'package:flutter/foundation.dart';

import '../utils/sib_package_insight.dart';
import 'deltasib_auth_service.dart';
import 'review_demo_account.dart';
import 'review_router_log.dart';
import 'sib_package_store.dart';

/// حجم زندهٔ jb.admin را بعد از ورود شبیه‌ساز، فقط با نام کاربری، از ورکر می‌گیرد.
class ReviewDeltaSibSync {
  ReviewDeltaSibSync._();

  static Future<void> fetch({
    required String username,
    required String password,
    required String origin,
  }) async {
    if (!ReviewDemoAccount.matches(username, password)) {
      return;
    }
    try {
      await DeltaSibAuthService().rememberSubscriber(username.trim());
      await SibPackageStore.refresh(force: true);
      final insight = SibPackageStore.snapshot;
      final name = SibPackageStore.displayName;
      ReviewRouterLog.instance.recordNote(
        label: 'DeltaSIB live',
        lines: [
          'account=${ReviewDemoAccount.username}',
          'origin=$origin',
        ],
        body: _summary(insight, name),
      );
    } catch (e) {
      debugPrint('[REVIEW_SIB] live fetch failed: $e');
      ReviewRouterLog.instance.recordNote(
        label: 'DeltaSIB live',
        lines: [
          'account=${ReviewDemoAccount.username}',
          'origin=$origin',
        ],
        body: 'FAILED  $e',
      );
    }
  }

  static String _summary(SibPackageInsight? insight, String? name) {
    if (insight == null && (name == null || name.isEmpty)) {
      return 'login finished; package body was empty';
    }
    final customer = insight?.customerName;
    final status = insight?.statusLabel;
    final lines = <String>[
      if (name != null && name.isNotEmpty) 'name=$name',
      if (customer != null && customer.isNotEmpty) 'customer=$customer',
      if (insight != null) 'package=${insight.title}',
      if (status != null && status.isNotEmpty) 'status=$status',
    ];
    return lines.isEmpty ? 'login finished' : lines.join('\n');
  }
}
