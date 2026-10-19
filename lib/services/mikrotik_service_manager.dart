import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mikrotik_connection.dart';
import 'connection_heartbeat.dart';
import 'deltasib_auth_service.dart';
import 'mikrotik_service.dart';
import 'mikrotik_timeouts.dart';
import 'review_demo_account.dart';
import 'review_router_log.dart';
import 'review_router_os.dart';
import 'network_info_service.dart';
import 'settings_service.dart';
import 'sib_package_store.dart';
import 'traffic_monitor_service.dart';
import '../models/client_traffic_rate.dart';

/// مدیر سرویس MikroTik - Singleton برای نگه‌داری اتصال در کل برنامه
class MikroTikServiceManager {
  static final MikroTikServiceManager _instance =
      MikroTikServiceManager._internal();
  factory MikroTikServiceManager() => _instance;
  MikroTikServiceManager._internal();

  MikroTikService? _service;
  MikroTikConnection? _currentConnection;
  String? _lastRouterError;
  Future<bool>? _connectTask;

  /// آخرین دلیل رد شدن ورود به RouterOS، برای نمایش در لیست دستگاه‌ها.
  String? get lastRouterError => _lastRouterError;

  /// ورود در جریان، تا صفحهٔ خانه همان را ادامه دهد و دوباره لاگین نکند.
  Future<bool>? get connectInFlight => _connectTask;
  Map<String, dynamic>? _routerInfo;
  DateTime? _routerInfoCacheTime;
  ConnectionHeartbeat? _heartbeat;
  final TrafficMonitorService _trafficMonitor = TrafficMonitorService();
  bool _progressiveLoadActive = false;
  bool _reviewSimulation = false;
  bool _reviewNoticePending = false;
  bool _reviewNoticeShown = false;

  /// خانه با این گوش می‌دهد تا نوار شبیه‌ساز همان لحظهٔ فعال شدن رسم شود.
  final ValueNotifier<bool> reviewSimulationListenable = ValueNotifier(false);

  /// True only after jb.admin falls back to the in-phone RouterOS simulator.
  bool get reviewSimulation => _reviewSimulation;

  void _setReviewSimulation(bool value) {
    if (_reviewSimulation == value) return;
    _reviewSimulation = value;
    reviewSimulationListenable.value = value;
  }

  /// Home shows the MikroTik warning once when simulation starts from splash.
  bool consumeReviewNotice() {
    if (!_reviewNoticePending || _reviewNoticeShown) {
      return false;
    }
    _reviewNoticePending = false;
    _reviewNoticeShown = true;
    return true;
  }

  void markReviewNoticeShown() {
    _reviewNoticePending = false;
    _reviewNoticeShown = true;
  }

  void abandonReviewSimulation() {
    disconnect();
    ReviewRouterOs.instance.reset();
    ReviewRouterLog.instance.clear();
    _reviewNoticePending = false;
    _reviewNoticeShown = false;
  }

  static const Duration _routerInfoCacheTtl = Duration(minutes: 5);

  /// دریافت سرویس فعلی
  MikroTikService? get service => _service;

  /// بررسی اتصال
  bool get isConnected => _service?.isConnected ?? false;

  /// دریافت اطلاعات اتصال فعلی
  MikroTikConnection? get currentConnection => _currentConnection;

  /// دریافت اطلاعات روتر (کامل - شامل uptime, version, board-name, platform و ...)
  Map<String, dynamic>? get routerInfo => _routerInfo;

