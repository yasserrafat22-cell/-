#!/usr/bin/env bash
# نسخة احتياطية مجدولة: backup-trial.sh ثم نسخة مشفرة بالمفتاح العام للمدير إلى كل
# وجهة في ملف backup-targets (مثل مجلد على Windows وفلاشة USB). المفتاح الخاص لفك
# التشفير يبقى مع المدير فقط ولا يوجد على السيرفر. الوجهة غير المتاحة (فلاشة غير
# موصولة) تُتجاوز مع تسجيل تحذير، وتُحفظ آخر KEEP نسخة في كل وجهة.
# الإعداد مرة واحدة:
#   backup-public.asc : المفتاح العام (gpg --export --armor ...)
#   backup-targets    : سطر لكل وجهة، مثل /mnt/c/QadisiyahBackups و /mnt/e/QadisiyahBackups
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

key="${BACKUP_PUBLIC_KEY:-backup-public.asc}"
targets_file="${BACKUP_TARGETS:-backup-targets}"
keep="${KEEP:-14}"
log="backups/auto-backup.log"
mkdir -p backups && chmod 700 backups
note() { echo "$(date '+%F %T') $*" | tee -a "$log"; }
# كل فشل يُسجل في الملف أيضًا (المهمة المجدولة تعمل دون نافذة).
die() { note "خطأ: $*" >&2; exit 1; }
trap 'note "خطأ: توقف السكربت عند السطر $LINENO"' ERR

[[ -s "$key" ]] || die "لا يوجد المفتاح العام $key (لا تُنسخ البيانات خارج الجهاز دون تشفير)."
[[ -s "$targets_file" ]] || die "لا يوجد ملف الوجهات $targets_file."

bash ./backup-trial.sh > /dev/null
dump="$(ls -t backups/qadisiyah-*.dump | grep -v -- '-app.dump' | head -1)"
stamp="$(basename "$dump" .dump | sed 's/^qadisiyah-//')"
files=("$(basename "$dump")" "env-$stamp")
[[ -f "backups/attachments-$stamp.tar" ]] && files+=("attachments-$stamp.tar")

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
out="$work/qadisiyah-$stamp.tar.gpg"
tar -C backups -cf - "${files[@]}" \
  | gpg --batch --yes --quiet --trust-model always --recipient-file "$key" --encrypt -o "$out"
[[ -s "$out" ]] || die "فشل تشفير النسخة"

ok=0
while IFS= read -r target || [[ -n "$target" ]]; do
  target="${target%$'\r'}"
  [[ -z "$target" || "$target" == \#* ]] && continue
  if [[ -d "$target" && -w "$target" ]]; then
    cp "$out" "$target/" && ok=$((ok + 1))
    # الأقدم يُحذف بعد الاحتفاظ بآخر KEEP نسخة في هذه الوجهة فقط.
    ls -1t "$target"/qadisiyah-*.tar.gpg 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r old; do rm -f -- "$old"; done
    note "تم: $target/$(basename "$out")"
  else
    note "تحذير: الوجهة غير متاحة (فلاشة غير موصولة؟): $target"
  fi
done < "$targets_file"

[[ $ok -gt 0 ]] || die "لم تُحفظ النسخة في أي وجهة. راجع $log"
note "انتهت النسخة المجدولة ($ok وجهة)."
