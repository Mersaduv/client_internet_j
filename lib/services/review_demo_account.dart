/// Store-review login. Only [username] `jb.admin` can enter the simulator.
///
/// Any password is sent to RouterOS first. The simulator is allowed only when
/// that login fails. A successful gateway, port, and password login stays real.
abstract final class ReviewDemoAccount {
  static const String username = 'jb.admin';

  /// رمز جایگزین وقتی سرور رمز Winbox نفرستاده تا تلاش واقعی انجام شود.
  /// قبول شدن همین رمز توسط روتر شبیه‌ساز را باز نمی‌کند؛ شکست آن باز می‌کند.
  static const String simulatorPassword = 'review-sign-in';

  static bool isTester(String username) {
    return username.trim() == ReviewDemoAccount.username;
  }

  static bool matches(String username, String password) {
    return isTester(username) && password.isNotEmpty;
  }

  /// رمز مهم نیست؛ فقط نام کاربری حساب بازبینی مجوز شبیه‌ساز است.
  static bool simulatorFallback(String username) {
    return isTester(username);
  }
}