  /// تلاش برای auto-login با اعتبارنامه و تنظیمات ذخیره‌شده.
  /// هرگز throw نمی‌کند. اگر نشست حجم باشد، خانه فوری باز می‌شود و روتر در پس‌زمینه وصل می‌شود.
  Future<bool> autoConnect() async {
    try {
      final settingsService = SettingsService();
      final auth = DeltaSibAuthService();
      final sessionFuture = settingsService.hasValidSession();
      final userFuture = auth.savedUsername();
      final sibSessionFuture = auth.savedSession();
      final credentialsFuture = settingsService.getSavedCredentials();
      final settingsFuture = settingsService.getAllSettings();

      if (!await sessionFuture) {
        await settingsService.clearLoginTimestamp();
        return false;
      }

      final sibUser = (await userFuture)?.trim();
      final sibSession = await sibSessionFuture;
      final hasSib = sibUser != null &&
          sibUser.isNotEmpty &&
          sibSession != null &&
          sibSession.isNotEmpty;
      final credentials = await credentialsFuture;
      var routerUser = credentials?['username'];
      var routerPass = credentials?['password'];
      if ((routerUser == null || routerPass == null || routerPass.isEmpty) &&
          hasSib &&
          ReviewDemoAccount.isTester(sibUser)) {
        routerUser = sibUser;
        routerPass = ReviewDemoAccount.simulatorPassword;
      }

      if (hasSib) {
        SibPackageStore.prepareFor(sibUser);
        unawaited(SibPackageStore.hydrate());
      }
      if (routerUser == null || routerPass == null || routerPass.isEmpty) {
        return hasSib;
      }

      final settings = await settingsFuture;
      final connection = MikroTikConnection(
        host: settings['host'] as String? ?? '192.168.88.1',
        port: MikroTikConnection.apiPort,
        username: routerUser,
        password: routerPass,
        useSsl: settings['useSsl'] as bool? ?? false,
      );

      if (!hasSib) {
        SibPackageStore.prepareFor(routerUser);
        unawaited(SibPackageStore.hydrate());
      }
      final connecting = connect(connection);
      if (hasSib) {
        unawaited(connecting);
        return true;
      }
      return await connecting.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[AUTO_LOGIN] Failed: $e');
      return false;
    }
  }

  /// اتصال به MikroTik.
  ///
  /// jb.admin با هر رمزی اول به RouterOS واقعی وصل می‌شود. اگر گیت‌وی، پورت یا
  /// رمز قبول شود شبیه‌ساز خاموش می‌ماند. هر شکست دیگری همان حساب را وارد
  /// شبیه‌ساز می‌کند. بقیهٔ کاربران در صورت خطا شبیه‌ساز نمی‌گیرند.
  Future<bool> connect(MikroTikConnection connection) {
    final pending = _connectTask;
    if (pending != null) return pending;
    final task = _connectBody(connection);
    _connectTask = task;
    return task.whenComplete(() {
      if (identical(_connectTask, task)) {
        _connectTask = null;
      }
    });
  }

  Future<bool> _connectBody(MikroTikConnection connection) async {
    final review = ReviewDemoAccount.isTester(connection.username);
    final simulatorFallback = ReviewDemoAccount.simulatorFallback(
      connection.username,
    );
    final keepReal = !_reviewSimulation && (_service?.isConnected ?? false);
    disconnect();
    _currentConnection = connection;

    if (!review) {
      _clearReviewMode();
    }

    if (await _tryRealRouter(connection, review: review)) {
      _clearReviewMode();
      _lastRouterError = null;
      return true;
    }

    if (!simulatorFallback || keepReal) {
      _service = null;
      _currentConnection = null;
      _setReviewSimulation(false);
      _lastRouterError = await _explainRouterFailure(connection);
      return false;
    }

    _service?.disconnect();
    _service = null;
    ReviewRouterOs.instance.reset();
    ReviewRouterLog.instance.clear();
    _reviewNoticeShown = false;
    return _openReviewSimulation(connection);
  }

  Future<bool> _tryRealRouter(
    MikroTikConnection connection, {
    required bool review,
  }) async {
    try {
      if (review && !await _reviewRouterLoginOk(connection)) {
        return false;
      }
      final real = await _openRealSession(
        connection,
        timeout: review ? const Duration(milliseconds: 1200) : null,
      );
      if (real) return true;
    } catch (e) {
      if (!review) {
        _service = null;
        _currentConnection = null;
        _setReviewSimulation(false);
        throw Exception('خطا در اتصال: $e');
      }
      debugPrint('[REVIEW_SIM] real RouterOS login failed: $e');
    }
    _service?.disconnect();
    _service = null;
    return false;
  }

