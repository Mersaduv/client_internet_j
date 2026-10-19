/// Store-review login. Simulator mode never applies to any other username.
///
/// The tester is identified by [username]. The password they type is kept for
/// a real router attempt and is not compared to a fixed review secret.
abstract final class ReviewDemoAccount {
  static const String username = 'jb.admin';

  /// فقط وقتی رمز Winbox از سرور نیامده. با رمز واقعی روتر شبیه‌ساز باز نمی‌شود.
  static const String simulatorPassword = 'review-sign-in';

  static bool isTester(String username) {
    return username.trim() == ReviewDemoAccount.username;
  }

  static bool matches(String username, String password) {
    return isTester(username) && password.isNotEmpty;
  }

  static bool simulatorFallback(String username, String password) {
    return isTester(username) && password == simulatorPassword;
  }
}
