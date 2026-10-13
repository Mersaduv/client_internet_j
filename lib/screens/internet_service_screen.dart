import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/internet_packages_data.dart';
import '../services/settings_service.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/panel_url_resolver.dart';
import '../utils/webview_host_allowlist.dart';
import '../widgets/province_selector.dart';

/// بعد از بارگذاری، محدودیت viewport (مثل user-scalable=no) را شل می‌کند تا pinch روی اندروید و iOS جواب بدهد.
const String _kUnrestrictViewportForPinchZoom = r'''
(function() {
  try {
    function patch() {
      var nodes = document.querySelectorAll('meta[name="viewport"],meta[name=viewport]');
      var i, el, c;
      for (i = 0; i < nodes.length; i++) {
        el = nodes[i];
        c = el.getAttribute('content') || '';
        c = c.replace(/user-scalable\s*=\s*no/gi, 'user-scalable=yes');
        c = c.replace(/user-scalable\s*=\s*0/gi, 'user-scalable=yes');
        c = c.replace(/maximum-scale\s*=\s*1(?:\.\d+)?/gi, 'maximum-scale=10');
        if (!/user-scalable/i.test(c)) c = (c ? c + ',' : '') + 'user-scalable=yes';
        if (!/minimum-scale/i.test(c)) c += ',minimum-scale=0.25';
        if (!/maximum-scale/i.test(c)) c += ',maximum-scale=10';
        el.setAttribute('content', c);
      }
      if (nodes.length === 0 && document.head) {
        var m = document.createElement('meta');
        m.name = 'viewport';
        m.content = 'width=device-width,initial-scale=1,minimum-scale=0.25,maximum-scale=10,user-scalable=yes';
        document.head.insertBefore(m, document.head.firstChild);
      }
    }
    patch();
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', patch);
    }
  } catch (e) {}
})();
''';

/// صفحه WebView برای سرویس انترنت یا پنل‌های ثابت (مثل اطلاعات وای‌فای)
class InternetServiceScreen extends StatefulWidget {
  const InternetServiceScreen({
    super.key,
    this.fixedUrl,
    this.defaultTitle,
    this.allowUrlChange = false,
  });

  /// در صورت تنظیم، این آدرس به‌جای URL ولایت بارگذاری می‌شود.
  final String? fixedUrl;
  final String? defaultTitle;
  final bool allowUrlChange;

  @override
  State<InternetServiceScreen> createState() => _InternetServiceScreenState();
}

class _InternetServiceScreenState extends State<InternetServiceScreen> {
  InAppWebViewController? _webViewController;
  final SettingsService _settingsService = SettingsService();

  bool _isLoading = true;
  bool _loadingProvince = true;
  bool _pickerVisible = false;
  PackageProvince? _province;
  double _progress = 0.0;
  String? _currentUrl;
  String? _pageTitle;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _errorMessage;
  bool _showError = false;

  bool get _usesProvinceFlow => widget.fixedUrl == null;

