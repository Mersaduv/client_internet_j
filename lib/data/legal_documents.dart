import 'support_contacts.dart';

/// متون حقوقی داخل‌برنامه‌ای — هم‌تراز با https://jahan-bit.vercel.app
class LegalDocuments {
  LegalDocuments._();

  /// نام Seller در App Store Connect (باید با حساب انتشار یکی باشد)
  static const String appStoreSellerName = 'Muhammad Aref Abdul Hadi';

  static const String developerName = appStoreSellerName;
  static const String appNameFa = 'جهان بیت';
  static const String appNameEn = 'Jahan Bit';
  static const String copyrightNotice = '© 2026 Jahan Bit';

  /// لینک عمومی برای App Store Connect و Google Play
  static const String privacyPolicyPublicUrl =
      'https://jahan-bit.vercel.app/privacy-policy.html';
  static const String termsPublicUrl =
      'https://jahan-bit.vercel.app/terms-of-use.html';

  static String privacyPolicy({required bool english}) =>
      english ? _privacyEn() : _privacyFa();

  static String termsOfUse({required bool english}) =>
      english ? _termsEn() : _termsFa();

  static String _supportLinesFa() {
    final buf = StringBuffer();
    for (final province in SupportContacts.provinces) {
      buf.writeln(province.nameFa);
      for (final line in province.phones) {
        buf.writeln('  ${line.number} — ${line.roleFa}');
      }
    }
    return buf.toString().trimRight();
  }

  static String _supportLinesEn() {
    final buf = StringBuffer();
    for (final province in SupportContacts.provinces) {
      buf.writeln(province.nameEn);
      for (final line in province.phones) {
        buf.writeln('  ${line.number} — ${line.roleEn}');
      }
    }
    return buf.toString().trimRight();
  }

  static String _privacyFa() => '''
سیاست حریم خصوصی — جهان بیت (Jahan Bit)

آخرین به‌روزرسانی: اکتبر ۲۰۲۶
ناشر App Store: $appStoreSellerName
نسخهٔ وب (مرجع کامل): $privacyPolicyPublicUrl

۱. معرفی و دامنه
جهان بیت ابزار مدیریت شبکهٔ محلی برای مشترکین اینترنت است. اپ به روتر MikroTik (RouterOS) روی LAN شما متصل می‌شود تا دستگاه‌ها را نشان دهد، دسترسی را مدیریت کند، محدودیت سرعت اعمال کند، وای‌فای را تنظیم کند و بستهٔ اینترنت مشترک را نشان دهد. این اپ محصول رسمی MikroTik نیست.

۲. کنترل‌گر / ناشر
ناشر App Store: $appStoreSellerName
برند محصول: جهان بیت / Jahan Bit

۳. داده‌هایی که روی دستگاه شما پردازش یا ذخیره می‌شوند
- اعتبارنامهٔ RouterOS در حافظهٔ امن سیستم (Keystore / Keychain) در صورت «مرا به خاطر بسپار»
- نام کاربری، رمز و توکن نشست سرویس حسابداری ولایت در همان حافظهٔ امن، فقط برای نمایش بسته و نام مشترک
- تنظیمات اتصال: IP/هاست روتر، پورت، SSL، ولایت، زبان، تم
- شناسه‌های محلی دستگاه‌های LAN (نام/MAC/IP محلی/وضعیت مسدود) برای نمایش و اقدام محلی شما
- برچسب زمانی نشست محلی در صورت فعال بودن
اپ به‌طور پیش‌فرض حساب ابری جهان بیت نمی‌سازد و اعتبارنامهٔ روتر را به سرورهای ناشر ارسال نمی‌کند. ترافیک API عمدتاً بین دستگاه شما و روتر روی LAN است.

۴. داده‌هایی که جمع‌آوری نمی‌کنیم
موقعیت GPS برای ردیابی، Advertising ID، دفترچه تلفن/پیامک/تماس/دوربین/میکروفون، فروش داده به کارگزاران. SDK تبلیغات یا analytics تبلیغاتی نداریم.

۵. شبکهٔ محلی
فقط برای کشف دروازه و اتصال API به روتر MikroTik روی شبکهٔ خودتان است. برای بعضی آنتن‌ها (مثل LHG و SXT) صفحهٔ وای‌فای همان دستگاه در مرورگر پیش‌فرض گوشی باز می‌شود، نه داخل اپ. اپ ترافیک را شنود نمی‌کند.

۶. اطلاعات بسته
حجم، زمان، نام سرویس و نام مشترک از وب‌سرویس حسابداری همان ولایت با HTTPS خوانده می‌شود و فقط داخل اپ نشان داده می‌شود. مرورگر داخلی وجود ندارد.

۷. امنیت انتقال (TLS / cleartext)
- هر درخواست اینترنتی خود اپ فقط با HTTPS است.
- استثنای HTTP ناامن برای IP عمومی یا خصوصی در تنظیمات شبکهٔ اندروید و iOS وجود ندارد.
- صفحهٔ وای‌فای بعضی آنتن‌ها را خود اپ بارگذاری نمی‌کند؛ گوشی آن را در مرورگر پیش‌فرض باز می‌کند.
- گواهی TLS نامعتبر پذیرفته نمی‌شود.
- اتصال روتر از سوکت API شبکهٔ محلی است، نه از بارگذاری صفحهٔ وب.

۸. اشتراک‌گذاری
اعتبارنامهٔ روتر یا فهرست دستگاه‌های LAN برای تبلیغات فروخته یا ارسال نمی‌شود. ورود حسابداری فقط به نشانی HTTPS همان ولایت می‌رود.

۹. نگه‌داری و حذف
خروج، «پاک‌سازی داده‌های محلی»، یا حذف اپ داده‌های محلی را طبق سیستم‌عامل پاک می‌کند. حساب ISP تابع قرارداد همان ارائه‌دهنده است.

۱۰. کودکان
ابزار شبکهٔ عمومی است؛ محتوای کودک‌محور ندارد و عمداً دادهٔ کودکان را برای تبلیغات جمع‌آوری نمی‌کند.

۱۱. حقوق شما
بسته به حوزهٔ قضایی ممکن است حق دسترسی/حذف داشته باشید؛ سریع‌ترین مسیر معمولاً پاک‌سازی محلی یا حذف اپ است.

۱۲. تغییرات
تاریخ «آخرین به‌روزرسانی» معیار است. این متن و URL عمومی باید هم‌خوان بمانند.

۱۳. تماس پشتیبانی (بر اساس ولایت)
${_supportLinesFa()}
ناشر: $appStoreSellerName
$copyrightNotice
''';

