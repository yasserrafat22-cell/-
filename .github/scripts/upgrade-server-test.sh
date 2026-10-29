#!/usr/bin/env bash
# اختبار ترقية حقيقي للسيرفر التجريبي: يشغّل الإصدار السابق كما على جهاز التجربة،
# يغيّر كلمة مرور المدير ويضيف بيانات، ثم يحدّث بـ update-trial.sh ويتحقق
# أن قاعدة البيانات والحسابات وكلمات المرور و.env والعنوان بقيت كما هي.
#
# الاستخدام (من جذر المستودع على الإصدار الجديد، بتاريخ git كامل):
#   bash .github/scripts/upgrade-server-test.sh <commit-الإصدار-السابق>
# يعمل في CI فقط: ينشئ نسخة مستقلة من المستودع في مجلد مؤقت.
set -euo pipefail

base="${1:?commit الإصدار السابق مطلوب}"
repo="$(git rev-parse --show-toplevel)"
new="$(git -C "$repo" rev-parse HEAD)"
work="$(mktemp -d)"
laptop="$work/laptop"
trial="$laptop/deploy/trial"
url="http://127.0.0.1:5080"
new_password='Upgrade-Test-Pass-2026'
device="$(cat /proc/sys/kernel/random/uuid)"

step() { echo; echo "=== $* ==="; }
fail() { echo "فشل: $*" >&2; exit 1; }
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
post() { curl -sS -o "$work/body" -w '%{http_code}' -X POST "$url$1" -H 'content-type: application/json' ${3:+-H "authorization: Bearer $3"} -d "$2"; }
# بعد إعادة تشغيل السيرفر قد يفشل أول طلب أثناء الإقلاع؛ يُعاد حتى 5 مرات.
fetch_sha() {
  for _ in 1 2 3 4 5; do
    curl -sf "$1" -H "authorization: Bearer $2" -o "$work/fetched" && { sha256sum < "$work/fetched" | cut -d' ' -f1; return; }
    sleep 2
  done
  echo "fetch-failed"
}
login() { post /api/v1/auth/login "{\"username\":\"admin\",\"password\":\"$1\",\"deviceId\":\"$device\",\"deviceName\":\"upgrade-test\"}"; }

step "نسخة تحاكي جهاز التجربة على الإصدار السابق ${base:0:7}"
git -C "$repo" branch -f upgrade-test "$new"
git clone -q --no-local "$repo" "$laptop"
git -C "$laptop" checkout -q -b upgrade-test "$base"
git -C "$laptop" branch -q --set-upstream-to=origin/upgrade-test
cd "$trial"
./start-trial.sh 127.0.0.1
bootstrap="$(sed -n 's/^BOOTSTRAP_ADMIN_PASSWORD=//p' .env)"

step "تعديل محلي على init-env.sh كما حدث على جهاز التجربة"
echo "# local fix on the trial laptop" >> init-env.sh

