# الإصدار 0.7.0 — الإدخال السريع: التقرير وخطوات النشر والتنظيف

- الفرع: `claude/batch-02-eight-fixes`. السيرفر `0.7.0`، والتطبيق `0.7.0+9` (Version Code من CI = 1000 + رقم التشغيل).
- الأساس السابق على سيرفر التجربة والهواتف: `0.6.0` (`5bdc099`، Version Code 1033).
- قائمة التنفيذ التفصيلية للمراحل 0–4: `docs/12-quick-entry-0.7.0-plan.md`.

## ما يتغير للمستخدم

- **الـ Grade اختياري في الإدخال السريع فقط**: الاسم والموبايل المصري والخامة إلزامية. الـ Grade غير الموجود في الكتالوج
  يُحفظ نصًا «غير موثق» ويظهر ويُبحث فيه ويُصدَّر مميزًا، ولا يُضاف للكتالوج أبدًا. الملتبس يحتاج تأكيدًا صريحًا.
  التسجيل اليدوي لم يتغير.
- **اللصق المباشر** يفصل السجلات حسب الجهة (حتى في سطر واحد)، ويستخرج 668 و5502 و575P وPP500 و218W وTR144، ولا يعرض
  تعيين أعمدة Excel للنص الحر.
- **Excel**: اكتشاف صف العناوين، عمود المنشأ، ورقم الصف الأصلي.
- **المراجعة**: جاهز / يحتاج مراجعة / ناقص / مكرر، والتنبيهات منفصلة عن النواقص.
- **تنظيف «بانتظار الاستكمال»**: حذف فردي، تحديد متعدد، وحذف الكل بمعاينة وتأكيد ثانٍ (استبعاد منطقي فقط).
- **الأزرار فوق شريط أندرويد** (أزرار ثلاثة وإيماءات)، ومع لوحة المفاتيح.
- **أمان التزامن**: لا يمكن أن يُنشأ سجل ويُستبعد في نفس الوقت؛ إعادة المحاولة لا تكرر البطاقات.

## قاعدة البيانات

ترحيل واحد إضافي فقط يُطبق تلقائيًا عند تشغيل السيرفر: `20261102132629_QuickEntryUnverifiedGrades` (8 أعمدة اختيارية
أو بقيمة افتراضية؛ لا حذف ولا إعادة تسمية). سيرفر 0.6.0 يعمل على القاعدة بعد الترحيل (اختُبر)، فالرجوع لا يحتاج استعادة.

## النشر على سيرفر التجربة (على جهاز السيرفر)

```bash
cd ~/qadisiyah/deploy/trial
git status --short            # يجب ألا يظهر شيء (أو init-env.sh فقط)
docker compose ps             # postgres و api يعملان
bash update-trial.sh          # نسخة احتياطية إلزامية ← تحديث ← إعادة بناء api فقط ← فحص
curl -s http://192.168.1.12:5080/api/v1/version   # المتوقع: "version":"0.7.0" و schema QuickEntryUnverifiedGrades
```

- `update-trial.sh` يتوقف دون أي تغيير إذا فشلت النسخة الاحتياطية أو وُجدت تعديلات محلية.
- التوقف المتوقع: دقيقة إلى 3 دقائق (إعادة بناء خدمة api).
- الرجوع: `git checkout 5bdc099 && docker compose up -d --build api` (البيانات تبقى). الاستعادة من النسخة الاحتياطية
  (`restore-trial.sh`) فقط عند الحاجة الفعلية.
- اختبار CI «Trial server update test (5bdc099 -> this commit, data kept)» يكرر نفس الخطوات على نسخة مؤقتة.

## تنظيف «بانتظار الاستكمال» (بعد النشر)

من التطبيق 0.7.0 بحساب المدير العام: «بانتظار الاستكمال» ← أيقونة «استبعاد كل المؤهل» ← راجع المعاينة (المؤهل، المحمي
وأسبابه، العدد بعده) ← «متابعة» ← التأكيد النهائي. أو من جهاز السيرفر عبر الواجهة البرمجية:

```bash
URL=http://192.168.1.12:5080
read -rsp 'كلمة مرور admin: ' PW; echo
TOKEN=$(curl -s -X POST $URL/api/v1/auth/login -H 'content-type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$PW\",\"deviceId\":\"$(cat /proc/sys/kernel/random/uuid)\",\"deviceName\":\"cleanup\"}" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["accessToken"])')
H="authorization: Bearer $TOKEN"
# 1) تصدير القائمة قبل التنظيف (فيها بيانات موردين: احفظها في مكان آمن)
curl -s -H "$H" "$URL/api/v1/quick-entry/pending/export" -o pending-before-cleanup.xlsx
# 2) المعاينة (لا تكتب شيئًا)
curl -s -X POST -H "$H" -H 'content-type: application/json' $URL/api/v1/quick-entry/pending/discard-all \
  -d '{"preview":true}' | tee preview.json
# 3) التنفيذ بنفس رمز المعاينة فقط
T=$(python3 -c 'import json;print(json.load(open("preview.json"))["token"])')
curl -s -X POST -H "$H" -H 'content-type: application/json' $URL/api/v1/quick-entry/pending/discard-all \
  -d "{\"preview\":false,\"token\":\"$T\"}"
```

- `quick.snapshot_changed` يعني أن القائمة تغيرت بعد المعاينة ولم يُستبعد شيء: أعد المعاينة ثم التنفيذ.
- الصفوف المحمية (مرتبطة ببطاقة، أو جارٍ إنشاؤها، أو توجد بطاقة بمعرفها) تبقى كما هي مع سببها في المعاينة.
- الاستبعاد منطقي: الصفوف تبقى في `import_entries` بحالة `discarded`، ولا تُلمس البطاقات أو الكتالوج أو المرفقات،
  وسجل التدقيق يُضاف إليه فقط (`quick.discard_all`).

## الهاتف

- APK من GitHub Actions (artifact `qadisiyah-debug-apk`)، بنفس معرف التطبيق `com.alqadisiyah.qadisiyah` ونفس مفتاح
  التوقيع الثابت (`trial-debug.keystore`)، فيُثبّت فوق 0.6.0 دون حذف البيانات. اختبار CI «Android in-place update test»
  يثبت 0.6.0 (1033) ثم الجديد فوقه ويتحقق من بقاء البيانات.
- عنوان السيرفر وتسجيل الدخول لا يتغيران.