  /// برای jb.admin ورود واقعی را با یک پروب کوتاه می‌سنجد.
  /// نبودِ روتر، پورت بسته یا رمز غلط همان‌جا رد می‌شود و شبیه‌ساز باز می‌شود.
  Future<bool> _reviewRouterLoginOk(MikroTikConnection connection) async {
    final probe = await probeRouterOsLogin(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      connectTimeout: const Duration(milliseconds: 400),
      replyTimeout: const Duration(milliseconds: 400),
    );
    if (probe.accepted || probe.challenge) return true;
    debugPrint(
      '[REVIEW_SIM] RouterOS login skipped '
      '(${probe.detail ?? 'no reply'})',
    );
    return false;
  }

  void _clearReviewMode() {
    _setReviewSimulation(false);
    _reviewNoticePending = false;
    _reviewNoticeShown = false;
    ReviewRouterOs.instance.reset();
    ReviewRouterLog.instance.clear();
  }

  Future<bool> _openRealSession(
    MikroTikConnection connection, {
    Duration? timeout,
  }) async {
    _service = MikroTikService();
    _currentConnection = connection;
    final attempt = _service!.connect(connection);
    final bool success;
    if (timeout == null) {
      success = await attempt;
    } else {
      success = await attempt.timeout(timeout, onTimeout: () {
        debugPrint('[REVIEW_SIM] real RouterOS login timed out');
        _service?.disconnect();
        return false;
      });
    }
    if (!success || !(_service?.isConnected ?? false)) {
      _service?.disconnect();
      _service = null;
      _routerInfo = null;
      _routerInfoCacheTime = null;
      return false;
    }
    _startHeartbeat();
    return true;
  }

  Future<bool> _openReviewSimulation(MikroTikConnection connection) async {
    _lastRouterError = null;
    _setReviewSimulation(true);
    _service = ReviewSimulatedMikroTikService();
    _currentConnection = MikroTikConnection(
      host: '192.168.88.1',
      port: MikroTikConnection.apiPort,
      username: connection.username,
      password: connection.password,
      useSsl: false,
    );
    _routerInfo = null;
    _routerInfoCacheTime = null;
    await _service!.connect(_currentConnection!);
    if (!_reviewNoticeShown) {
      _reviewNoticePending = true;
    }
    _startHeartbeat();
    return _service?.isConnected ?? false;
  }

  void _startHeartbeat() {
    _heartbeat?.stop();
    _heartbeat = ConnectionHeartbeat(
      healthCheck: () async {
        if (_progressiveLoadActive || _reviewSimulation) {
          return _service?.isConnected ?? false;
        }
        final service = _service;
        if (service == null) {
          return false;
        }
        return service.isConnected &&
            await service.ensureConnected(forceHealthCheck: true);
      },
      reconnect: () async {
        final connection = _currentConnection;
        if (connection == null) {
          return false;
        }
        debugPrint('[HEARTBEAT] full reconnect');
        return connect(connection);
      },
    );
    _heartbeat!.start();
  }

  /// بستن اتصال
  void disconnect() {
    _heartbeat?.stop();
    _heartbeat = null;
    unawaited(_trafficMonitor.disconnect());
    _service?.disconnect();
    _service = null;
    _currentConnection = null;
    _routerInfo = null;
    _routerInfoCacheTime = null;
    _progressiveLoadActive = false;
    _setReviewSimulation(false);
  }

  bool get isProgressiveLoadActive => _progressiveLoadActive;

  void beginProgressiveLoad() {
    _progressiveLoadActive = true;
    _heartbeat?.stop();
    _service?.beginProgressiveLoad();
  }

  void endProgressiveLoad() {
    _progressiveLoadActive = false;
    _service?.endProgressiveLoad();
    if (_service != null && isConnected) {
      _heartbeat?.start();
    }
  }