step "أول دخول وتغيير كلمة مرور المدير على الإصدار السابق"
[[ "$(login "$bootstrap")" == 200 ]] || fail "دخول المدير الأول"
token="$(json "d['accessToken']" < "$work/body")"
[[ "$(post /api/v1/auth/change-password "{\"currentPassword\":\"$bootstrap\",\"newPassword\":\"$new_password\"}" "$token")" == 200 ]] \
  || { cat "$work/body"; fail "تغيير كلمة المرور"; }
[[ "$(login "$new_password")" == 200 ]] || fail "الدخول بكلمة المرور الجديدة"
refresh="$(json "d['refreshToken']" < "$work/body")"

env_before="$(sha256sum .env)"
volume_before="$(docker volume inspect -f '{{.CreatedAt}}' qadisiyah-trial_pgdata)"
user_before="$(docker compose exec -T postgres psql -U qadisiyah -d qadisiyah -tAc \
  "select id || '|' || password_hash || '|' || must_change_password || '|' || security_stamp from users where username = 'admin'")"
[[ -n "$user_before" ]] || fail "لم يُعثر على حساب المدير في قاعدة البيانات"

step "التحديث الأول بنفس الخطوات المكتوبة في docs/06-update-guide.md"
# الإصدار السابق لا يحتوي update-trial.sh؛ لذا أول تحديث يدوي بخطوات قليلة.
mkdir -p backups && chmod 700 backups
docker compose exec -T postgres pg_dump -U qadisiyah -d qadisiyah --format=custom > backups/before-phase3.dump
cp .env backups/env-before-phase3
cp init-env.sh backups/init-env.sh.local
git checkout -- init-env.sh
git pull --ff-only origin upgrade-test
bash update-trial.sh

step "التحقق من الحفاظ على البيانات"
[[ "$(git -C "$laptop" rev-parse HEAD)" == "$new" ]] || fail "لم يتحدث الكود للإصدار الجديد"
[[ "$(sha256sum .env)" == "$env_before" ]] || fail ".env تغيّر"
[[ "$(docker volume inspect -f '{{.CreatedAt}}' qadisiyah-trial_pgdata)" == "$volume_before" ]] || fail "volume قاعدة البيانات أعيد إنشاؤه"
ls backups/qadisiyah-*.dump > /dev/null || fail "لا توجد نسخة احتياطية"
grep -q "local fix on the trial laptop" backups/init-env.sh.local || fail "النسخة المحلية من init-env.sh لم تُحفظ"
docker compose exec -T postgres pg_restore --list < backups/before-phase3.dump > /dev/null || fail "النسخة الاحتياطية اليدوية غير صالحة"
user_after="$(docker compose exec -T postgres psql -U qadisiyah -d qadisiyah -tAc \
  "select id || '|' || password_hash || '|' || must_change_password || '|' || security_stamp from users where username = 'admin'")"
[[ "$user_after" == "$user_before" ]] || fail "حساب المدير تغيّر أثناء التحديث"
[[ "$(docker compose exec -T postgres psql -U qadisiyah -d qadisiyah -tAc "select count(*) from users")" == 1 ]] \
  || fail "عدد المستخدمين تغيّر"

[[ "$(post /api/v1/auth/refresh "{\"refreshToken\":\"$refresh\",\"deviceId\":\"$device\"}")" == 200 ]] \
  || fail "جلسة الهاتف (refresh token) لم تعد صالحة بعد التحديث"
[[ "$(login "$bootstrap")" == 401 ]] || fail "كلمة المرور المؤقتة القديمة ما زالت تعمل"
[[ "$(login "$new_password")" == 200 ]] || fail "كلمة المرور المعدلة لم تعد تعمل"
[[ "$(json "d['user']['mustChangePassword']" < "$work/body")" == False ]] || fail "عاد إجبار تغيير كلمة المرور"
token="$(json "d['accessToken']" < "$work/body")"

expected_version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$repo/server/Directory.Build.props")"
curl -sf "$url/api/v1/version" | json "d['version']" | grep -qx "$expected_version" || fail "إصدار السيرفر غير متوقع"

step "واجهات المرحلة الثالثة تعمل على البيانات المحفوظة"
curl -sf "$url/api/v1/reference" -H "authorization: Bearer $token" > "$work/ref"
activity="$(json "d['activityTypes'][0]['id']" < "$work/ref")"
party="$(cat /proc/sys/kernel/random/uuid)"
[[ "$(post /api/v1/parties "{\"id\":\"$party\",\"name\":\"عميل اختبار الترقية\",\"isCustomer\":true,\"isSupplier\":false,\"phones\":[{\"number\":\"01001234567\"}],\"customerActivityId\":\"$activity\"}" "$token")" =~ ^20[01]$ ]] \
  || { cat "$work/body"; fail "تسجيل عميل"; }

step "تحديث لاحق بالسكربت مباشرة (مع تعديل محلي على init-env.sh) لا يمس الحساب أو البيانات"
echo "# another local edit" >> init-env.sh
bash ./update-trial.sh
grep -q "another local edit" backups/init-env.sh.local-* || fail "update-trial.sh لم يحفظ init-env.sh المحلي"
git diff --quiet -- init-env.sh || fail "init-env.sh لم يرجع للنسخة المصححة"
[[ "$(login "$new_password")" == 200 ]] || fail "كلمة المرور بعد التحديث الثاني"
token="$(json "d['accessToken']" < "$work/body")"
curl -sf "$url/api/v1/parties/$party" -H "authorization: Bearer $token" | json "d['name']" | grep -qx 'عميل اختبار الترقية' \
  || fail "العميل المسجل اختفى بعد التحديث الثاني"
[[ "$(sha256sum .env)" == "$env_before" ]] || fail ".env تغيّر في التحديث الثاني"

step "المرفقات تُحفظ في volume دائم وتدخل في النسخ الاحتياطي والاستعادة"
printf '\x89PNG\r\n\x1a\nupgrade-test-image' > "$work/logo.png"
attachment="$(cat /proc/sys/kernel/random/uuid)"
code="$(curl -sS -o "$work/body" -w '%{http_code}' -X POST "$url/api/v1/parties/$party/attachments" \
  -H "authorization: Bearer $token" -F "id=$attachment" -F "kind=logo" -F "file=@$work/logo.png;filename=logo.png")"
[[ "$code" == 201 ]] || { cat "$work/body"; fail "رفع ملف"; }
original_sha="$(sha256sum < "$work/logo.png" | cut -d' ' -f1)"
docker volume inspect qadisiyah-trial_attachments > /dev/null || fail "volume المرفقات غير موجود"

bash ./backup-trial.sh
dump="$(ls -t backups/qadisiyah-*.dump | head -1)"
tar_file="backups/attachments-$(basename "$dump" .dump | sed 's/^qadisiyah-//').tar"
tar -tf "$tar_file" | grep -q "${attachment//-/}" || fail "الملف غير موجود في نسخة المرفقات"

# فقد بيانات بعد النسخة: سجل جديد، وحذف ملفات المرفقات.
late="$(cat /proc/sys/kernel/random/uuid)"
[[ "$(post /api/v1/parties "{\"id\":\"$late\",\"name\":\"سجل بعد النسخة\",\"isCustomer\":true,\"isSupplier\":false,\"phones\":[{\"number\":\"01009998887\"}]}" "$token")" == 201 ]] \
  || fail "تسجيل بعد النسخة"
docker compose exec -T api sh -c 'find /data/attachments -type f -delete'
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/attachments/$attachment/content" -H "authorization: Bearer $token")" == 404 ]] \
  || fail "حذف الملفات للمحاكاة لم ينجح"

echo RESTORE | bash ./restore-trial.sh "$dump"
[[ "$(login "$new_password")" == 200 ]] || fail "كلمة المرور بعد الاستعادة"
token="$(json "d['accessToken']" < "$work/body")"
restored_sha="$(fetch_sha "$url/api/v1/attachments/$attachment/content" "$token")"
[[ "$restored_sha" == "$original_sha" ]] || fail "الملف المستعاد لا يطابق الأصل"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/parties/$late" -H "authorization: Bearer $token")" == 404 ]] \
  || fail "قاعدة البيانات لم ترجع لنقطة النسخة"
curl -sf "$url/api/v1/parties/$party" -H "authorization: Bearer $token" | json "d['logoAttachmentId']" | grep -qx "$attachment" \
  || fail "الشعار لم يعد مرتبطًا بالعميل بعد الاستعادة"
[[ "$(sha256sum .env)" == "$env_before" ]] || fail ".env تغيّر أثناء النسخ أو الاستعادة"

step "زر «حفظ نسخة»: نسخة كاملة مشفرة بكلمة مرور، تُفك وتُستعاد بالسكربتات"
backup_password="Backup-Pass-$(date +%s)"
code="$(curl -sS -o "$work/app.qbk" -w '%{http_code}' -X POST "$url/api/v1/admin/backups" \
  -H "authorization: Bearer $token" -H 'content-type: application/json' -d "{\"password\":\"$backup_password\"}")"
[[ "$code" == 200 ]] || { cat "$work/app.qbk"; fail "إنشاء نسخة من التطبيق"; }
[[ "$(head -c 4 "$work/app.qbk")" == QBK1 ]] || fail "ملف النسخة ليس بالصيغة المشفرة"
! grep -q "عميل اختبار الترقية" "$work/app.qbk" || fail "النسخة غير مشفرة"
echo "wrong-password-123" | bash ./decrypt-backup.sh "$work/app.qbk" && fail "فُكت النسخة بكلمة مرور خاطئة"
echo "$backup_password" | bash ./decrypt-backup.sh "$work/app.qbk"
app_dump="$(ls -t backups/qadisiyah-*-app.dump | head -1)"
docker compose exec -T postgres pg_restore --list < "$app_dump" > /dev/null || fail "قاعدة البيانات في نسخة التطبيق غير صالحة"

after_app="$(cat /proc/sys/kernel/random/uuid)"
[[ "$(post /api/v1/parties "{\"id\":\"$after_app\",\"name\":\"سجل بعد نسخة التطبيق\",\"isCustomer\":true,\"isSupplier\":false,\"phones\":[{\"number\":\"01009998886\"}],\"confirmSimilar\":true}" "$token")" == 201 ]] \
  || fail "تسجيل بعد نسخة التطبيق"
echo RESTORE | bash ./restore-trial.sh "$app_dump"
[[ "$(login "$new_password")" == 200 ]] || fail "كلمة المرور بعد استعادة نسخة التطبيق"
token="$(json "d['accessToken']" < "$work/body")"
[[ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/parties/$after_app" -H "authorization: Bearer $token")" == 404 ]] \
  || fail "استعادة نسخة التطبيق لم ترجع البيانات لنقطة النسخة"
restored_sha="$(fetch_sha "$url/api/v1/attachments/$attachment/content" "$token")"
[[ "$restored_sha" == "$original_sha" ]] || fail "الملف في نسخة التطبيق لا يطابق الأصل"

step "النسخ المجدول: مشفر بالمفتاح العام إلى مجلد Windows، والفلاشة غير الموصولة تُتجاوز"
export GNUPGHOME="$work/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-gen-key "Qadisiyah Backup CI <backup@example.com>" rsa3072 encrypt never
gpg --batch --export --armor backup@example.com > backup-public.asc
mkdir -p "$work/windows-folder"
printf '%s\n' "$work/windows-folder" "$work/usb-not-plugged" > backup-targets
for _ in 1 2 3; do KEEP=2 bash ./auto-backup.sh; sleep 1; done
[[ "$(ls "$work/windows-folder"/qadisiyah-*.tar.gpg | wc -l)" == 2 ]] || fail "عدد النسخ المحفوظة لا يطابق KEEP"
grep -q "الوجهة غير متاحة" backups/auto-backup.log || fail "لم يُسجل تحذير الفلاشة غير الموصولة"
latest="$(ls -t "$work/windows-folder"/qadisiyah-*.tar.gpg | head -1)"
mkdir -p "$work/auto"; gpg --batch --quiet --decrypt "$latest" | tar -C "$work/auto" -xf -
docker compose exec -T postgres pg_restore --list < "$(ls "$work/auto"/qadisiyah-*.dump)" > /dev/null || fail "النسخة المجدولة غير صالحة"
ls "$work/auto"/env-* > /dev/null || fail "النسخة المجدولة بلا .env"
rm -f backup-public.asc backup-targets
printf 'x\n' > backup-targets
bash ./auto-backup.sh && fail "النسخ المجدول عمل دون مفتاح تشفير"
rm -f backup-targets
[[ "$(sha256sum .env)" == "$env_before" ]] || fail ".env تغيّر أثناء النسخ"

echo
echo "نجح اختبار الترقية: ${base:0:7} -> ${new:0:7} مع الحفاظ على البيانات والحسابات و.env."
echo "LAPTOP_DIR=$trial" >> "${GITHUB_ENV:-/dev/null}"
