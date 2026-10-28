#!/usr/bin/env bash
# تحديث السيرفر التجريبي القائم إلى آخر نسخة على GitHub دون فقد أي بيانات.
#
#  - يأخذ نسخة احتياطية إلزامية أولًا ويتوقف إذا فشلت.
#  - لا يلمس .env (كلمات المرور والمفاتيح) ولا قاعدة البيانات أو الـ volume.
#  - يعيد بناء السيرفر فقط؛ ترحيلات قاعدة البيانات تُطبق تلقائيًا عند تشغيله.
#
# الاستخدام: bash update-trial.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

[[ -f .env ]] || die "لا يوجد .env؛ هذا المجلد ليس مجلد السيرفر العامل."
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "المجلد ليس نسخة git. راجع قسم «التحديث بدون git» في docs/06-update-guide.md"
branch="$(git rev-parse --abbrev-ref HEAD)"
before="$(git rev-parse HEAD)"

# تعديلات محلية على ملفات المستودع تمنع التحديث الآمن؛ استثناء وحيد معروف:
# init-env.sh الذي عُدّل محليًا وأصلح المصدر الأصلي نفسه.
changed="$(git -C "$repo_root" status --porcelain --untracked-files=no)"
if [[ -n "$changed" ]]; then
  if [[ "$changed" == " M deploy/trial/init-env.sh" ]]; then
    mkdir -p backups && chmod 700 backups
    cp init-env.sh "backups/init-env.sh.local-$(date +%Y%m%d-%H%M%S)"
    git checkout -- init-env.sh
    echo "حُفظت نسختك المحلية من init-env.sh في backups/ واستُخدمت النسخة المصححة."
  else
    echo "$changed" >&2
    die "توجد تعديلات محلية على ملفات المشروع؛ لم يُنفذ أي تغيير. أرسلها للمراجعة قبل التحديث."
  fi
fi

echo "== 1/4 نسخة احتياطية =="
postgres_running || docker compose up -d postgres
bash ./backup-trial.sh
mkdir -p backups && echo "$before" > backups/last-version-before-update

if [[ "${SKIP_PULL:-0}" != "1" ]]; then
  echo "== 2/4 تنزيل التحديث من GitHub (فرع $branch) =="
  git fetch origin "$branch"
  git merge --ff-only "origin/$branch" \
    || die "تعذر التحديث التلقائي (تفرع محلي)؛ لم يُنفذ أي تغيير على السيرفر."
fi
after="$(git rev-parse HEAD)"

echo "== 3/4 إعادة بناء وتشغيل السيرفر (البيانات محفوظة) =="
docker compose build api
docker compose up -d

echo "== 4/4 التحقق =="
if ! wait_healthy "$(server_url)"; then
  docker compose logs --tail 80 api
  cat >&2 <<ROLLBACK
السيرفر لم يعمل بعد التحديث. البيانات لم تُحذف. للرجوع للإصدار السابق:
  git checkout $before
  docker compose up -d --build api
وإذا لزم إرجاع البيانات لما قبل التحديث: bash restore-trial.sh <آخر ملف في backups/>
ROLLBACK
  exit 1
fi

echo "تم التحديث بنجاح: ${before:0:7} -> ${after:0:7}"
curl -sf "$(server_url)/api/v1/version" && echo
echo "السيرفر يعمل على: $(server_url) — لا حاجة لإعادة تسجيل الدخول أو تغيير أي إعداد."
