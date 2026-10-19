import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mikrotik_connection.dart';
import '../utils/webview_host_allowlist.dart';

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
  static const String _keyRememberMe = 'remember_me';
  static const String _keyLanguage = 'app_language';
  static const String _keyThemeMode = 'app_theme_mode';
  static const String _keyPackageProvince = 'package_province';

  /// برای همگام‌سازی ولایت بین تب بسته‌ها و سرویس اینترنت
  final ValueNotifier<String?> packageProvinceListenable =
      ValueNotifier<String?>(null);

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyUsername = 'secure_username';
  static const _keyPassword = 'secure_password';

  // مقادیر پیش‌فرض
  static const String _defaultHost = '192.168.88.1';
  static const bool _defaultUseSsl = false;
  /// آدرس پیش‌فرض پنل کاربری سرویس اینترنت (عمومی = فقط HTTPS)
  static const String _defaultServiceUrl =
      'https://jb-herat.mersadkarimi001.workers.dev/users/';
  /// URLهای قدیمی ذخیره‌شده روی بعضی دستگاه‌ها — فقط برای مهاجرت
  static const String _legacyDefaultServiceUrl = 'http://user.ariyabod.af/users';
  static const String _legacyHeratHttpServiceUrl =
      'http://165.99.189.40:9394/users/';
  static const String _legacyHeratHttpsIpServiceUrl =
      'https://165.99.189.40:9394/users/';
  // Keep migrating old public cleartext / IP-TLS away from prefs.
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

  /// دریافت Port — همیشه پورت API پروژه (2752)
  Future<int> getPort() async {
    return _cachedPort ??= MikroTikConnection.apiPort;
  }

  /// ذخیره Port — پورت API همیشه 2752 است
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
      if (url.isEmpty ||
          _isLegacyDefaultServiceUrl(url) ||
          !WebViewHostAllowlist.isAllowedUrl(url)) {
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

  bool _isLegacyDefaultServiceUrl(String url) {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    final legacy = _legacyDefaultServiceUrl.replaceAll(RegExp(r'/+$'), '');
    final legacyHeratHttp =
        _legacyHeratHttpServiceUrl.replaceAll(RegExp(r'/+$'), '');
    final legacyHeratHttpsIp =
        _legacyHeratHttpsIpServiceUrl.replaceAll(RegExp(r'/+$'), '');
    // مسیرهای قدیمی IP عمومی را به HTTPS Worker مهاجرت بده.
    return normalized == legacy ||
        normalized == legacyHeratHttp ||
        normalized == legacyHeratHttpsIp;
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

  /// بررسی انقضای لاگین (14 روز)
  Future<bool> isLoginExpired() async {
    final timestamp = await getLoginTimestamp();
    if (timestamp == null) {
      return true; // اگر زمان لاگین وجود نداشته باشد، منقضی شده در نظر بگیر
    }
    
    final loginDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(loginDate);
    
    // اگر 14 روز یا بیشتر گذشته باشد، منقضی شده است
    return difference.inDays >= 14;
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
    final stored = await Future.wait<String?>([
      _secureStorage.read(key: _keyUsername),
      _secureStorage.read(key: _keyPassword),
    ]);
    final username = stored[0];
    final password = stored[1];
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
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keyLanguage);
      await prefs.remove(_keyThemeMode);
      await prefs.remove(_keyPackageProvince);
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

  /// session معتبر: login_timestamp وجود دارد و کمتر از ۱۴ روز گذشته
  Future<bool> hasValidSession() async {
    final timestamp = await getLoginTimestamp();
    if (timestamp == null) {
      return false;
    }
    final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(loginTime).inDays < 14;
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
    } catch (e) {
      // اگر shared_preferences کار نکرد، فقط cache را پاک کن
    }
  }
}

