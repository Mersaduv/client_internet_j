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
جهان بیت ابزار مدیریت شبکهٔ محلی برای مشترکین اینترنت است. اپ به روتر MikroTik (RouterOS) روی LAN شما متصل می‌شود تا دستگاه‌ها را نشان دهد، دسترسی را مدیریت کند، محدودیت سرعت اعمال کند، وای‌فای را تنظیم کند، بسته‌ها را نشان دهد و در صورت نیاز پنل مشترک ISP را در WebView داخلی با میزبان‌های ازپیش‌تأییدشده نمایش دهد. این اپ محصول رسمی MikroTik نیست.

۲. کنترل‌گر / ناشر
ناشر App Store: $appStoreSellerName
برند محصول: جهان بیت / Jahan Bit

۳. داده‌هایی که روی دستگاه شما پردازش یا ذخیره می‌شوند
- اعتبارنامهٔ RouterOS در حافظهٔ امن سیستم (Keystore / Keychain) در صورت «مرا به خاطر بسپار»
- تنظیمات اتصال: IP/هاست روتر، پورت، SSL، ولایت، زبان، تم
- شناسه‌های محلی دستگاه‌های LAN (نام/MAC/IP محلی/وضعیت مسدود) برای نمایش و اقدام محلی شما
- برچسب زمانی نشست محلی در صورت فعال بودن
اپ به‌طور پیش‌فرض حساب ابری جهان بیت نمی‌سازد و اعتبارنامهٔ روتر را به سرورهای ناشر ارسال نمی‌کند. ترافیک API عمدتاً بین دستگاه شما و روتر روی LAN است.

۴. داده‌هایی که جمع‌آوری نمی‌کنیم
موقعیت GPS برای ردیابی، Advertising ID، دفترچه تلفن/پیامک/تماس/دوربین/میکروفون، فروش داده به کارگزاران. SDK تبلیغات یا analytics تبلیغاتی نداریم.

۵. شبکهٔ محلی
برای کشف دروازه و اتصال به روتر MikroTik و پنل‌های تأییدشده روی LAN استفاده می‌شود؛ نه برای نقشه‌برداری مخفی یا شنود ترافیک.

۶. WebView پنل ISP
محتوا، حساب، پرداخت و حریم خصوصی پنل تحت کنترل ISP است. ناوبری به allowlist محدود است.

۷. امنیت انتقال (TLS / cleartext)
- میزبان‌های عمومی اینترنت فقط با HTTPS بارگذاری می‌شوند؛ cleartext به IP/دامنهٔ عمومی مجاز نیست.
- HTTP بدون TLS فقط برای میزبان‌های خصوصی/محلی تأییدشده (مثلاً پنل LAN ولایت یا CPE روی ۱۰.۱۰.۱۰.۲) ممکن است.
- گواهی TLS نامعتبر برای میزبان‌های عمومی پذیرفته نمی‌شود.

۸. اشتراک‌گذاری
اعتبارنامهٔ روتر یا فهرست LAN برای تبلیغات/فروش به اشخاص ثالث ارسال نمی‌شود. استفاده از پنل ISP تابع سیاست همان ارائه‌دهنده است.

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
Jahan Bit is a local-network management utility for internet subscribers. It connects to your MikroTik RouterOS device on your LAN to list devices, manage access, apply speed limits, change Wi‑Fi settings, show packages, and optionally display your ISP subscriber panel in an embedded WebView limited to allowlisted hosts. Jahan Bit is not an official MikroTik product.

2. Publisher / Controller
App Store seller: $appStoreSellerName
Product brand: Jahan Bit

3. Data Processed or Stored On Your Device
- RouterOS credentials in OS secure storage when Remember Me / local session is used
- Connection settings: router host/IP, port, SSL preference, province, language, theme
- LAN device identifiers (hostname/MAC/local IP/ban state) for listing and local actions you initiate
- Local session timestamp when enabled
Jahan Bit does not create its own cloud user account by default and does not upload router credentials to publisher servers. Router API traffic is primarily between your device and your router on the LAN.

4. Data We Do Not Collect
No GPS tracking, Advertising ID, contacts/SMS/calls/camera/microphone, or sale of personal data to brokers. No advertising or ad-analytics SDKs.

5. Local Network Access
Used only to discover the default gateway and connect to your MikroTik router / allowlisted LAN ISP panels — not for covert scanning or traffic interception.

6. ISP Panel WebView
Panel content, accounts, payments, and privacy practices are controlled by your ISP. Navigation is limited to allowlisted hosts.

7. Transport Security (TLS / Cleartext)
- Public internet hosts are loaded over HTTPS only; cleartext to public IPs/domains is not permitted.
- HTTP without TLS may be used only for approved private/local hosts (for example a province LAN panel or CPE at 10.10.10.2).
- Invalid TLS certificates are not accepted for public hosts.

8. Sharing
We do not sell or share router credentials or LAN device lists with advertisers. ISP panel use follows that provider’s policies.

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
