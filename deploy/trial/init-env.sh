#!/usr/bin/env bash
# ينشئ ملف .env بأسرار عشوائية قوية لسيرفر التجربة. لا يُرفع .env للمستودع.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  echo ".env موجود بالفعل؛ لن يُستبدل." >&2
  exit 1
fi

bind_address="${1:?الاستخدام: ./init-env.sh <عنوان-IP-للجهاز-على-الشبكة>}"
rand() { openssl rand -base64 "$1" | tr -d '/+=\n' | cut -c1-"$2"; }

admin_password="$(rand 18 14)7a"
umask 077
cat > .env <<ENV
BIND_ADDRESS=${bind_address}
POSTGRES_PASSWORD=$(rand 32 32)
JWT_SIGNING_KEY=$(rand 64 64)
BOOTSTRAP_ADMIN_PASSWORD=${admin_password}
ENV

echo "تم إنشاء .env"
echo "كلمة مرور المدير المؤقتة (تُطلب مرة واحدة ويُجبر تغييرها عند أول دخول):"
echo "  ${admin_password}"
