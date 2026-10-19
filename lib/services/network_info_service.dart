import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';

import '../utils/windows_default_gateway.dart';
import 'mikrotik_service_manager.dart';

/// منبع تشخیص Default Gateway دستگاه (کلاینت)
enum DeviceGatewaySource {
  /// جدول مسیریابی / DHCP سیستم‌عامل (دقیق برای هر subnet)
  system,

  /// تشخیص ممکن نبود (مثلاً Web یا محدودیت پلتفرم)
  unavailable,
}

/// نتیجهٔ تشخیص gateway اینترنت دستگاه
class DeviceGatewayDiscovery {
  const DeviceGatewayDiscovery({this.ip, required this.source});

  final String? ip;
  final DeviceGatewaySource source;

  bool get found => ip != null && ip!.isNotEmpty;
}

/// پورت API روتر در چند ثانیه باز است یا نه.
Future<bool> routerApiReachable(String host) async {
  if (kIsWeb) return false;
  try {
    final socket = await Socket.connect(
      host,
      8728,
      timeout: const Duration(milliseconds: 1500),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

List<int> _routerOsSentence(List<String> words) {
  final out = <int>[];
  for (final word in words) {
    final bytes = utf8.encode(word);
    final n = bytes.length;
    if (n < 0x80) {
      out.add(n);
    } else if (n < 0x4000) {
      out.add((n >> 8) | 0x80);
      out.add(n & 0xff);
    } else {
      out.add((n >> 16) | 0xC0);
      out.add((n >> 8) & 0xff);
      out.add(n & 0xff);
    }
    out.addAll(bytes);
  }
  out.add(0);
  return out;
}

class RouterOsLoginProbe {
  const RouterOsLoginProbe({
    required this.accepted,
    this.reachable = false,
    this.challenge = false,
    this.detail,
  });

  final bool accepted;

  /// پورت API جواب داده، حتی اگر رمز رد شده باشد.
  final bool reachable;

  /// RouterOS قدیمی چالش برگردانده و ورود واقعی هنوز تمام نشده.
  final bool challenge;
  final String? detail;
}

Future<RouterOsLoginProbe> probeRouterOsLogin({
  required String host,
  required int port,
  required String username,
  required String password,
  Duration connectTimeout = const Duration(milliseconds: 1200),
  Duration replyTimeout = const Duration(milliseconds: 1200),
}) async {
  if (kIsWeb || host.isEmpty) {
    return const RouterOsLoginProbe(accepted: false);
  }
  Socket? socket;
  try {
    socket = await Socket.connect(
      host,
      port,
      timeout: connectTimeout,
    );
    final bytes = <int>[];
    final done = Completer<void>();
    final sub = socket.listen(
      (data) {
        bytes.addAll(data);
        if (!done.isCompleted && bytes.contains(0)) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    socket.add(
      _routerOsSentence([
        '/login',
        '=name=$username',
        '=password=$password',
      ]),
    );
    await done.future.timeout(replyTimeout, onTimeout: () {});
    await sub.cancel();
    final text = utf8.decode(bytes, allowMalformed: true);
    final message = RegExp(r'message=([^\x00]+)').firstMatch(text)?.group(1);
    if (text.contains('!done') && !text.contains('=ret=')) {
      return const RouterOsLoginProbe(accepted: true, reachable: true);
    }
    if (text.contains('!done') && text.contains('=ret=')) {
      return const RouterOsLoginProbe(
        accepted: false,
        reachable: true,
        challenge: true,
      );
    }
    return RouterOsLoginProbe(
      accepted: false,
      reachable: text.isNotEmpty,
      detail: message,
    );
  } catch (_) {
    return const RouterOsLoginProbe(accepted: false);
  } finally {
    socket?.destroy();
  }
}

/// سرویس برای دریافت اطلاعات شبکه دستگاه (IPv4 Address و Default Gateway)
class NetworkInfoService {
  static final NetworkInfoService _instance = NetworkInfoService._internal();
  factory NetworkInfoService() => _instance;
  NetworkInfoService._internal();

  final NetworkInfo _networkInfo = NetworkInfo();

  WindowsDefaultRoute? _windowsRouteCache;
  DateTime? _windowsRouteCacheAt;
  static const Duration _windowsRouteCacheTtl = Duration(seconds: 20);
  DeviceGatewayDiscovery? _gatewayMemory;
  DateTime? _gatewayMemoryAt;
  Future<DeviceGatewayDiscovery>? _gatewayInFlight;
  static const Duration _gatewayMemoryTtl = Duration(seconds: 30);

  static final RegExp _ipv4Regex = RegExp(
    r'^(?:\d{1,3}\.){3}\d{1,3}$',
  );

  /// نرمال‌سازی و اعتبارسنجی IPv4 (برای تست و استفاده داخلی)
  static String? normalizeIpv4(String? raw) {
    if (raw == null) {
      return null;
    }
    var value = raw.trim().replaceAll('"', '');
    if (value.isEmpty || value == '0.0.0.0' || value == '255.255.255.255') {
      return null;
    }
    if (!_ipv4Regex.hasMatch(value)) {
      return null;
    }
    final parts = value.split('.');
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return null;
      }
    }
    return value;
  }

  bool get _isWindows {
    if (kIsWeb) {
      return false;
    }
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  /// Default Gateway واقعی اینترنت دستگاه از OS
  /// (نه حدس subnet و نه route WAN روتر MikroTik)
  Future<DeviceGatewayDiscovery> discoverDeviceDefaultGateway() {
    final cachedAt = _gatewayMemoryAt;
    if (_gatewayMemory != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _gatewayMemoryTtl) {
      return Future.value(_gatewayMemory);
    }
    final inFlight = _gatewayInFlight;
    if (inFlight != null) return inFlight;
    final run = _loadDeviceDefaultGateway();
    _gatewayInFlight = run;
    return run.whenComplete(() {
      if (identical(_gatewayInFlight, run)) {
        _gatewayInFlight = null;
      }
    });
  }

  Future<DeviceGatewayDiscovery> _loadDeviceDefaultGateway() async {
    if (kIsWeb) {
      return const DeviceGatewayDiscovery(
        source: DeviceGatewaySource.unavailable,
      );
    }

    final wifiFuture = _wifiGateway();
    final routeFuture = _isWindows
        ? _windowsDefaultRoute()
        : Future<WindowsDefaultRoute?>.value(null);

    final wifi = await wifiFuture;
    if (wifi != null &&
        WindowsDefaultGatewayParser.isPrivateIpv4(wifi) &&
        !WindowsDefaultGatewayParser.looksLikeVpnIpv4(wifi)) {
      return _rememberGateway(wifi);
    }

    final windowsRoute = await routeFuture;
    final gateway = normalizeIpv4(windowsRoute?.gateway);
    if (gateway != null) {
      return _rememberGateway(gateway);
    }

    return const DeviceGatewayDiscovery(source: DeviceGatewaySource.unavailable);
  }

  DeviceGatewayDiscovery _rememberGateway(String gateway) {
    final found = DeviceGatewayDiscovery(
      ip: gateway,
      source: DeviceGatewaySource.system,
    );
    _gatewayMemory = found;
    _gatewayMemoryAt = DateTime.now();
    return found;
  }

  Future<String?> _wifiGateway() async {
    try {
      final raw = await _networkInfo
          .getWifiGatewayIP()
          .timeout(const Duration(milliseconds: 700));
      return normalizeIpv4(raw);
    } catch (_) {
      return null;
    }
  }

  /// دریافت IPv4 Address دستگاه از NetworkInterface
  /// این متد IP محلی دستگاه را از interface های فعال برمی‌گرداند
  Future<String?> getDeviceIPv4Address() async {
    try {
      if (_isWindows) {
        final windowsRoute = await _windowsDefaultRoute();
        final interfaceIp = normalizeIpv4(windowsRoute?.interfaceIp);
        if (interfaceIp != null && _isPrivateLanIp(interfaceIp)) {
          return interfaceIp;
        }

        final gateway = windowsRoute?.gateway;
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: false,
        );
        String? fallbackPrivate;
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              final ip = addr.address;
              if (_isPrivateLanIp(ip)) {
                fallbackPrivate ??= ip;
                if (gateway != null &&
                    WindowsDefaultGatewayParser.sameSlash24(ip, gateway)) {
                  return ip;
                }
              }
            }
          }
        }
        return fallbackPrivate;
      }

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (_isPrivateLanIp(ip)) {
              return ip;
            }
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  bool _isPrivateLanIp(String ip) {
    return WindowsDefaultGatewayParser.isPrivateIpv4(ip);
  }

  Future<WindowsDefaultRoute?> _windowsDefaultRoute() async {
    final now = DateTime.now();
    if (_windowsRouteCache != null &&
        _windowsRouteCacheAt != null &&
        now.difference(_windowsRouteCacheAt!) < _windowsRouteCacheTtl) {
      return _windowsRouteCache;
    }

    final localIps = await _localPrivateIpv4s();

    try {
      final routePrint = await Process.run(
        'route',
        const ['print', '0.0.0.0'],
        runInShell: true,
      ).timeout(const Duration(milliseconds: 1200));
      final stdoutText = '${routePrint.stdout}';
      final routes = WindowsDefaultGatewayParser.parseRoutePrint(stdoutText);
      final best = WindowsDefaultGatewayParser.selectBestRoute(
        routes,
        localIps: localIps,
      );
      if (best != null) {
        _windowsRouteCache = best;
        _windowsRouteCacheAt = now;
        return best;
      }
    } catch (_) {
      // fallback to ipconfig
    }

    try {
      final ipconfig = await Process.run(
        'ipconfig',
        const [],
        runInShell: true,
      ).timeout(const Duration(milliseconds: 1200));
      final gateway = WindowsDefaultGatewayParser.parseIpconfig(
        '${ipconfig.stdout}',
      );
      if (gateway != null) {
        final best = WindowsDefaultRoute(gateway: gateway);
        _windowsRouteCache = best;
        _windowsRouteCacheAt = now;
        return best;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<List<String>> _localPrivateIpv4s() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final ips = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback &&
              addr.type == InternetAddressType.IPv4 &&
              _isPrivateLanIp(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
      return ips;
    } catch (_) {
      return const [];
    }
  }

  /// Default Gateway دستگاه — فقط از OS
  Future<String?> getDefaultGatewayOrRouterIp() async {
    final discovery = await discoverDeviceDefaultGateway();
    return discovery.ip;
  }

  /// آدرس روتر همان Default Gateway سیستم‌عامل است. شبکه برای پیدا کردن روتر اسکن نمی‌شود.
  Future<String?> discoverRouterApiHost() async {
    return (await discoverDeviceDefaultGateway()).ip;
  }

  /// برچسب فارسی منبع gateway برای لاگ
  String sourceLabel(DeviceGatewaySource source) {
    switch (source) {
      case DeviceGatewaySource.system:
        return 'سیستم‌عامل (جدول مسیریابی / DHCP)';
      case DeviceGatewaySource.unavailable:
        return 'یافت نشد';
    }
  }

  /// دریافت Default Gateway از route table RouterOS (WAN روتر — فقط تشخیصی)
  /// برای تنظیم host اتصال کلاینت استفاده نکنید؛ از [discoverDeviceDefaultGateway] استفاده کنید.
  Future<String?> getDefaultGateway() async {
    try {
      final serviceManager = MikroTikServiceManager();
      if (serviceManager.isConnected) {
        return await serviceManager.getDefaultGateway();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// دریافت همه اطلاعات شبکه (IPv4 Address و Default Gateway)
  Future<Map<String, String?>> getNetworkInfo() async {
    final deviceIp = await getDeviceIPv4Address();
    final discovery = await discoverDeviceDefaultGateway();

    return {
      'deviceIp': deviceIp,
      'defaultGateway': discovery.ip,
      'gatewaySource': sourceLabel(discovery.source),
    };
  }
}
