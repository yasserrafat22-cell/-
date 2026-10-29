#!/usr/bin/env bash
# يفك نسخة «حفظ نسخة» من التطبيق (.qbk) بكلمة مرورها إلى مجلد backups/ بنفس صيغة
# backup-trial.sh. لا يغير أي بيانات؛ الاستعادة خطوة منفصلة بـ restore-trial.sh.
# الاستخدام: bash decrypt-backup.sh /mnt/c/Users/.../qadisiyah-YYYYMMDD-HHMMSS.qbk
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

file="${1:-}"
[[ -n "$file" && -f "$file" ]] || die "حدد ملف النسخة (.qbk)."
mkdir -p backups && chmod 700 backups
if [[ -t 0 ]]; then
  read -r -s -p "كلمة مرور النسخة: " password; echo
else
  read -r password
fi
[[ -n "$password" ]] || die "لم تُدخل كلمة المرور."

# كلمة المرور تصل للبرنامج عبر المدخل فقط (لا تظهر في قائمة العمليات ولا في السجلات).
printf '%s\n' "$password" | docker compose run --rm --no-deps -T \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$(realpath "$file"):/in/backup.qbk:ro" -v "$(pwd)/backups:/out" \
  --entrypoint dotnet api Qadisiyah.Api.dll decrypt-backup /in/backup.qbk /out \
  || die "تعذر فك النسخة (كلمة مرور خاطئة أو ملف تالف)."
chmod 600 backups/*-app.dump backups/*-app.tar 2>/dev/null || true
dump="$(ls -t backups/qadisiyah-*-app.dump | head -1)"
echo "للاستعادة (تستبدل البيانات الحالية بعد أخذ نسخة منها): bash restore-trial.sh $dump"
