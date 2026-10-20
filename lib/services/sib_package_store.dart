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
  static const _ownerKey = 'sib_package_owner_v1';
  static String? _boundUsername;
  static final ValueNotifier<SibPackageInsight?> listenable = ValueNotifier(null);
  static SibPackageInsight? snapshot;
  static String? displayName;
  static Future<void>? _hydrateOnce;
  static Future<void>? _refreshing;

  static Future<void> hydrate() {
    return _hydrateOnce ??= _readDisk();
  }

  /// حجم کش‌شدهٔ مشترک قبلی را کنار می‌گذارد تا صفحهٔ خانه مال همین نام کاربری باشد.
  static void prepareFor(String username) {
    final name = username.trim();
    if (name.isEmpty || name == _boundUsername) return;
    _boundUsername = name;
    snapshot = null;
    displayName = null;
    listenable.value = null;
    _hydrateOnce = null;
  }

  static Future<void> clear() async {
    _boundUsername = null;
    snapshot = null;
    displayName = null;
    listenable.value = null;
    _hydrateOnce = null;
    _refreshing = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_nameKey);
      await prefs.remove(_ownerKey);
    } catch (e) {
      debugPrint('[SIB_PACKAGE] clear failed: $e');
    }
  }

  /// اگر نسخه‌ای هست همان را فوری برمی‌گرداند و در پس‌زمینه تازه می‌کند.
  ///
  /// [force] waits for any in-flight refresh, then always hits DeltaSIB again.
  static Future<void> refresh({bool force = false}) {
    if (!force) {
      final existing = _refreshing;
      if (existing != null) return existing;
      late final Future<void> tracked;
      tracked = _refreshBody().whenComplete(() {
        if (identical(_refreshing, tracked)) _refreshing = null;
      });
      _refreshing = tracked;
      return tracked;
    }
    return _refreshForced();
  }

  static Future<void> _refreshForced() async {
    final current = _refreshing;
    if (current != null) {
      await current;
    }
    late final Future<void> tracked;
    tracked = _refreshBody().whenComplete(() {
      if (identical(_refreshing, tracked)) _refreshing = null;
    });
    _refreshing = tracked;
    await tracked;
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
          if (e is DeltaSibAuthException && e.sessionExpired) throw e;
          debugPrint('[SIB_PACKAGE] credit failed: $e');
          return null;
        }),
        service.loadDisplayName(),
      ]);
      credit = loaded[0] as Map<String, dynamic>?;
      name = loaded[1] as String?;
    } catch (e) {
      if (e is DeltaSibAuthException && e.sessionExpired) {
        await endSubscriberSession();
      }
      debugPrint('[SIB_PACKAGE] refresh failed: $e');
      return;
    }
    if (credit == null && (name == null || name.isEmpty)) return;
    final owner = (await DeltaSibAuthService().savedUsername())?.trim();
    if (owner == null || owner.isEmpty) return;
    if (_boundUsername != null && _boundUsername != owner) return;
    _boundUsername = owner;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, owner);
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
      await DeltaSibAuthService().ready;
      final saved = (await DeltaSibAuthService().savedUsername())?.trim();
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(_ownerKey)?.trim();
      if (saved == null || saved.isEmpty || owner != saved) return;
      if (_boundUsername != null && _boundUsername != saved) return;
      _boundUsername = saved;
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
