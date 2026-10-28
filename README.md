# القادسية لتجارة مواد خام البلاستيك — نظام CRM

تطبيق Android (Flutter) متصل بسيرفر مركزي (ASP.NET Core + PostgreSQL) لتسجيل العملاء والموردين والبحث الذكي والتقارير.

| المجلد | المحتوى |
|---|---|
| `app/` | تطبيق Flutter (Android أولًا، قابل للتوسع للاب) |
| `server/` | Web API بطبقات: Domain / Application / Infrastructure / Api + الاختبارات |
| `docs/` | تقرير التحليل والخطة، تقارير المراحل، المراجع الأصلية |
| `docs/reference/` | مستندات المتطلبات والتصميمات المعتمدة والشعار الأصلي (لا تُعدل) |

## المتطلبات

- Flutter 3.47.7 (Dart 3.13)
- .NET SDK 10.0 (LTS)
- PostgreSQL 16 (محليًا أو عبر `docker compose up -d`)
- Android SDK + JDK 17 لبناء APK

## تشغيل السيرفر محليًا

```bash
docker compose up -d            # أو PostgreSQL محلي بنفس بيانات docker-compose.yml
cd server
export Bootstrap__AdminPassword='اختر-كلمة-مرور-مؤقتة1'
dotnet run --project src/Qadisiyah.Api --launch-profile http
```

- السيرفر يعمل على `http://0.0.0.0:5080` ويطبق ترحيلات قاعدة البيانات تلقائيًا.
- عند أول تشغيل فقط يُنشأ حساب `admin` بكلمة المرور المؤقتة أعلاه، ويُطلب تغييرها عند أول دخول.
- مفتاح JWT الموجود في `appsettings.Development.json` للتطوير فقط؛ السيرفر يرفض تشغيله خارج Development.

## تشغيل التطبيق

```bash
cd app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080   # المحاكي
flutter run --dart-define=API_BASE_URL=http://<IP-الجهاز>:5080  # هاتف على نفس الشبكة
flutter build apk --debug --dart-define=API_BASE_URL=http://<IP>:5080
```

نسخة debug فقط تسمح بالاتصال عبر HTTP لسيرفر التطوير؛ نسخة release تتطلب HTTPS.

## الاختبارات

```bash
cd app && flutter analyze && flutter test
cd server && dotnet test     # يحتاج PostgreSQL؛ قاعدة الاختبار تُحدد بـ QADISIYAH_TEST_DB
```

- صور الشاشات المرجعية (golden) في `app/test/golden/goldens/`.
- تحديثها بعد تغيير بصري مقصود: `flutter test --update-goldens --tags golden`.

## سيرفر تجريبي

- التشغيل الأول: `docs/05-trial-server-plan.md` و`deploy/trial/`.
- **التحديث** (تراكمي، بدون حذف بيانات أو إعادة تثبيت): `docs/06-update-guide.md` — `bash deploy/trial/update-trial.sh`.
- ممنوع `docker compose down -v` على سيرفر التجربة: يحذف قاعدة البيانات.

## CI

`.github/workflows/ci.yml` يبني السيرفر ويختبره على PostgreSQL، ويحلل التطبيق ويختبره، ثم يبني APK للتجربة (debug) ويرفعه كـ artifact.
ويختبر الترقية فعليًا: تحديث سيرفر التجربة من الإصدار المثبت (`ff9087b`) مع التحقق من بقاء البيانات والحسابات و`.env`،
وتثبيت APK الجديد فوق السابق على محاكي Android مع بقاء بيانات التطبيق.
