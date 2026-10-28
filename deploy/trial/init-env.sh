#!/usr/bin/env bash
# ينشئ ملف .env بأسرار عشوائية قوية لسيرفر التجربة — مرة واحدة فقط عند أول إعداد.
# لا يُرفع .env للمستودع، ولا يستبدل هذا السكربت ملف .env موجودًا أبدًا:
# كلمة مرور قاعدة البيانات فيه مرتبطة بالبيانات المحفوظة.
#
# الاستخدام: bash init-env.sh <عنوان-IP-للجهاز-على-الشبكة>
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  echo ".env موجود بالفعل؛ لن يُستبدل (الإعدادات الحالية محفوظة)." >&2
  exit 1
fi

bind_address="${1:-}"
if [[ -z "$bind_address" ]]; then
  echo "الاستخدام: bash init-env.sh <عنوان-IP-للجهاز-على-الشبكة>" >&2
  exit 1
fi

# أسرار من /dev/urandom دون الاعتماد على openssl؛ حروف وأرقام فقط حتى لا
# تحتاج أي تهريب داخل .env أو سلسلة الاتصال بقاعدة البيانات.
rand() {
  local out=""
  while [[ ${#out} -lt $1 ]]; do
    out+="$(head -c 256 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${out:0:$1}"
}

admin_password="$(rand 14)7a"
umask 077
cat > .env <<ENV
BIND_ADDRESS=${bind_address}
POSTGRES_PASSWORD=$(rand 32)
JWT_SIGNING_KEY=$(rand 64)
BOOTSTRAP_ADMIN_PASSWORD=${admin_password}
ENV

echo "تم إنشاء .env"
echo "كلمة مرور المدير المؤقتة (تُستخدم مرة واحدة ويُجبر تغييرها عند أول دخول):"
echo "  ${admin_password}"