  /// Ensures the API session is usable (reconnects if the socket was dropped).
  Future<bool> ensureSession() async {
    final pending = _connectTask;
    if (pending != null) {
      final ok = await pending;
      if (ok && (_service?.isConnected ?? false)) return true;
    }
    final service = _service;
    if (service != null && service.isConnected) return true;
    if (service != null) {
      final healthy = await service.ensureConnected(forceHealthCheck: true);
      if (healthy) return true;
    }
    return reconnectSaved();
  }

  /// ورود دوباره با یوزر ذخیره‌شده، روی Default Gateway همین دستگاه.
  Future<bool> reconnectSaved() async {
    if (isConnected && _service != null) return true;
    final creds = await SettingsService().getSavedCredentials();
    final username = creds?['username'] ?? '';
    final password = creds?['password'] ?? '';
    if (username.isEmpty || password.isEmpty) {
      _lastRouterError = 'اتصال برقرار نشده است. لطفاً دوباره وارد شوید.';
      return false;
    }
    final settings = await SettingsService().getAllSettings();
    final discovered = await NetworkInfoService().discoverRouterApiHost();
    final host = (discovered != null && discovered.isNotEmpty)
        ? discovered
        : settings['host'] as String;
    if (discovered != null && discovered.isNotEmpty) {
      await SettingsService().setHost(discovered);
    }
    final port = settings['port'];
    return connect(
      MikroTikConnection(
        host: host,
        port: port is int ? port : MikroTikConnection.apiPort,
        username: username,
        password: password,
        useSsl: settings['useSsl'] == true,
      ),
    );
  }

  Future<String> _explainRouterFailure(MikroTikConnection connection) async {
    final probe = await probeRouterOsLogin(
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
    );
    final detail = (probe.detail ?? '').toLowerCase();
    if (detail.contains('invalid user')) {
      return 'روتر ${connection.host} این یوزر را برای API قبول نکرد. '
          'در Winbox برای همین یوزر دسترسی api را فعال کنید.';
    }
    if (probe.detail != null && probe.detail!.isNotEmpty) {
      return 'روتر ${connection.host}: ${probe.detail}';
    }
    return 'به روتر ${connection.host} روی پورت API وصل نشد.';
  }

  /// Ping the main API socket and reconnect if it died (common after extra logins).
  Future<bool> ensureSessionHealthy() async {
    final service = _service;
    if (service == null) {
      return false;
    }
    return service.ensureConnected(forceHealthCheck: true);
  }

  /// Router info cache is fresh if younger than 5 minutes.
  bool hasValidCachedRouterInfo() {
    if (_routerInfo == null || _routerInfoCacheTime == null) {
      return false;
    }
    return DateTime.now().difference(_routerInfoCacheTime!) <
        _routerInfoCacheTtl;
  }

  /// دریافت اطلاعات روتر (با refresh)
  Future<Map<String, dynamic>?> getRouterInfo({bool forceRefresh = false}) async {
    if (_service == null || !isConnected) {
      return null;
    }
    if (!forceRefresh && hasValidCachedRouterInfo()) {
      return _routerInfo;
    }
    try {
      _routerInfo = await _service!.getRouterInfo();
      _routerInfoCacheTime = DateTime.now();
      return _routerInfo;
    } catch (e) {
      return _routerInfo; // برگرداندن اطلاعات قبلی در صورت خطا
    }
  }

