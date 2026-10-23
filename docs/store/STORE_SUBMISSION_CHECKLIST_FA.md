# آماده‌سازی انتشار فروشگاه — Jahan Bit

شناسهٔ یکتا:
- Android `applicationId`: `com.jahanbit.app`
- iOS Bundle ID: `com.jahanbit.app`

## قبل از آپلود

1. لینک عمومی Privacy (فعال روی Vercel / پروژه `jahan-bit`): `https://jahan-bit.vercel.app/privacy-policy.html` — قبل از ارسال، فایل `docs/store/privacy_policy.html` (۲۰ اکتبر ۲۰۲۶) را روی همین آدرس منتشر کنید. صفحهٔ زندهٔ قبلی هنوز نشست ۱۴روزه و «عدم ارسال به سرور» را می‌گوید و با اپ جور نیست.
2. لینک Terms: `https://jahan-bit.vercel.app/terms-of-use.html` — همین URLها را در **App Store Connect** و **Play Console** و داخل اپ (`LegalDocuments.privacyPolicyPublicUrl`) قرار دهید.
3. در اپ، مسیرهای Settings → Privacy Policy / Terms همیشه در دسترس‌اند (الزام داخل‌برنامه).

## Google Play — Data safety (پیشنهاد پر کردن)

| داده | جمع‌آوری؟ | اشتراک؟ | هدف |
|------|-----------|---------|-----|
| App info / settings | بله (محلی روی دستگاه) | خیر | عملکرد اپ |
| Device or other IDs (MAC/hostname محلی) | بله (محلی) | خیر | مدیریت دستگاه‌های LAN |
| Account info (username, password, session) | بله، به ورکر HTTPS همان ولایت | خیر (فروش نمی‌شود) | ورود و نمایش بسته |
| Credentials (RouterOS) | بله، روی دستگاه؛ رمز یک‌بارمصرف یک بار با HTTPS برمی‌گردد | خیر | ورود به روتر |
| Location | خیر | — | — |
| Advertising ID | خیر | — | — |

Encryption in transit: برای پنل‌های HTTP محلی/ISP محدود، در صورت ارسال از دستگاه اعلام دقیق کنید؛ اعتبارنامه روتر به سرور جهان بیت ارسال نمی‌شود.
Data deletion: «حذف حساب از این برنامه» آن نام کاربری را از ورکر همان ورود کامل حذف می‌کند (همهٔ نشست‌ها و رمزهای ورود) و دادهٔ گوشی را پاک می‌کند. حساب دلتاسیب حذف نمی‌شود. هرات و فراه یک ورکر دارند؛ نیمروز جداست. در فرم Play همان URL سیاست حریم خصوصی را برای حذف داده بدهید.

## Apple — Privacy Nutrition Labels

مطابق `PrivacyInfo.xcprivacy`. این‌ها Collected، Linked to the user، و Not used for tracking هستند. هدف: App Functionality.

- User ID: نام کاربری و نشست
- Name: نام کاربری مشترک
- Other Data Types: رمز Winbox یک‌بارمصرف که یک بار برمی‌گردد و روی سرور نمی‌ماند
- Tracking: خیر
- Third-party ads: خیر
- Location و Advertising ID: خیر

## App Review Notes (نمونه)

```
Sign-in required. Choose province Herat, then sign in with the username and
password issued for the review account. The app shows Username and Password
fields, the same pair requested in App Review Information.
Username: jb.admin
Password: PASTE_THE_PERMANENT_REVIEW_PASSWORD_HERE

Do not commit that password. The router password bound to a one-time sign-in
will not match the review network. After sign-in the app still opens every screen
(devices, packages, Wi-Fi, settings) so the review can be completed.
A normal subscriber still needs their own router on the local network.

No VPN, no in-app purchase, no advertising SDK.
Privacy Policy and Terms are under Settings.
Logout deletes the server session and the data stored on the device.
Local Network permission is used only to reach a router on the same LAN.
The app does not load public HTTP addresses.
```

## Signing Android

- `android/app/key.properties` (gitignored) + `android/app/keystore/jahanbit-upload.jks`
- از `key.properties.example` کپی بگیرید اگر روی ماشین دیگر بیلد می‌کنید.
- **keystore را بکاپ بگیرید**؛ بدون آن به‌روزرسانی Play ممکن نیست.

## ATS / Cleartext

- iOS: بدون `NSAllowsArbitraryLoads`؛ فقط `NSAllowsLocalNetworking`
- Android: `usesCleartextTraffic=false` و بدون استثنای HTTP عمومی
- پنل هرات، فراه و نیمروز داخل اپ فقط HTTPS است
