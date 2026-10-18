import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/sib_package_insight.dart';
import 'deltasib_auth_service.dart';
import 'sib_customer_service.dart';

/// آخرین بستهٔ مشترک. اول از حافظه، بعد از دیسک، بعد از شبکه.
class SibPackageStore {
  SibPackageStore._();

  static const _prefsKey = 'sib_package_credit_v1';
  static const _nameKey = 'sib_customer_name_v1';
  static final ValueNotifier<SibPackageInsight?> listenable = ValueNotifier(null);
  static SibPackageInsight? snapshot;
  static String? displayName;
  static Future<void>? _hydrateOnce;
  static Future<void>? _refreshing;

  static Future<void> hydrate() {
    return _hydrateOnce ??= _readDisk();
  }

  /// اگر نسخه‌ای هست همان را فوری برمی‌گرداند و در پس‌زمینه تازه می‌کند.
  static Future<void> refresh() {
    return _refreshing ??= _refreshBody().whenComplete(() => _refreshing = null);
  }

  static Future<void> _refreshBody() async {
    await hydrate();
    if (snapshot != null && listenable.value == null) {
      listenable.value = snapshot;
    }
    await DeltaSibAuthService().ready;
    final service = SibCustomerService();
    Map<String, dynamic>? credit;
    String? name;
    try {
      final loaded = await Future.wait<Object?>([
        service.loadCredit().then<Object?>((value) => value).catchError((Object e) {
          debugPrint('[SIB_PACKAGE] credit failed: $e');
          return null;
        }),
        service.loadDisplayName(),
      ]);
      credit = loaded[0] as Map<String, dynamic>?;
      name = loaded[1] as String?;
    } catch (e) {
      debugPrint('[SIB_PACKAGE] refresh failed: $e');
      return;
    }
    if (credit == null && (name == null || name.isEmpty)) return;
    final prefs = await SharedPreferences.getInstance();
    if (name != null && name.isNotEmpty) {
      displayName = name;
      await prefs.setString(_nameKey, name);
    }
    if (credit == null) {
      listenable.value = snapshot;
      return;
    }
    try {
      final insight = SibPackageInsight.fromMaps(credit: credit);
      snapshot = insight;
      displayName ??= insight.customerName;
      listenable.value = insight;
      await prefs.setString(_prefsKey, jsonEncode(credit));
      if (displayName != null) {
        await prefs.setString(_nameKey, displayName!);
      }
    } catch (e) {
      debugPrint('[SIB_PACKAGE] refresh failed: $e');
    }
  }

  static Future<void> _readDisk() async {
    if (snapshot != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      displayName ??= prefs.getString(_nameKey);
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      snapshot = SibPackageInsight.fromMaps(
        credit: decoded.map((key, value) => MapEntry('$key', value)),
      );
      listenable.value = snapshot;
    } catch (e) {
      debugPrint('[SIB_PACKAGE] cache unreadable: $e');
    }
  }
}
