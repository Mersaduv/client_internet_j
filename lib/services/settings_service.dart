import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mikrotik_connection.dart';
import '../utils/webview_host_allowlist.dart';
import 'app_secure_storage.dart';

/// سرویس برای مدیریت تنظیمات اتصال MikroTik
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyHost = 'mikrotik_host';
  static const String _keyPort = 'mikrotik_port';
  static const String _keyUseSsl = 'mikrotik_use_ssl';
  static const String _keyServiceUrl = 'internet_service_url';
  static const String _keyLoginTimestamp = 'login_timestamp';
  static const String _keyLastActivity = 'last_activity_at';
  static const Duration inactivityLimit = Duration(days: 365);
  static const Duration _activityWriteGap = Duration(hours: 12);
  static const String _keyRememberMe = 'remember_me';
  static const String _keyLanguage = 'app_language';
  static const String _keyThemeMode = 'app_theme_mode';
  static const String _keyPackageProvince = 'package_province';
  static const String _keySibWorkerOrigin = 'sib_worker_origin';

  /// برای همگام‌سازی ولایت بین تب بسته‌ها و سرویس اینترنت
  final ValueNotifier<String?> packageProvinceListenable =
      ValueNotifier<String?>(null);

  static final _secureStorage = AppSecureStorage.instance;

  static const _keyUsername = 'secure_username';
  static const _keyPassword = 'secure_password';

  // مقادیر پیش‌فرض
  static const String _defaultHost = '192.168.88.1';
  static const bool _defaultUseSsl = false;
  /// آدرس پیش‌فرض پنل کاربری سرویس اینترنت (عمومی = فقط HTTPS)
  static const String _defaultServiceUrl =
      'https://jb-herat.mersadkarimi001.workers.dev/users/';
  static const String _defaultLanguage = 'fa';
  static const String _defaultThemeMode = 'dark';

  // Cache برای تنظیمات (برای جلوگیری از خطا در صورت مشکل shared_preferences)
  String? _cachedHost;
  int? _cachedPort;
  bool? _cachedUseSsl;
  String? _cachedServiceUrl;
  String? _cachedLanguage;
  String? _cachedThemeMode;
  String? _cachedPackageProvince;

  /// دریافت Host
  Future<String> getHost() async {
    if (_cachedHost != null) {
      return _cachedHost!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedHost = prefs.getString(_keyHost) ?? _defaultHost;
      return _cachedHost!;
    } catch (e) {
      // در صورت خطا، از مقدار پیش‌فرض استفاده کن
      _cachedHost = _defaultHost;
      return _defaultHost;
    }
  }

  /// ذخیره Host
  Future<void> setHost(String host) async {
    _cachedHost = host;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyHost, host);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط در حافظه نگه دار
    }
  }

  /// دریافت Port — همیشه پورت API پروژه (8728)
  Future<int> getPort() async {
    return _cachedPort ??= MikroTikConnection.apiPort;
  }

  /// ذخیره Port — پورت API همیشه 8728 است
  Future<void> setPort(int port) async {
    _cachedPort = MikroTikConnection.apiPort;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyPort, MikroTikConnection.apiPort);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط در حافظه نگه دار
    }
  }

  /// دریافت UseSsl
  Future<bool> getUseSsl() async {
    if (_cachedUseSsl != null) {
      return _cachedUseSsl!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedUseSsl = prefs.getBool(_keyUseSsl) ?? _defaultUseSsl;
      return _cachedUseSsl!;
    } catch (e) {
      // در صورت خطا، از مقدار پیش‌فرض استفاده کن
      _cachedUseSsl = _defaultUseSsl;
      return _defaultUseSsl;
    }
  }

  /// ذخیره UseSsl
  Future<void> setUseSsl(bool useSsl) async {
    _cachedUseSsl = useSsl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyUseSsl, useSsl);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط در حافظه نگه دار
    }
  }

  /// آدرس پیش‌فرض عمومی پنل سرویس اینترنت
  static String get defaultServiceUrl => _defaultServiceUrl;

  /// دریافت URL سرویس اینترنت (در صورت خالی/قدیمی/غیرمجاز → پیش‌فرض فعلی)
  Future<String> getServiceUrl() async {
    if (_cachedServiceUrl != null &&
        _cachedServiceUrl!.trim().isNotEmpty &&
        WebViewHostAllowlist.isAllowedUrl(_cachedServiceUrl)) {
      return _cachedServiceUrl!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      var url = (prefs.getString(_keyServiceUrl) ?? '').trim();
      // لینک خالی، قدیمی یا خارج از allowlist را با پیش‌فرض جایگزین کن
      if (url.isEmpty || !WebViewHostAllowlist.isAllowedUrl(url)) {
        url = _defaultServiceUrl;
        await prefs.setString(_keyServiceUrl, url);
      }
      _cachedServiceUrl = url;
      return _cachedServiceUrl!;
    } catch (e) {
      _cachedServiceUrl = _defaultServiceUrl;
      return _defaultServiceUrl;
    }
  }

  /// ذخیره URL سرویس اینترنت — فقط میزبان‌های allowlist
  Future<void> setServiceUrl(String url) async {
    final trimmed = url.trim();
    if (!WebViewHostAllowlist.isAllowedUrl(trimmed)) {
      throw ArgumentError('URL خارج از فهرست میزبان‌های مجاز پنل است');
    }
    _cachedServiceUrl = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyServiceUrl, trimmed);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط در حافظه نگه دار
    }
  }

  /// دریافت همه تنظیمات
  Future<Map<String, dynamic>> getAllSettings() async {
    return {
      'host': await getHost(),
      'port': await getPort(),
      'useSsl': await getUseSsl(),
      'serviceUrl': await getServiceUrl(),
    };
  }

  /// ذخیره زمان لاگین
  Future<void> setLoginTimestamp() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLoginTimestamp, timestamp);
    } catch (e) {
      // اگر shared_preferences کار نکرد، نادیده بگیر
    }
  }

  /// دریافت زمان لاگین
  Future<int?> getLoginTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyLoginTimestamp);
    } catch (e) {
      return null;
    }
  }

  /// ورود ذخیره شده و در یک سال اخیر فعالیت داشته است.
  Future<bool> isLoginExpired() async {
    return !await hasValidSession();
  }

  Future<int?> getLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyLastActivity);
    } catch (_) {
      return null;
    }
  }

  /// باز شدن برنامه فعالیت است. نوشتن را تا ۱۲ ساعت یک‌بار انجام می‌دهد.
  Future<void> markActivity() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = await getLastActivity();
    if (previous != null && now - previous < _activityWriteGap.inMilliseconds) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastActivity, now);
    } catch (_) {}
  }

  Future<void> clearLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastActivity);
    } catch (_) {}
  }

  /// یک سال بدون باز شدن برنامه.
  /// نبودن مهر فعالیت یعنی این نسخه هنوز فعالیتی ننوشته؛ همین باز شدن فعالیت است
  /// و نباید با زمان ورودِ قدیمی اشتباه گرفته شود.
  Future<bool> isInactiveYear() async {
    final activity = await getLastActivity();
    if (activity == null) return false;
    final seen = DateTime.fromMillisecondsSinceEpoch(activity);
    return DateTime.now().difference(seen) >= inactivityLimit;
  }

  /// پاک کردن زمان لاگین (برای خروج)
  Future<void> clearLoginTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLoginTimestamp);
    } catch (e) {
      // اگر shared_preferences کار نکرد، نادیده بگیر
    }
  }

  /// آیا کاربر «مرا به خاطر بسپار» را فعال کرده است
  Future<bool> getRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyRememberMe) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// ذخیره وضعیت «مرا به خاطر بسپار»
  Future<void> setRememberMe(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyRememberMe, value);
    } catch (e) {
      // نادیده
    }
  }

  /// ذخیره اعتبارنامه پس از ورود موفق (Keychain / Keystore)
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    await _secureStorage.write(key: _keyUsername, value: username);
    await _secureStorage.write(key: _keyPassword, value: password);
  }

  /// بازیابی اعتبارنامه ذخیره‌شده
  Future<Map<String, String>?> getSavedCredentials() async {
    final username = await _secureStorage.read(key: _keyUsername);
    final password = await _secureStorage.read(key: _keyPassword);
    if (username == null || password == null) {
      return null;
    }
    return {'username': username, 'password': password};
  }

  /// پاک کردن اعتبارنامه (خروج یا انقضای session)
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _keyUsername);
    await _secureStorage.delete(key: _keyPassword);
  }

  /// پاک‌سازی کامل داده‌های محلی اپ (حریم خصوصی / معادل حذف دادهٔ روی دستگاه)
  Future<void> clearAllLocalData() async {
    await clearCredentials();
    await clearLoginTimestamp();
    _cachedHost = null;
    _cachedPort = null;
    _cachedUseSsl = null;
    _cachedServiceUrl = null;
    _cachedLanguage = null;
    _cachedThemeMode = null;
    _cachedPackageProvince = null;
    packageProvinceListenable.value = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyHost);
      await prefs.remove(_keyPort);
      await prefs.remove(_keyUseSsl);
      await prefs.remove(_keyServiceUrl);
      await prefs.remove(_keyLoginTimestamp);
      await prefs.remove(_keyLastActivity);
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keyLanguage);
      await prefs.remove(_keyThemeMode);
      await prefs.remove(_keyPackageProvince);
      await prefs.remove(_keySibWorkerOrigin);
      await prefs.remove('banned_device_fingerprints');
      // اثر انگشت/مسدودسازی محلی دستگاه‌ها اگر با کلیدهای prefs ذخیره شده باشند
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('ban_') ||
            key.startsWith('fingerprint_') ||
            key.startsWith('client_') ||
            key.startsWith('device_') ||
            key.startsWith('traffic_')) {
          await prefs.remove(key);
        }
      }
    } catch (_) {
      // فقط cache را پاک کردیم
    }
  }

  /// تا خروج معتبر است، مگر یک سال هیچ فعالیتی نباشد.
  Future<bool> hasValidSession() async {
    final timestamp = await getLoginTimestamp();
    if (timestamp == null) return false;
    return !await isInactiveYear();
  }

  /// دریافت زبان برنامه
  Future<String> getLanguage() async {
    if (_cachedLanguage != null) {
      return _cachedLanguage!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedLanguage = prefs.getString(_keyLanguage) ?? _defaultLanguage;
      return _cachedLanguage!;
    } catch (e) {
      // در صورت خطا، از مقدار پیش‌فرض استفاده کن
      _cachedLanguage = _defaultLanguage;
      return _defaultLanguage;
    }
  }

  /// ذخیره زبان برنامه
  Future<void> setLanguage(String languageCode) async {
    _cachedLanguage = languageCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLanguage, languageCode);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط در حافظه نگه دار
    }
  }

  /// دریافت主题模式
  Future<String> getThemeMode() async {
    if (_cachedThemeMode != null) {
      return _cachedThemeMode!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedThemeMode = prefs.getString(_keyThemeMode) ?? _defaultThemeMode;
      return _cachedThemeMode!;
    } catch (e) {
      // در صورت خطا، از مقدار پیش‌فرض استفاده کن
      _cachedThemeMode = _defaultThemeMode;
      return _defaultThemeMode;
    }
  }

  /// 将字符串转换为 ThemeMode
  ThemeMode stringToThemeMode(String mode) {
    switch (mode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark; // Default fallback: dark
    }
  }

  /// 将 ThemeMode 转换为字符串
  String themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// 保存主题模式
  Future<void> setThemeMode(String themeMode) async {
    _cachedThemeMode = themeMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, themeMode);
    } catch (e) {
      // 如果 shared_preferences 不工作，只在内存中保存
    }
  }

  /// 保存 ThemeMode
  Future<void> setThemeModeEnum(ThemeMode themeMode) async {
    await setThemeMode(themeModeToString(themeMode));
  }

  /// 获取 ThemeMode
  Future<ThemeMode> getThemeModeEnum() async {
    final mode = await getThemeMode();
    return stringToThemeMode(mode);
  }

  /// ولایت بسته‌های اینترنتی ذخیره‌شده — null یعنی هنوز انتخاب نشده
  Future<String?> getPackageProvinceId() async {
    if (_cachedPackageProvince != null) {
      final id =
          _cachedPackageProvince!.isEmpty ? null : _cachedPackageProvince;
      if (packageProvinceListenable.value != id) {
        packageProvinceListenable.value = id;
      }
      return id;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyPackageProvince);
      _cachedPackageProvince = value ?? '';
      final id = (value == null || value.isEmpty) ? null : value;
      if (packageProvinceListenable.value != id) {
        packageProvinceListenable.value = id;
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  /// ورکری که کد این نشست را ساخته است. خالی یعنی هرات.
  Future<String?> getSibWorkerOrigin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keySibWorkerOrigin);
      if (value == null || value.isEmpty) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSibWorkerOrigin(String origin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySibWorkerOrigin, origin);
    } catch (_) {}
  }

  Future<void> clearSibWorkerOrigin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySibWorkerOrigin);
    } catch (_) {}
  }

  /// ذخیره ولایت پیش‌فرض (بسته‌ها + سرویس اینترنت)
  Future<void> setPackageProvinceId(String provinceId) async {
    _cachedPackageProvince = provinceId;
    packageProvinceListenable.value = provinceId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPackageProvince, provinceId);
    } catch (_) {
      // فقط در حافظه نگه دار
    }
  }

  /// بازنشانی به تنظیمات پیش‌فرض
  Future<void> resetToDefaults() async {
    _cachedHost = null;
    _cachedPort = null;
    _cachedUseSsl = null;
    _cachedServiceUrl = null;
    _cachedLanguage = null;
    _cachedThemeMode = null;
    _cachedPackageProvince = null;
    packageProvinceListenable.value = null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyHost);
      await prefs.remove(_keyPort);
      await prefs.remove(_keyUseSsl);
      await prefs.remove(_keyServiceUrl);
      await prefs.remove(_keyLanguage);
      await prefs.remove(_keyThemeMode);
      await prefs.remove(_keyPackageProvince);
      await prefs.remove(_keySibWorkerOrigin);
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط cache را پاک کن
    }
  }
}

