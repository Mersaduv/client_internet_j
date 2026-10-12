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
Jahan Bit is a LAN utility for ISP subscribers.
It connects to the customer's MikroTik RouterOS API on the local network
(default gateway / port 8728) to list devices, ban/unban, shape speed, and
change Wi-Fi. The Internet Service tab loads only allowlisted ISP panel hosts.
No cloud account is created by the app; credentials stay on-device.
No VPN / Packet Tunnel / advertising SDKs.

Demo: connect a phone to a MikroTik LAN and use router API user credentials.
Privacy Policy and Terms are available under Settings.
Local Network permission is required to discover the gateway and talk to the router.
```

## Signing Android

- `android/app/key.properties` (gitignored) + `android/app/keystore/jahanbit-upload.jks`
- از `key.properties.example` کپی بگیرید اگر روی ماشین دیگر بیلد می‌کنید.
- **keystore را بکاپ بگیرید**؛ بدون آن به‌روزرسانی Play ممکن نیست.

## ATS / Cleartext

- iOS: بدون `NSAllowsArbitraryLoads`؛ فقط `NSAllowsLocalNetworking` + exception برای IPهای پنل
- Android: `usesCleartextTraffic=false` + domain-config محدود