  bool get _preferDesktopExperience =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_usesProvinceFlow) {
      _settingsService.packageProvinceListenable
          .addListener(_onSharedProvinceChanged);
      _bootstrapProvinceFlow();
    } else {
      _loadingProvince = false;
      _currentUrl = widget.fixedUrl;
      _isLoading = widget.fixedUrl!.trim().isNotEmpty;
      _loadFixedOrStoredUrl();
    }
  }

  @override
  void dispose() {
    if (_usesProvinceFlow) {
      _settingsService.packageProvinceListenable
          .removeListener(_onSharedProvinceChanged);
    }
    _webViewController?.dispose();
    super.dispose();
  }

  void _onSharedProvinceChanged() {
    if (!_usesProvinceFlow || !mounted) return;
    final next = PackageProvinceX.tryParse(
      _settingsService.packageProvinceListenable.value,
    );
    if (next == null || next == _province) return;
    _applyProvince(next, persist: false);
  }

  Future<void> _bootstrapProvinceFlow() async {
    final savedId = await _settingsService.getPackageProvinceId();
    final saved = PackageProvinceX.tryParse(savedId);
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _province = null;
        _currentUrl = null;
        _loadingProvince = false;
        _pickerVisible = true;
        _isLoading = false;
        _showError = false;
        _errorMessage = null;
      });
      return;
    }

    await _applyProvince(saved, persist: false);
  }

  Future<void> _applyProvince(
    PackageProvince province, {
    required bool persist,
  }) async {
    if (!mounted) return;
    setState(() {
      _province = province;
      _loadingProvince = true;
      _pickerVisible = false;
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final url = await PanelUrlResolver.resolveBest(province);
    if (!WebViewHostAllowlist.isAllowedUrl(url)) {
      if (!mounted) return;
      setState(() {
        _province = province;
        _currentUrl = null;
        _loadingProvince = false;
        _pickerVisible = false;
        _isLoading = false;
        _showError = true;
        _errorMessage =
            'آدرس پنل این ولایت مجاز نیست. با پشتیبانی جهان بیت تماس بگیرید.';
      });
      return;
    }
    if (!mounted) return;

    final previousUrl = _currentUrl;
    setState(() {
      _province = province;
      _currentUrl = url;
      _loadingProvince = false;
      _pickerVisible = false;
      _errorMessage = null;
      _showError = false;
      _isLoading = true;
      _progress = 0.0;
      _pageTitle = null;
      _canGoBack = false;
      _canGoForward = false;
      if (previousUrl != url) {
        _webViewController = null;
      }
    });

    // بعد از setState تا listener با ولایت فعلی هم‌خوان باشد و دوباره صدا نزند
    if (persist) {
      await _settingsService.setPackageProvinceId(province.id);
    }
    await _settingsService.setServiceUrl(url);

    if (!mounted) return;
    if (previousUrl == url && _webViewController != null) {
      try {
        await _webViewController!.reload();
      } catch (e) {
        debugPrint('province reload: $e');
      }
    }
  }

  Future<void> _failoverToNextPanelUrl(String reason) async {
    final province = _province;
    final current = _currentUrl;
    if (province == null || current == null) return;
    final next = PanelUrlResolver.nextAfter(province, current);
    if (next == null || next == current) return;
    debugPrint('[WEBVIEW] failover ($reason) -> $next');
    if (!mounted) return;
    setState(() {
      _currentUrl = next;
      _showError = false;
      _errorMessage = null;
      _isLoading = true;
      _progress = 0.0;
      _webViewController = null;
    });
    try {
      await _settingsService.setServiceUrl(next);
    } catch (_) {}
  }

  Future<void> _loadFixedOrStoredUrl() async {
    try {
      final resolved = (widget.fixedUrl ?? await _settingsService.getServiceUrl())
          .trim();
      var url = resolved.isEmpty
          ? SettingsService.defaultServiceUrl
          : resolved;
      if (!WebViewHostAllowlist.isAllowedUrl(url)) {
        if (mounted) {
          setState(() {
            _currentUrl = null;
            _isLoading = false;
            _showError = true;
            _errorMessage =
                'فقط پنل‌های تأیید‌شدهٔ سرویس اینترنت قابل نمایش هستند.';
          });
        }
        return;
      }
      final previous = _currentUrl;
      if (mounted) {
        setState(() {
          _currentUrl = url;
          _errorMessage = null;
          _showError = false;
          _isLoading = url.isNotEmpty;
        });
      }
      if (_webViewController != null &&
          previous != null &&
          previous != url &&
          url.isNotEmpty) {
        await _webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentUrl ??=
              widget.fixedUrl ?? SettingsService.defaultServiceUrl;
          if (_currentUrl == null ||
              _currentUrl!.isEmpty ||
              !WebViewHostAllowlist.isAllowedUrl(_currentUrl)) {
            _errorMessage = 'خطا در بارگذاری URL: $e';
            _showError = true;
            _currentUrl = null;
          }
        });
      }
    }
  }

  Future<void> _reload() async {
    if (_usesProvinceFlow && _province == null) {
      setState(() => _pickerVisible = true);
      return;
    }
    if (_webViewController != null) {
      await _webViewController!.reload();
      return;
    }
    if (_usesProvinceFlow && _province != null) {
      await _applyProvince(_province!, persist: false);
    } else {
      await _loadFixedOrStoredUrl();
    }
  }

  Future<void> _goBack() async {
    if (_webViewController != null && _canGoBack) {
      try {
        await _webViewController!.goBack();
      } catch (e) {
        debugPrint('Error in goBack: $e');
      }
    }
  }

  Future<void> _goForward() async {
    if (_webViewController != null && _canGoForward) {
      try {
        await _webViewController!.goForward();
      } catch (e) {
        debugPrint('Error in goForward: $e');
      }
    }
  }

  Future<void> _patchViewportForPinchZoom(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(
        source: _kUnrestrictViewportForPinchZoom,
      );
    } catch (e) {
      debugPrint('viewport zoom patch: $e');
    }
  }

  /// برای IP محلی/پنل‌ها از http و برای دامنه از https استفاده می‌کند.
  String _normalizeServiceUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) {
      return url;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      final host = url.split('/').first.split(':').first;
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      url = '${isIp ? 'http' : 'https'}://$url';
    }
    return url;
  }

  Future<void> _showUrlInputDialog() async {
    if (!widget.allowUrlChange) return;

    final urlController = TextEditingController(
      text: _currentUrl ??
          _province?.servicePanelUrl ??
          SettingsService.defaultServiceUrl,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ورود آدرس سایت'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'URL',
            hintText: 'https://jb-herat.mersadkarimi001.workers.dev/users/',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, urlController.text),
            child: const Text('بارگذاری'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final url = _normalizeServiceUrl(result);
      if (!WebViewHostAllowlist.isAllowedUrl(url)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'فقط آدرس پنل‌های تأیید‌شدهٔ جهان بیت مجاز است.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _settingsService.setServiceUrl(url);

      if (_webViewController != null) {
        setState(() {
          _currentUrl = url;
          _errorMessage = null;
          _showError = false;
          _isLoading = true;
        });
        await _webViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      } else {
        setState(() {
          _currentUrl = url;
          _errorMessage = null;
          _showError = false;
          _isLoading = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = AppTheme.primaryFor(theme.brightness);
    final l10n = AppLocalizations.of(context);
    final isEnglish = l10n?.locale.languageCode == 'en';
    final onAppBar = AppTheme.onAppBar(theme.brightness);
    final titleText =
        _pageTitle ?? widget.defaultTitle ?? l10n?.internetService ?? 'سرویس انترنت';

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.appBarFor(theme.brightness),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppBar(
            title: Text(
              titleText,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onAppBar),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: onAppBar,
            iconTheme: IconThemeData(color: onAppBar),
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            actions: [
              if (_usesProvinceFlow && _province != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Center(
                    child: ProvinceDropdown(
                      value: _province!,
                      isEnglish: isEnglish,
                      compact: true,
                      onChanged: (p) => _applyProvince(p, persist: true),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _canGoBack ? _goBack : null,
                tooltip: 'بازگشت',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _canGoForward ? _goForward : null,
                tooltip: 'جلو',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
                tooltip: 'بارگذاری مجدد',
              ),
              if (widget.allowUrlChange)
                IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: _showUrlInputDialog,
                  tooltip: 'تغییر آدرس',
                ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_loadingProvince)
            const Center(child: CircularProgressIndicator())
          else if (!_showError &&
              _currentUrl != null &&
              _currentUrl!.isNotEmpty)
            KeyedSubtree(
              key: ValueKey(
                _usesProvinceFlow
                    ? 'svc-${_province?.id ?? 'none'}-$_currentUrl'
                    : 'fixed-$_currentUrl',
              ),
              child: InAppWebView(
                preventGestureDelay: true,
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    groupName: 'pinch_zoom_viewport',
                    source: _kUnrestrictViewportForPinchZoom,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
                  ),
                ]),
                initialUrlRequest: URLRequest(url: WebUri(_currentUrl!)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  useHybridComposition: true,
                  useShouldOverrideUrlLoading: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  allowsBackForwardNavigationGestures: true,
                  userAgent: _preferDesktopExperience
                      ? null
                      : 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
                  supportZoom: true,
                  builtInZoomControls: true,
                  displayZoomControls: false,
                  minimumZoomScale: 0.25,
                  maximumZoomScale: 5.0,
                  ignoresViewportScaleLimits: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                    _progress = 0.0;
                    _showError = false;
                    _errorMessage = null;
                  });
                },
                onLoadStop: (controller, url) async {
                  setState(() {
                    _isLoading = false;
                    _currentUrl = url.toString();
                  });

                  try {
                    final title = await controller.getTitle();
                    if (title != null && mounted) {
                      setState(() {
                        _pageTitle = title;
                      });
                    }

                    try {
                      final canGoBack = await controller.canGoBack();
                      final canGoForward = await controller.canGoForward();
                      if (mounted) {
                        setState(() {
                          _canGoBack = canGoBack;
                          _canGoForward = canGoForward;
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _canGoBack = false;
                          _canGoForward = false;
                        });
                      }
                    }

                    await _patchViewportForPinchZoom(controller);
                  } catch (e) {
                    debugPrint('Error in onLoadStop: $e');
                  }
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100;
                  });
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == false) {
                    return;
                  }
                  final desc = error.description;
                  if (_province != null) {
                    unawaited(
                      _failoverToNextPanelUrl('load_error:$desc'),
                    );
                    return;
                  }
                  setState(() {
                    _isLoading = false;
                    _showError = true;
                    _errorMessage = 'خطا در بارگذاری صفحه: $desc';
                  });
                },
                onReceivedHttpError: (controller, request, response) {
                  if (request.isForMainFrame == false) {
                    return;
                  }
                  final statusCode = response.statusCode;
                  if (statusCode == null) return;
                  // Cloudflare edge / gateway failures → منبع بعدی
                  if (_province != null &&
                      (statusCode == 530 ||
                          statusCode == 502 ||
                          statusCode == 503 ||
                          statusCode == 1016)) {
                    unawaited(
                      _failoverToNextPanelUrl('http_$statusCode'),
                    );
                    return;
                  }
                  if (statusCode >= 400) {
                    setState(() {
                      _isLoading = false;
                      _showError = true;
                      _errorMessage =
                          'خطای HTTP $statusCode: ${response.reasonPhrase ?? "خطای ناشناخته"}';
                    });
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final requestUrl = navigationAction.request.url?.toString();
                  if (WebViewHostAllowlist.isAllowedUrl(requestUrl)) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  debugPrint('[WEBVIEW] blocked navigation: $requestUrl');
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            )
          else if (_showError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'خطا در بارگذاری',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'خطای ناشناخته',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_usesProvinceFlow &&
                        (_province == PackageProvince.nimroz ||
                            _province == PackageProvince.farah)) ...[
                      const SizedBox(height: 12),
                      Text(
                        isEnglish
                            ? 'This panel is only reachable on the local network of that province.'
                            : 'این پنل فقط روی شبکهٔ محلی همان ولایت در دسترس است.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تلاش مجدد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (_usesProvinceFlow) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _pickerVisible = true),
                        icon: const Icon(Icons.location_on_outlined),
                        label: Text(isEnglish ? 'Change province' : 'تغییر ولایت'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(color: primaryColor),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                    if (widget.allowUrlChange) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _showUrlInputDialog,
                        icon: const Icon(Icons.link),
                        label: const Text('تغییر آدرس'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(color: primaryColor),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (_usesProvinceFlow && _province == null)
            const SizedBox.shrink()
          else if (_currentUrl == null || _currentUrl!.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'آدرسی تنظیم نشده است',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'برای باز کردن سرویس اینترنت، آدرس سایت را وارد کنید.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.allowUrlChange) ...[
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showUrlInputDialog,
                        icon: const Icon(Icons.link),
                        label: const Text('ورود آدرس'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),

          if (_isLoading &&
              _progress > 0.0 &&
              !_pickerVisible &&
              _currentUrl != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                minHeight: 3,
              ),
            ),

          if (_usesProvinceFlow && _pickerVisible)
            ProvincePickerOverlay(
              isEnglish: isEnglish,
              requiredChoice: _province == null,
              selected: _province,
              subtitleFa:
                  'پنل سرویس اینترنت بر اساس ولایت متفاوت است. انتخاب شما ذخیره می‌شود.',
              subtitleEn:
                  'The internet service panel differs by province. Your choice will be saved.',
              onSelected: (province) =>
                  _applyProvince(province, persist: true),
              onDismiss: _province == null
                  ? null
                  : () => setState(() => _pickerVisible = false),
            ),
        ],
      ),
    );
  }
}
