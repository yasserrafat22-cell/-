#!/usr/bin/env bash
# استعادة قاعدة بيانات التجربة ومرفقاتها من نسخة احتياطية (تستبدل البيانات الحالية).
# الاستخدام: bash restore-trial.sh backups/qadisiyah-YYYYMMDD-HHMMSS.dump
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

dump="${1:-}"
[[ -n "$dump" && -s "$dump" ]] || die "حدد ملف نسخة احتياطية موجودًا. المتاح: $(ls backups/*.dump 2>/dev/null | tr '\n' ' ')"
postgres_running || docker compose up -d postgres

docker compose exec -T postgres pg_restore --list < "$dump" > /dev/null || die "الملف ليس نسخة احتياطية صالحة"
# ملف المرفقات المأخوذ مع نفس النسخة (نفس التاريخ والوقت) إن وُجد.
attachments="$(dirname "$dump")/attachments-$(basename "$dump" .dump | sed 's/^qadisiyah-//').tar"
[[ -f "$attachments" ]] && { tar -tf "$attachments" > /dev/null || die "ملف المرفقات تالف: $attachments"; }

echo "ستُستبدل بيانات قاعدة التجربة الحالية بمحتوى: $dump"
echo "سيتم أولًا أخذ نسخة احتياطية من الوضع الحالي."
read -r -p "للمتابعة اكتب RESTORE: " answer
[[ "$answer" == "RESTORE" ]] || die "أُلغيت الاستعادة."

bash ./backup-trial.sh
docker compose stop api
docker compose exec -T postgres pg_restore -U qadisiyah -d qadisiyah --clean --if-exists --no-owner < "$dump"
if [[ -f "$attachments" ]]; then
  attachments_tar -C /data/attachments -xf - < "$attachments"
  echo "استُعيدت المرفقات من: $attachments"
fi
docker compose up -d api
wait_healthy "$(server_url)" || die "السيرفر لم يعمل بعد الاستعادة؛ راجع: docker compose logs api"
echo "تمت الاستعادة والسيرفر يعمل: $(server_url)"
