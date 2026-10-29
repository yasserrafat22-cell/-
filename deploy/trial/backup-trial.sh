#!/usr/bin/env bash
# نسخة احتياطية كاملة لقاعدة بيانات التجربة والمرفقات وملف .env في مجلد backups/.
# الاستخدام: bash backup-trial.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

[[ -f .env ]] || die "لا يوجد .env؛ هذا المجلد ليس مجلد السيرفر العامل."
postgres_running || die "قاعدة البيانات لا تعمل. شغّلها أولًا: docker compose up -d postgres"

mkdir -p backups && chmod 700 backups
stamp="$(date +%Y%m%d-%H%M%S)"
dump="backups/qadisiyah-${stamp}.dump"

docker compose exec -T postgres pg_dump -U qadisiyah -d qadisiyah --format=custom > "$dump"
[[ -s "$dump" ]] || { rm -f "$dump"; die "النسخة الاحتياطية فارغة"; }
# تحقق أن الملف قابل للقراءة كنسخة PostgreSQL صالحة.
docker compose exec -T postgres pg_restore --list < "$dump" > /dev/null \
  || { rm -f "$dump"; die "النسخة الاحتياطية تالفة"; }

cp .env "backups/env-${stamp}"
chmod 600 "$dump" "backups/env-${stamp}"

attachments="backups/attachments-${stamp}.tar"
if attachments_volume_exists; then
  attachments_tar -C /data/attachments -cf - . > "$attachments"
  tar -tf "$attachments" > /dev/null || { rm -f "$attachments"; die "نسخة المرفقات تالفة"; }
  chmod 600 "$attachments"
else
  attachments=""
fi

echo "تم حفظ النسخة الاحتياطية:"
echo "  قاعدة البيانات: $(pwd)/$dump ($(du -h "$dump" | cut -f1))"
echo "  الإعدادات:      $(pwd)/backups/env-${stamp}"
if [[ -n "$attachments" ]]; then
  echo "  المرفقات:       $(pwd)/$attachments ($(du -h "$attachments" | cut -f1))"
else
  echo "  المرفقات:       لا توجد بعد (تبدأ مع أول تشغيل لإصدار يدعمها)"
fi
