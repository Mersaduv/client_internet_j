# آماده‌سازی انتشار فروشگاه — Jahan Bit

شناسهٔ یکتا:
- Android `applicationId`: `com.jahanbit.app`
- iOS Bundle ID: `com.jahanbit.app`

## قبل از آپلود

1. لینک عمومی Privacy (فعال روی Vercel / پروژه `jahan-bit`): `https://jahan-bit.vercel.app/privacy-policy.html`
2. لینک Terms: `https://jahan-bit.vercel.app/terms-of-use.html` — همین URLها را در **App Store Connect** و **Play Console** و داخل اپ (`LegalDocuments.privacyPolicyPublicUrl`) قرار دهید.
3. در اپ، مسیرهای Settings → Privacy Policy / Terms همیشه در دسترس‌اند (الزام داخل‌برنامه).

## Google Play — Data safety (پیشنهاد پر کردن)

| داده | جمع‌آوری؟ | اشتراک؟ | هدف |
|------|-----------|---------|-----|
| App info / settings | بله (محلی روی دستگاه) | خیر | عملکرد اپ |
| Device or other IDs (MAC/hostname محلی) | بله (محلی) | خیر | مدیریت دستگاه‌های LAN |
| Credentials (RouterOS) | بله (محلی امن) | خیر | ورود به روتر |
| Location | خیر | — | — |
| Advertising ID | خیر | — | — |

Encryption in transit: برای پنل‌های HTTP محلی/ISP محدود، در صورت ارسال از دستگاه اعلام دقیق کنید؛ اعتبارنامه روتر به سرور جهان بیت ارسال نمی‌شود.
Data deletion: کاربر می‌تواند «پاک‌سازی داده‌های محلی» را انجام دهد.

## Apple — Privacy Nutrition Labels

- Data Not Linked to You / On Device: تنظیمات، اعتبارنامهٔ روتر (در Keychain)، شناسه‌های دستگاه LAN برای ban محلی
- Tracking: خیر
- Third-party ads: خیر

## App Review Notes (نمونه)

```
Sign-in required.
Username: jb.admin
Password: jb@admin120

Jahan Bit is a LAN utility for ISP subscribers in Afghanistan (Herat, Nimroz,
Farah). A normal account connects to that subscriber's MikroTik RouterOS API
on the phone's local network (default gateway, TCP port 8728). After that
login succeeds, the app asks only for that subscriber's username and shows
their own package volume. The subscriber password is not sent to DeltaSIB.
The app does not create router users. No VPN, no in-app purchase, no
advertising SDK.

The tester is the username jb.admin. Please sign in with the password above
from any network — a MikroTik router is not required. After sign-in the app
loads that account's live DeltaSIB package. Every other username still needs
a live router.

What you will see:
1. The app tries the local router for a few seconds.
2. If no RouterOS API answers, a bilingual dialog explains that this phone is
   not connected to MikroTik.
3. Continue opens the full app on an in-phone simulator (clearly labeled).
   Connected devices, banned devices, ban/unban, speed limit, lock new
   connections, and Wi-Fi all work and change the on-screen lists.
4. Every action runs the same RouterOS API sentence the live app sends
   (for example /ip/firewall/raw/add, /ip/dhcp-server/set,
   /ip/dhcp-server/lease/set). Open "API log" on the yellow banner to read
   the command and the simulated reply. Nothing is sent to a customer router.

Why: reviewers are not on an Afghan subscriber LAN, so a normal router
password cannot open the app. This one account lets you exercise every
MikroTik screen without that hardware. All other users still need their own
router on the local network.

Privacy Policy and Terms are under Settings.
Local Network permission is used only when a real router is on the LAN.
```

## Signing Android

- `android/app/key.properties` (gitignored) + `android/app/keystore/jahanbit-upload.jks`
- از `key.properties.example` کپی بگیرید اگر روی ماشین دیگر بیلد می‌کنید.
- **keystore را بکاپ بگیرید**؛ بدون آن به‌روزرسانی Play ممکن نیست.

## ATS / Cleartext

- iOS: بدون `NSAllowsArbitraryLoads`؛ فقط `NSAllowsLocalNetworking` + exception برای IPهای پنل
- Android: `usesCleartextTraffic=false` + domain-config محدود
