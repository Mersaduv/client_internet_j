import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/internet_packages_data.dart';
import '../data/support_contacts.dart';
import '../models/mikrotik_connection.dart';
import '../services/deltasib_auth_service.dart';
import '../services/review_demo_account.dart';
import '../services/sib_package_store.dart';
import '../services/mikrotik_service_manager.dart';
import '../services/settings_service.dart';
import '../services/network_info_service.dart';
import '../utils/app_localizations.dart';
import '../widgets/province_selector.dart';
import '../utils/app_theme.dart';
import '../widgets/cosmic_background.dart';

/// صفحه ورود مدرن و حرفه‌ای
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accessCodeController = TextEditingController();

  bool _isConnecting = false;
  PackageProvince? _province;
  bool _provinceDialogOpen = false;
  String? _errorMessage;
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _checkLoginExpiration();
    _loadProvince();
    _autoSetRouterHostFromGateway();
  }

  Future<void> _loadProvince() async {
    if (!mounted) return;
    final savedProvince = PackageProvinceX.tryParse(
      await _settingsService.getPackageProvinceId(),
    );
    if (!mounted) return;
    setState(() {
      _province = savedProvince;
    });
    if (savedProvince == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickProvinceOnce();
      });
    }
  }

  Future<void> _pickProvinceOnce() async {
    if (!mounted || _province != null || _provinceDialogOpen) return;
    _provinceDialogOpen = true;
    final picked = await showLoginProvinceDialog(context);
    _provinceDialogOpen = false;
    if (!mounted || picked == null) return;
    await _settingsService.setPackageProvinceId(picked.id);
    if (!mounted) return;
    setState(() => _province = picked);
  }

  /// تنظیم خودکار Router Host از Default Gateway
  /// این متد Default Gateway را شناسایی می‌کند و در Router Host ذخیره می‌کند
  Future<void> _autoSetRouterHostFromGateway() async {
    try {
      final networkInfo = NetworkInfoService();
      final discovery = await networkInfo.discoverDeviceDefaultGateway();

      if (discovery.found) {
        final gateway = discovery.ip!;
        final currentHost = await _settingsService.getHost();
        await _settingsService.setHost(gateway);
        if (kDebugMode && currentHost != gateway) {
          debugPrint(
            '[LOGIN] router host set from gateway=$gateway source=${discovery.source}',
          );
        }
      } else if (kDebugMode) {
        debugPrint('[LOGIN] gateway not found; host unchanged');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LOGIN] auto host failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _accessCodeController.dispose();
    super.dispose();
  }

  /// بررسی انقضای لاگین
  Future<void> _checkLoginExpiration() async {
    final isExpired = await _settingsService.isLoginExpired();
    if (isExpired && mounted) {
      // اگر لاگین منقضی شده باشد، زمان لاگین را پاک کن
      await _settingsService.clearLoginTimestamp();
    }
  }

  Future<void> _handleLogin() async {
    if (_province == null) {
      await _pickProvinceOnce();
      if (_province == null) return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // مخفی کردن کیبورد
    FocusScope.of(context).unfocus();

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    final province = _province!;
    final serviceManager = MikroTikServiceManager();
    try {
      unawaited(_settingsService.setPackageProvinceId(province.id));
      final hostFuture = NetworkInfoService().discoverRouterApiHost();
      final settingsFuture = _settingsService.getAllSettings();
      final savedFuture = _settingsService.getSavedCredentials();
      final codeOrigin = DeltaSibAuthService.codeWorkerFor(province);
      final redeemed = await DeltaSibAuthService().redeemAccessCode(
        code: _accessCodeController.text,
        origin: codeOrigin,
      );
      await _settingsService.setSibWorkerOrigin(codeOrigin);
      if (!mounted) return;
      final username = redeemed.username;

      SibPackageStore.prepareFor(username);
      String? discoveredHost;
      try {
        discoveredHost = await hostFuture;
      } catch (_) {}
      final settings = await settingsFuture;
      Map<String, String>? saved;
      try {
        saved = await savedFuture;
      } catch (e) {
        debugPrint('[LOGIN] saved credentials unreadable: $e');
      }
      var routerPass = redeemed.routerPassword ?? '';
      if (routerPass.isEmpty &&
          saved != null &&
          saved['username'] == username) {
        routerPass = saved['password'] ?? '';
      }
      if (routerPass.isEmpty && ReviewDemoAccount.isTester(username)) {
        routerPass = ReviewDemoAccount.simulatorPassword;
      }
      final host = (discoveredHost != null && discoveredHost.isNotEmpty)
          ? discoveredHost
          : settings['host'] as String;
      final saves = <Future<void>>[
        DeltaSibAuthService().rememberSubscriber(username),
        _settingsService.setLoginTimestamp(),
        _settingsService.markActivity(),
        if (discoveredHost != null && discoveredHost.isNotEmpty)
          _settingsService.setHost(discoveredHost),
        if (redeemed.routerPassword != null &&
            redeemed.routerPassword!.isNotEmpty)
          _settingsService.saveCredentials(
            username: username,
            password: redeemed.routerPassword!,
          ),
      ];
      try {
        await Future.wait(saves);
      } catch (e) {
        debugPrint('[LOGIN] local save failed, continuing: $e');
      }
      if (!mounted) return;

      if (routerPass.isNotEmpty) {
        unawaited(
          serviceManager.connect(
            MikroTikConnection(
              host: host,
              port: MikroTikConnection.apiPort,
              username: username,
              password: routerPass,
              useSsl: settings['useSsl'] as bool,
            ),
          ),
        );
      }
      unawaited(SibPackageStore.refresh(force: true));

      setState(() => _isConnecting = false);
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = AppTheme.primaryFor(theme.brightness);
    final screenWidth = MediaQuery.of(context).size.width;
    final contentMaxWidth = screenWidth >= 900 ? 460.0 : 520.0;
    final logoSize = screenWidth >= 900 ? 180.0 : 230.0;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkScaffold : colorScheme.surface,
      body: CosmicBackground(
        showStars: isDark,
        showGlow: isDark,
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 24.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),

                    // لوگو (بزرگ‌تر و کمی پایین‌تر تا به فیلدها نزدیک شود)
                    Center(
                      child: Image.asset(
                        'assets/images/logos/new_logo_bit.png',
                        height: logoSize,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          // اگر لوگو پیدا نشد، از آیکون برند استفاده کن
                          return Image.asset(
                            'assets/images/logos/new_logo_bit_2.png',
                            height: logoSize,
                            width: logoSize,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: logoSize,
                                height: logoSize,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? primaryColor.withOpacity(0.14)
                                      : primaryColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.router,
                                  size: logoSize * 0.39,
                                  color: primaryColor,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // const SizedBox(height: 24),

                    // عنوان
                    const SizedBox(height: 8),
                    Text(
                      Localizations.localeOf(context).languageCode == 'en'
                          ? 'Enter the 10-character code from support'
                          : 'کد ۱۰ نویسه‌ای پشتیبانی را وارد کنید',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.grey.shade600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    if (_province != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          Localizations.localeOf(context).languageCode == 'en'
                              ? _province!.titleEn()
                              : _province!.titleFa(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _accessCodeController,
                      keyboardType: TextInputType.visiblePassword,
                      textCapitalization: TextCapitalization.characters,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onFieldSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'کد ورود',
                        hintText: 'حرف و رقم',
                        prefixIcon: Icon(Icons.pin_outlined, color: primaryColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (DeltaSibAuthService.normalizeAccessCode(value ?? '') ==
                            null) {
                          return 'کد باید ۱۰ حرف انگلیسی و رقم باشد';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // دکمه ورود
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isConnecting ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.actionFor(theme.brightness),
                          foregroundColor: AppTheme.onActionFor(theme.brightness),
                          disabledBackgroundColor: AppTheme.actionFor(
                            theme.brightness,
                          ).withValues(alpha: 0.45),
                          disabledForegroundColor: AppTheme.onActionFor(
                            theme.brightness,
                          ).withValues(alpha: 0.7),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          elevation: 0,
                        ),
                        child: _isConnecting
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.onActionFor(theme.brightness),
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.login, size: 22),
                                  const SizedBox(width: 12),
                                  Builder(
                                    builder: (context) {
                                      final l10n = AppLocalizations.of(context);
                                      return Text(
                                        l10n?.login ?? 'Login',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    // شماره‌های پشتیبانی بر اساس ولایت
                    Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context);
                        final isEnglish = l10n?.locale.languageCode == 'en';
                        final muted = isDark
                            ? colorScheme.onSurface.withOpacity(0.65)
                            : Colors.grey.shade600;
                        final strong = isDark
                            ? colorScheme.onSurface.withOpacity(0.9)
                            : Colors.grey.shade800;

                        return Center(
                          child: Column(
                            children: [
                              Text(
                                isEnglish
                                    ? 'Support numbers by province'
                                    : 'شماره پشتیبانی بر اساس ولایت',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...SupportContacts.provinces.map((province) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    children: [
                                      Text(
                                        province.name(english: isEnglish),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: strong,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      ...province.phones.map((line) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            '${line.number}  ${line.role(english: isEnglish)}',
                                            textAlign: TextAlign.center,
                                            textDirection: TextDirection.ltr,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: strong,
                                              letterSpacing: 0.3,
                                              height: 1.45,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),

                    // نمایش خطا
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.red.shade900.withOpacity(0.3)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.red.shade700
                                : Colors.red.shade200,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: isDark
                                  ? Colors.red.shade400
                                  : Colors.red.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red.shade400
                                      : Colors.red.shade700,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
