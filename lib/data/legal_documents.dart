/// متون حقوقی داخل‌برنامه‌ای — هماهنگ با Seller در App Store: Muhammad Aref Abdul Hadi
class LegalDocuments {
  LegalDocuments._();

  /// نام Seller در App Store Connect (باید با حساب انتشار یکی باشد)
  static const String appStoreSellerName = 'Muhammad Aref Abdul Hadi';

  static const String supportPhonePrimary = '0795336608';
  static const String supportPhoneSecondary = '0700336608';

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
      english ? _privacyEn : _privacyFa;

  static String termsOfUse({required bool english}) =>
      english ? _termsEn : _termsFa;

  static const String _privacyFa = '''
سیاست حریم خصوصی — جهان بیت (Jahan Bit)

آخرین به‌روزرسانی: اکتبر ۲۰۲۶
ناشر App Store: $appStoreSellerName
نسخهٔ وب: $privacyPolicyPublicUrl

۱. معرفی
جهان بیت یک برنامهٔ مدیریت شبکهٔ محلی برای مشترکین اینترنت است که به روتر MikroTik (RouterOS) روی شبکهٔ محلی شما متصل می‌شود و امکان مشاهدهٔ دستگاه‌ها، مدیریت دسترسی، تنظیم وای‌فای و مشاهدهٔ پنل سرویس ارائه‌دهنده را فراهم می‌کند.

۲. داده‌هایی که جمع‌آوری یا ذخیره می‌کنیم
- اعتبارنامهٔ ورود به روتر (نام کاربری و رمز عبور RouterOS): فقط روی دستگاه شما و در حافظهٔ امن سیستم (Android Keystore / iOS Keychain) ذخیره می‌شود.
- نشانی IP/هاست روتر، پورت، تنظیمات SSL، ولایت، زبان و تم: به‌صورت محلی روی دستگاه ذخیره می‌شود.
- شناسه‌های محلی دستگاه‌های شبکه (مانند MAC/نام) برای نمایش فهرست و اعمال مسدودسازی محلی: فقط روی دستگاه شما نگهداری می‌شود.
- برنامه به‌طور پیش‌فرض دادهٔ حساب ابری برای جهان بیت نمی‌سازد و اطلاعات ورود روتر را به سرورهای ناشر ارسال نمی‌کند.

۳. دسترسی به شبکهٔ محلی
برنامه برای کشف دروازهٔ پیش‌فرض و اتصال به روتر MikroTik شما به شبکهٔ محلی دسترسی دارد. این دسترسی فقط برای عملکرد اصلی برنامه استفاده می‌شود.

۴. WebView پنل سرویس
تب سرویس اینترنت ممکن است پنل کاربری ارائه‌دهنده را در نمای وب داخلی نمایش دهد. ناوبری به میزبان‌های تأیید‌شده محدود است.

۵. اشتراک‌گذاری
دادهٔ ورود روتر یا فهرست دستگاه‌ها برای تبلیغات/فروش به اشخاص ثالث ارسال نمی‌شود. SDK تبلیغات وجود ندارد.

۶. امنیت
اعتبارنامه‌ها در ذخیره‌سازی امن سیستم نگهداری می‌شوند. اتصال API معمولاً روی شبکهٔ محلی است.

۷. حذف داده
با «پاک‌سازی داده‌های محلی» اعتبارنامه‌ها و تنظیمات روی دستگاه حذف می‌شوند. حساب مشترک ISP تابع سیاست ارائه‌دهنده است.

۸. کودکان
ابزار شبکهٔ عمومی است و محتوای کودک‌محور ندارد.

۹. تماس
$contactFa
''';

  static const String _privacyEn = '''
Privacy Policy — Jahan Bit

Last updated: October 2026
App Store seller: $appStoreSellerName
Web version: $privacyPolicyPublicUrl

1. Overview
Jahan Bit connects to your MikroTik RouterOS device on your LAN to manage devices, Wi‑Fi, and the ISP subscriber panel.

2. Data we store
Router credentials stay on-device in secure storage. Host/port/SSL/province/language/theme are local. LAN device identifiers for ban/unban stay on-device. No Jahan Bit cloud account; credentials are not uploaded to the publisher’s servers.

3. Local network
Used only to discover the gateway and talk to the MikroTik router / approved ISP panel hosts.

4. WebView
ISP panel navigation is limited to allowlisted hosts.

5. Sharing
No ad SDKs; no sale of router credentials or LAN device lists.

6. Deletion
Use Clear local data in Settings to erase stored credentials and preferences on this device.

7. Contact
$contactEn
''';

  static const String _termsFa = '''
شرایط استفاده — جهان بیت (Jahan Bit)

آخرین به‌روزرسانی: اکتبر ۲۰۲۶
ناشر App Store: $appStoreSellerName

۱. پذیرش شرایط با نصب/استفاده.
۲. ابزار مدیریت روتر MikroTik و پنل ISP است؛ اپ رسمی MikroTik نیست.
۳. کاربر مسئول امنیت رمز روتر و استفادهٔ قانونی است.
۴. استفاده برای دسترسی غیرمجاز یا شنود غیرقانونی ممنوع است.
۵. پرداخت داخل پنل ISP تابع همان ارائه‌دهنده است؛ IAP کالای دیجیتال جدا نداریم.
۶. سیاست حریم خصوصی: $privacyPolicyPublicUrl
۷. تماس: $supportPhonePrimary · $supportPhoneSecondary
$copyrightNotice
''';

  static const String _termsEn = '''
Terms of Use — Jahan Bit

Last updated: October 2026
App Store seller: $appStoreSellerName

1. By using the app you accept these terms.
2. LAN MikroTik / ISP utility — not an official MikroTik product.
3. You are responsible for lawful use and router security.
4. No unauthorized network access or interception.
5. ISP panel payments follow the provider’s terms.
6. Privacy policy: $privacyPolicyPublicUrl
7. Contact: $supportPhonePrimary · $supportPhoneSecondary
$copyrightNotice
''';

  static const String contactFa =
      'پشتیبانی تلفنی: $supportPhonePrimary · $supportPhoneSecondary\n'
      'ناشر: $appStoreSellerName\n'
      'نسخهٔ وب سیاست حریم خصوصی: $privacyPolicyPublicUrl\n'
      '$copyrightNotice';

  static const String contactEn =
      'Support phones: $supportPhonePrimary · $supportPhoneSecondary\n'
      'Publisher: $appStoreSellerName\n'
      'Web privacy policy: $privacyPolicyPublicUrl\n'
      '$copyrightNotice';
}
