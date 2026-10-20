import 'package:flutter/material.dart';
import '../services/deltasib_auth_service.dart';
import '../services/mikrotik_service_manager.dart';
import '../services/settings_service.dart';
import '../services/sib_package_store.dart';
import '../providers/clients_provider.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import 'wifi_settings_screen.dart';

/// ??????
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final MikroTikServiceManager _serviceManager = MikroTikServiceManager();
  final SettingsService _settingsService = SettingsService();
  ThemeMode _selectedThemeMode = ThemeMode.dark;
  bool _isLoading = true;

  Color get _primaryColor =>
      AppTheme.primaryFor(Theme.of(context).brightness);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// ??????(?????)
  Future<void> _loadSettings() async {
    try {
      // ??????
      final themeMode = await _settingsService.getThemeModeEnum();

      setState(() {
        _selectedThemeMode = themeMode;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _selectedThemeMode = ThemeMode.dark;
        _isLoading = false;
      });
    }
  }

  /// ????
  Future<void> _changeTheme(ThemeMode themeMode) async {
    if (_isLoading) return;

    setState(() {
      _selectedThemeMode = themeMode;
    });

    try {
      // ??????
      await _settingsService.setThemeModeEnum(themeMode);

      // ?????????
      if (onThemeChanged != null) {
        onThemeChanged!(themeMode);
      }

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l10n?.darkMode ?? 'Theme'} ${_getThemeModeName(themeMode, l10n)}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _primaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.error ?? 'Error'}: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ????????
  String _getThemeModeName(ThemeMode mode, AppLocalizations? l10n) {
    switch (mode) {
      case ThemeMode.light:
        return l10n?.light ?? 'Light';
      case ThemeMode.dark:
        return l10n?.dark ?? 'Dark';
      case ThemeMode.system:
        return l10n?.system ?? 'System';
    }
  }

  /// ?????????
  void _showThemeSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = AppTheme.primaryFor(theme.brightness);

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ??
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                l10n?.darkMode ?? 'Theme Mode',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const Divider(),
            // ??????
            ListTile(
              leading: Icon(Icons.light_mode, color: primaryColor),
              title: Text(l10n?.light ?? 'Light'),
              subtitle: Text(l10n?.lightMode ?? 'Light Mode'),
              trailing: _selectedThemeMode == ThemeMode.light
                  ? Icon(Icons.check, color: primaryColor)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (_selectedThemeMode != ThemeMode.light) {
                  _changeTheme(ThemeMode.light);
                }
              },
            ),
            // ??????
            ListTile(
              leading: Icon(Icons.dark_mode, color: primaryColor),
              title: Text(l10n?.dark ?? 'Dark'),
              subtitle: Text(l10n?.darkMode ?? 'Dark Mode'),
              trailing: _selectedThemeMode == ThemeMode.dark
                  ? Icon(Icons.check, color: primaryColor)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (_selectedThemeMode != ThemeMode.dark) {
                  _changeTheme(ThemeMode.dark);
                }
              },
            ),
            // ??????
            ListTile(
              leading: Icon(Icons.brightness_auto, color: primaryColor),
              title: Text(l10n?.system ?? 'System'),
              subtitle: Text(l10n?.followSystem ?? 'Follow System'),
              trailing: _selectedThemeMode == ThemeMode.system
                  ? Icon(Icons.check, color: primaryColor)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (_selectedThemeMode != ThemeMode.system) {
                  _changeTheme(ThemeMode.system);
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = AppTheme.primaryFor(theme.brightness);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.appBarFor(theme.brightness),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppBar(
            title: Text(
              l10n?.settings ?? 'Settings',
              style: TextStyle(
                color: AppTheme.onAppBar(theme.brightness),
              ),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: AppTheme.onAppBar(theme.brightness),
            iconTheme: IconThemeData(color: AppTheme.onAppBar(theme.brightness)),
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
        ),
      ),
      body: Container(
        color: colorScheme.surfaceContainerHighest,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ??????
            Card(
              elevation: 2,
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.wifi, color: primaryColor),
                    title: Text(
                      l10n?.wifiSettings ?? 'تنظیمات وایفای',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      l10n?.wifiSettingsSubtitle ?? 'تغییر نام و رمز شبکه',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.primaryFor(theme.brightness),
                    ),
                    onTap: () async {
                      final live = MikroTikServiceManager().currentConnection?.host;
                      final info = Provider.of<ClientsProvider>(context, listen: false)
                              .routerInfo ??
                          MikroTikServiceManager().routerInfo;
                      if (info == null) {
                        await Provider.of<ClientsProvider>(context, listen: false)
                            .loadRouterInfo();
                      }
                      if (!context.mounted) return;
                      final resolved = Provider.of<ClientsProvider>(context, listen: false)
                              .routerInfo ??
                          MikroTikServiceManager().routerInfo;
                      if (WifiSettingsRouter.shouldOpenExternally(
                        host: live,
                        routerInfo: resolved,
                      )) {
                        final opened = await openCpeWifiInExternalBrowser();
                        if (opened || !context.mounted) return;
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).pushNamed('/wifi-settings');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.headset_mic_rounded, color: primaryColor),
                    title: Text(
                      l10n?.subscriberHelp ?? 'راهنمایی مشترکین',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      l10n?.subscriberHelpSettingsSubtitle ??
                          'آموزش مدیریت دستگاه، وای‌فای و سرویس',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.primaryFor(theme.brightness),
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed('/subscriber-help');
                    },
                  ),
                  const Divider(height: 1),
                  // ????
                  ListTile(
                    leading: Icon(
                      _selectedThemeMode == ThemeMode.dark
                          ? Icons.dark_mode
                          : _selectedThemeMode == ThemeMode.system
                          ? Icons.brightness_auto
                          : Icons.light_mode,
                      color: primaryColor,
                    ),
                    title: Text(
                      l10n?.darkMode ?? 'Theme Mode',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      _getThemeModeName(_selectedThemeMode, l10n),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getThemeModeName(_selectedThemeMode, l10n),
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: primaryColor,
                              ),
                            ],
                          ),
                    onTap: _isLoading
                        ? null
                        : () => _showThemeSelector(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.privacy_tip_outlined, color: primaryColor),
                    title: Text(
                      l10n?.privacyPolicy ?? 'Privacy Policy',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: primaryColor,
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed('/privacy-policy');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.description_outlined, color: primaryColor),
                    title: Text(
                      l10n?.termsOfUse ?? 'Terms of Use',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: primaryColor,
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamed('/terms-of-use');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined, color: primaryColor),
                    title: Text(
                      l10n?.clearLocalData ?? 'Clear local data',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      l10n?.clearLocalDataSubtitle ??
                          'Remove saved router credentials and preferences',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: primaryColor,
                    ),
                    onTap: _handleClearLocalData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ????
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  l10n?.logout ?? 'Logout',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
                subtitle: Text(
                  l10n?.logoutMessage ?? 'Logout from account',
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: _handleLogout,
                trailing: const Icon(Icons.chevron_right, color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleClearLocalData() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.clearLocalData ?? 'Clear local data'),
        content: Text(
          l10n?.clearLocalDataConfirm ??
              'This permanently deletes locally stored credentials and preferences on this device. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n?.delete ?? 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = Provider.of<ClientsProvider>(context, listen: false);
    provider.clear();
    _serviceManager.disconnect();
    await DeltaSibAuthService().logout();
    await SibPackageStore.clear();
    await _settingsService.clearAllLocalData();

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n?.clearLocalDataDone ?? 'Local data cleared'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _primaryColor,
      ),
    );
    nav.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _handleLogout() async {
    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.logout ?? 'Logout'),
        content: Text(
          l10n?.logoutConfirm ?? 'Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n?.logout ?? 'Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final provider = Provider.of<ClientsProvider>(context, listen: false);
      provider.clear();
      _serviceManager.disconnect();

      final settingsService = SettingsService();
      await DeltaSibAuthService().logout();
      await SibPackageStore.clear();
      await settingsService.clearLoginTimestamp();
      await settingsService.clearLastActivity();
      if (!await settingsService.getRememberMe()) {
        await settingsService.clearCredentials();
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }
}