  static String _privacyEn() => '''
Privacy Policy — Jahan Bit

Last updated: October 2026
App Store seller: $appStoreSellerName
Web version (canonical): $privacyPolicyPublicUrl

1. Overview and Scope
Jahan Bit is a local-network management utility for internet subscribers. It connects to your MikroTik RouterOS device on your LAN to list devices, manage access, apply speed limits, change Wi‑Fi settings, and show the subscriber internet package. Jahan Bit is not an official MikroTik product.

2. Publisher / Controller
App Store seller: $appStoreSellerName
Product brand: Jahan Bit

3. Data Processed or Stored On Your Device
- RouterOS credentials in OS secure storage when Remember Me / local session is used
- Accounting username, password, and session token in the same secure storage, used only to show the package and subscriber name
- Connection settings: router host/IP, port, SSL preference, province, language, theme
- LAN device identifiers (hostname/MAC/local IP/ban state) for listing and local actions you initiate
- Local session timestamp when enabled
Jahan Bit does not create its own cloud user account by default and does not upload router credentials to publisher servers. Router API traffic is primarily between your device and your router on the LAN.

4. Data We Do Not Collect
No GPS tracking, Advertising ID, contacts/SMS/calls/camera/microphone, or sale of personal data to brokers. No advertising or ad-analytics SDKs.

5. Local Network Access
Used only to discover the default gateway and open the MikroTik API on your own LAN. On some antennas (such as LHG and SXT) the Wi‑Fi page of that device opens in the phone’s default browser, not inside the app. The app does not intercept traffic.

6. Package information
Volume, time, service name, and the subscriber name are read over HTTPS from that province’s accounting service and shown only inside the app. There is no in-app browser.

7. Transport Security (TLS / Cleartext)
- Every internet request made by the app uses HTTPS.
- Android and iOS network settings do not allow insecure HTTP exceptions for public or private addresses.
- On some antennas the Wi‑Fi page is not loaded by the app; the phone opens it in the default browser.
- Invalid TLS certificates are not accepted.
- The router connection is a local API socket, not a web page.

8. Sharing
Router credentials and LAN device lists are not sold or sent to advertisers. The accounting login goes only to that province’s HTTPS address.

9. Retention and Deletion
Logout, Clear local data, or uninstall removes on-device app data per OS behavior. ISP accounts remain subject to the ISP’s contract.

10. Children
General network utility; not child-directed; does not knowingly collect children’s data for advertising.

11. Your Rights
Depending on jurisdiction you may have access/deletion rights; the fastest path is usually Clear local data or uninstall.

12. Changes
The “Last updated” date controls. Keep this in-app text aligned with the public URL.

13. Support Contacts (by province)
${_supportLinesEn()}
Publisher: $appStoreSellerName
$copyrightNotice
''';

  static String _termsFa() => '''
شرایط استفاده — جهان بیت (Jahan Bit)

آخرین به‌روزرسانی: اکتبر ۲۰۲۶
ناشر App Store: $appStoreSellerName

۱. با نصب یا استفاده، این شرایط را می‌پذیرید.
۲. ابزار مدیریت روتر MikroTik و مشاهدهٔ پنل ISP است؛ محصول رسمی MikroTik نیست.
۳. شما مسئول امنیت رمز روتر، شبکهٔ محلی و استفادهٔ قانونی مطابق قرارداد ISP هستید. دسترسی غیرمجاز یا شنود غیرقانونی ممنوع است.
۴. پرداخت/اشتراک داخل پنل ISP تابع شرایط همان ارائه‌دهنده است؛ جهان بیت فروش کالای دیجیتال جدا از طریق IAP برای آن سرویس‌ها انجام نمی‌دهد.
۵. اپ «همان‌گونه که هست» ارائه می‌شود و به در دسترس بودن روتر/شبکه/سیستم‌های ISP وابسته است.
۶. سیاست حریم خصوصی: $privacyPolicyPublicUrl
۷. تماس:
${_supportLinesFa()}
$copyrightNotice
''';

  static String _termsEn() => '''
Terms of Use — Jahan Bit

Last updated: October 2026
App Store seller: $appStoreSellerName

1. By installing or using Jahan Bit you accept these Terms.
2. MikroTik LAN management utility with optional ISP panel viewing — not an official MikroTik product.
3. You are responsible for router credentials, your LAN, and lawful use under your ISP agreement. Unauthorized access or unlawful interception is prohibited.
4. Payments or subscription management inside an ISP web panel follow that provider’s terms. Jahan Bit does not sell separate digital goods via IAP for those ISP services.
5. The app is provided “as is” and depends on router, network, and ISP system availability.
6. Privacy policy: $privacyPolicyPublicUrl
7. Contact:
${_supportLinesEn()}
$copyrightNotice
''';
}
