import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/utils/webview_host_allowlist.dart';

void main() {
  test('allows known ISP and CPE hosts with store-safe schemes', () {
    expect(
      WebViewHostAllowlist.isAllowedUrl(
        'https://jb-herat.mersadkarimi001.workers.dev/users/',
      ),
      isTrue,
    );
    // Public cleartext must be blocked (store policy).
    expect(
      WebViewHostAllowlist.isAllowedUrl('http://165.99.189.40:9394/users/'),
      isFalse,
    );
    expect(
      WebViewHostAllowlist.isAllowedUrl(
        'http://149.54.23.54:9999/users/',
      ),
      isTrue,
    );
    expect(
      WebViewHostAllowlist.isAllowedUrl('http://192.168.10.10/login'),
      isTrue,
    );
    expect(
      WebViewHostAllowlist.isAllowedUrl('http://10.10.10.2/'),
      isTrue,
    );
    expect(
      WebViewHostAllowlist.isAllowedUrl('https://example.com'),
      isFalse,
    );
    expect(
      WebViewHostAllowlist.isAllowedUrl('http://user.ariyabod.af/users'),
      isFalse,
    );
    expect(WebViewHostAllowlist.isAllowedUrl('about:blank'), isTrue);
  });
}
