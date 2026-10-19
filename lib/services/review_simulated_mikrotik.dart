part of 'mikrotik_service.dart';

/// RouterOS service that executes the production command builders against
/// [ReviewRouterOs] instead of a socket. Only the store-review account uses it.
class ReviewSimulatedMikroTikService extends MikroTikService {
  bool _simulated = false;

  @override
  bool get isConnected => _simulated;

  @override
  Future<bool> connect(MikroTikConnection connection) async {
    _connection = connection;
    _lastConnection = connection;
    _routerInfoCache = null;
    _wirelessFeaturesEnabled = null;
    _simulated = true;
    ReviewRouterOs.instance.ensureSeeded();
    debugPrint(
      '[REVIEW_SIM] session open host=192.168.88.1 user=${connection.username} '
      'transport=simulated socket=none',
    );
    return true;
  }

  @override
  void disconnect() {
    _simulated = false;
    _connection = null;
    _lastConnection = null;
    _routerInfoCache = null;
    _wirelessFeaturesEnabled = null;
  }

  @override
  Future<bool> ensureConnected({bool forceHealthCheck = false}) async {
    return _simulated;
  }

  @override
  Future<String?> getDeviceIp() async {
    if (!_simulated) {
      return null;
    }
    return '192.168.88.10';
  }

  @override
  Future<List<Map<String, String>>> _talk(
    List<String> command, {
    Duration timeout = MikrotikTimeouts.defaultTalk,
  }) async {
    if (!_simulated) {
      throw Exception('Cannot connect to router');
    }
    final rows = ReviewRouterOs.instance.execute(command);
    ReviewRouterLog.instance.record(
      command: command,
      rows: rows,
      note:
          'simulated RouterOS reply; no packet was sent; '
          'timeout=${timeout.inSeconds}s',
    );
    return rows;
  }

  @override
  Future<void> _dispatchWifiScript({
    required List<String> runCommand,
    required String scriptSource,
  }) async {
    ReviewRouterLog.instance.record(
      command: runCommand,
      rows: const [],
      note: 'simulated /system/script/run; script applied in memory',
    );
    ReviewRouterOs.instance.applyScript(scriptSource);
  }
}