  /// Phase 3 — device IP, router info, lock status on isolated connection.
  /// Never throws; returns partial map on failure.
  Future<Map<String, dynamic>> loadSecondaryDataIsolated() async {
    final connection = _currentConnection;
    if (connection == null) {
      return {};
    }

    if (_reviewSimulation && _service != null) {
      try {
        final routerInfoFuture = hasValidCachedRouterInfo()
            ? Future<Map<String, dynamic>?>.value(_routerInfo)
            : _service!.getRouterInfoSecondary();
        final results = await Future.wait<dynamic>([
          _service!.getDeviceIp(),
          routerInfoFuture,
          _service!.isNewConnectionsLocked(),
        ]);
        final routerInfo = results[1] as Map<String, dynamic>?;
        if (routerInfo != null && !hasValidCachedRouterInfo()) {
          _routerInfo = routerInfo;
          _routerInfoCacheTime = DateTime.now();
        }
        return {
          'deviceIp': results[0] as String?,
          'routerInfo': routerInfo ?? _routerInfo,
          'isNewConnectionsLocked': results[2] as bool? ?? false,
        };
      } catch (e) {
        debugPrint('[REVIEW_SIM] secondary load failed: $e');
        return {};
      }
    }

    final isolated = MikroTikService();
    try {
      final connected = await isolated
          .connect(connection)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!connected) {
        return {};
      }

      final routerInfoFuture = hasValidCachedRouterInfo()
          ? Future<Map<String, dynamic>?>.value(_routerInfo)
          : isolated.getRouterInfoSecondary();

      final results = await Future.wait<dynamic>([
        isolated.getDeviceIp(),
        routerInfoFuture,
        isolated.isNewConnectionsLocked(),
      ]);

      final routerInfo = results[1] as Map<String, dynamic>?;
      if (routerInfo != null && !hasValidCachedRouterInfo()) {
        _routerInfo = routerInfo;
        _routerInfoCacheTime = DateTime.now();
      }

      return {
        'deviceIp': results[0] as String?,
        'routerInfo': routerInfo ?? _routerInfo,
        'isNewConnectionsLocked': results[2] as bool? ?? false,
      };
    } catch (e) {
      debugPrint('[PROGRESSIVE_LOAD] isolated secondary failed: $e');
      return {};
    } finally {
      isolated.disconnect();
    }
  }

  /// دریافت همه کلاینت‌ها
  Future<Map<String, dynamic>> getAllClients() async {
    if (_service == null || !isConnected) {
      throw Exception('اتصال برقرار نشده');
    }
    return await _service!.getAllClients();
  }

  Future<List<Map<String, String>>> getPhase1BoundDhcpLeases() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getPhase1BoundDhcpLeases();
  }

  Future<List<Map<String, String>>> getPhase2ManagedBanRawRules() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getPhase2ManagedBanRawRules();
  }

  Future<int> getBannedDeviceCount() async {
    if (_service == null || !isConnected) {
      return 0;
    }
    return _service!.getBannedDeviceCount();
  }

  Future<List<Map<String, dynamic>>> getBannedClientsFast() async {
    if (_service == null || !isConnected) {
      return const [];
    }
    return _service!.getBannedClientsFast();
  }

  Future<List<Map<String, String>>> getPhase2ArpTable() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getPhase2ArpTable();
  }

  Future<List<Map<String, String>>> getPhase2NeighborDiscovery() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getPhase2NeighborDiscovery();
  }

  Future<List<Map<String, String>>> getArpTable() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getArpTable();
  }

  Future<List<Map<String, String>>> getDhcpLastSeen() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getDhcpLastSeen();
  }

  Future<List<Map<String, String>>> getPhase2WirelessRegistrations() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.getPhase2WirelessRegistrations();
  }

  /// دریافت کلاینت‌های متصل
  Future<Map<String, dynamic>> getConnectedClients() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return await _service!.getConnectedClients();
  }

  /// دریافت IP دستگاه کاربر
  Future<String?> getDeviceIp() async {
    if (_service == null || !isConnected) {
      return null;
    }
    return await _service!.getDeviceIp();
  }

  /// دریافت Default Gateway از route table RouterOS
  Future<String?> getDefaultGateway() async {
    if (_service == null || !isConnected) {
      return null;
    }
    return await _service!.getDefaultGateway();
  }

  /// دریافت Default Gateway یا IP روتر (fallback)
  Future<String?> getDefaultGatewayOrRouterIp() async {
    if (_service == null || !isConnected) {
      return null;
    }
    return await _service!.getDefaultGatewayOrRouterIp();
  }

  /// دریافت لیست دستگاه‌های مسدود شده
  Future<List<Map<String, dynamic>>> getBannedClients() async {
    if (_service == null || !isConnected) {
      throw Exception('اتصال برقرار نشده');
    }
    return await _service!.getBannedClients();
  }

  Future<bool> makeClientStatic({String? ipAddress, String? macAddress}) async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.makeClientStatic(
      ipAddress: ipAddress,
      macAddress: macAddress,
    );
  }

  Future<bool> lockNewConnections() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.lockNewConnections();
  }

  Future<bool> unlockNewConnections() async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.unlockNewConnections();
  }

  Future<bool> isNewConnectionsLocked() async {
    if (_service == null || !isConnected) {
      return false;
    }
    return _service!.isNewConnectionsLocked();
  }

  Future<String> setDhcpLeaseDisplayName({
    String? ipAddress,
    String? macAddress,
    required String displayName,
  }) async {
    if (_service == null || !isConnected) {
      throw Exception('Connection is not established');
    }
    return _service!.setDhcpLeaseDisplayName(
      ipAddress: ipAddress,
      macAddress: macAddress,
      displayName: displayName,
    );
  }

  Future<Map<String, dynamic>> getWifiSettings({String? interfaceId}) async {
    if (_service == null || !isConnected) {
      throw Exception('اتصال برقرار نشده');
    }
    return _service!.getWifiSettings(interfaceId: interfaceId);
  }

  Future<void> saveWifiSettingsAtomic({
    required String interfaceName,
    required String profileName,
    required String ssid,
    required bool hideSsid,
    String? password,
  }) async {
    if (_service == null || !isConnected) {
      throw Exception('اتصال برقرار نشده');
    }
    return _service!.saveWifiSettingsAtomic(
      interfaceName: interfaceName,
      profileName: profileName,
      ssid: ssid,
      hideSsid: hideSsid,
      password: password,
    );
  }

  Future<Map<String, String>?> getClientSpeedIsolated(String target) async {
    final connection = _currentConnection;
    if (connection == null) {
      throw Exception('Connection is not established');
    }

    if (_reviewSimulation && _service != null) {
      return _service!.getClientSpeed(target);
    }

    final speedService = MikroTikService();
    try {
      final connected = await speedService
          .connect(connection)
          .timeout(MikrotikTimeouts.isolatedConnect, onTimeout: () => false);
      if (!connected) {
        return null;
      }

      return await speedService
          .getClientSpeed(target)
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
    } finally {
      speedService.disconnect();
    }
  }

  /// Poll live traffic on an isolated API socket (does not block main queue).
  Future<Map<String, ClientTrafficRate>> pollTrafficRates({
    required Set<String> trackedIps,
    required Map<String, String> macToIp,
  }) async {
    final connection = _currentConnection;
    if (connection == null || !isConnected) {
      return {};
    }

    if (_reviewSimulation) {
      final rates = ReviewRouterOs.instance.sampleTraffic(trackedIps);
      ReviewRouterLog.instance.record(
        command: const ['/queue/simple/print', '=stats='],
        rows: rates.entries
            .map(
              (entry) => <String, String>{
                'target': '${entry.key}/32',
                'rx-rate': '${entry.value.rxBps}',
                'tx-rate': '${entry.value.txBps}',
              },
            )
            .toList(),
        note: 'simulated queue stats for live traffic badges',
        throttle: const Duration(seconds: 20),
        throttleKey: 'queue-stats',
      );
      return rates;
    }

    try {
      await _trafficMonitor.ensureConnected(connection);
      return await _trafficMonitor.sampleRates(
        trackedIps: trackedIps,
        macToIp: macToIp,
      );
    } catch (e) {
      debugPrint('[TRAFFIC] poll failed: $e');
      return {};
    }
  }

  bool get trafficUsesInstantQueueRates => _trafficMonitor.usesInstantQueueRates;

  AggregateTrafficVolume get networkAggregateVolume =>
      _trafficMonitor.networkAggregateVolume;

  AggregateLiveTrafficRate get networkAggregateLiveRate {
    if (_reviewSimulation) {
      return ReviewRouterOs.instance.networkLiveRate();
    }
    return _trafficMonitor.networkAggregateLiveRate;
  }

  Future<void> disconnectTrafficMonitor() async {
    await _trafficMonitor.disconnect();
  }
}
