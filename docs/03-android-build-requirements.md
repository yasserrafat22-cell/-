# متطلبات بناء APK وحالة Android SDK

تاريخ الفحص: 2026-10-27

## 1. ما يحتاجه المشروع (مستخرج من إعدادات Flutter 3.47.7 والمشروع)

| المكوّن | الإصدار المطلوب | المصدر الرسمي | الحالة في بيئة التطوير السحابية |
|---|---|---|---|
| Flutter SDK | 3.47.7 stable | storage.googleapis.com (Google) | ✅ مثبت |
| JDK | 17 أو أحدث | Ubuntu (OpenJDK) | ✅ OpenJDK 21 مثبت |
| Android SDK Command-line Tools | الأحدث | dl.google.com (Google) | ❌ غير مثبت — الموقع محجوب |
| Android SDK Platform | API 36 (compileSdk / targetSdk) | dl.google.com | ❌ |
| Android SDK Build-Tools | 36.x (الافتراضي في AGP 9.1) | dl.google.com | ❌ |
| Android SDK Platform-Tools | الأحدث | dl.google.com | ❌ |
| Android NDK | 28.2.13676358 (يحدده Flutter؛ يُستخدم لمعالجة مكتبات المحرك) | dl.google.com | ❌ |
| Gradle | 9.3.1 (wrapper) | services.gradle.org | ✅ الموقع متاح |
| Android Gradle Plugin | 9.1.0 | maven.google.com | ✅ الموقع متاح |
| Kotlin Gradle Plugin | 2.4.0 | plugins.gradle.org / Maven Central | ✅ متاح |
| مساحة القرص | ~6 GB للـ SDK والـ NDK وذاكرة Gradle | — | ✅ متاح ~30 GB |

- أقل إصدار Android يعمل عليه التطبيق: **Android 7.0 (API 24)**.
- الهدف: **Android 16 (API 36)**.

## 2. سبب تعذر البناء الآن

حزم Android SDK لا تُوزَّع رسميًا إلا من `dl.google.com`، وهذا النطاق محجوب في سياسة الشبكة الحالية لبيئة التطوير.

البدائل المتاحة على هذه البيئة لا تصلح:
- حزمة `android-sdk` في مستودعات Ubuntu قديمة (API 23 وأدوات بناء قديمة) ولا تبني مشروعًا يستهدف API 36.
- حزم Ubuntu من نوع installer تحمّل من `dl.google.com` نفسه.
- **لم أستخدم أي مصدر غير رسمي** (مرايا أو أرشيفات طرف ثالث)، ولم أغير أي إعداد للشبكة.

## 3. طرق البناء الآمنة (اختر واحدة)

| الطريقة | ما يلزم منك | الملاحظات |
|---|---|---|
| **أ. GitHub Actions** (موصى به) | تثبيت تطبيق Claude على المستودع حتى يُرفع الكود | ملف CI جاهز. خوادم GitHub عليها Android SDK رسمي، وتنتج `qadisiyah-debug-apk` كملف قابل للتحميل. لا يغير إعدادات الأمان |
| ب. السماح بنطاق `dl.google.com` | من إعدادات بيئة Claude ← Network access ← Allowed domains | نطاق Google الرسمي. بعدها أثبت الـ SDK عبر `sdkmanager` وأبني هنا مباشرة |
| ج. جهاز مطوّر محلي | Android Studio أو Command-line Tools من developer.android.com | `flutter build apk --debug` من مجلد `app/` |

## 4. أوامر البناء بعد توفر الـ SDK

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"
flutter doctor --android-licenses
cd app
flutter build apk --debug --dart-define=API_BASE_URL=http://<IP-السيرفر>:5080
# الناتج: app/build/app/outputs/flutter-apk/app-debug.apk
```

## 5. ملاحظات الإصدار

- **نسخة debug** للتجربة فقط: تقبل الاتصال بسيرفر التطوير عبر HTTP.
- **نسخة release** للتوزيع تحتاج:
  - مفتاح توقيع خاص بالشركة في `android/key.properties`، لا يُرفع للمستودع.
  - سيرفر يعمل بـ HTTPS.
  
  هذا من مهام المرحلة 8.
