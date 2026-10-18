import 'dart:io';

/// اتصال مشترک دلتاسیب تا ورود و خواندن بسته از همان سوکت استفاده کنند.
class SibHttp {
  SibHttp._();

  static final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 20);
}
