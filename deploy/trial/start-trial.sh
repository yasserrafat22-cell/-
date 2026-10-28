#!/usr/bin/env bash
# سيرفر القادسية التجريبي — Linux/macOS. الاستخدام: ./start-trial.sh [عنوان-IP]
set -euo pipefail
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "Docker غير مثبت" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker لا يعمل" >&2; exit 1; }

source ./lib.sh

ip="${1:-}"
if [[ -f .env ]]; then
  # إعداد قائم: لا يُغيَّر أي شيء في .env إلا إذا طُلب عنوان جديد صراحةً.
  if [[ -n "$ip" ]]; then
    sed -i.bak "s/^BIND_ADDRESS=.*/BIND_ADDRESS=${ip}/" .env && rm -f .env.bak
  fi
else
  if [[ -z "$ip" ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
      die "داخل WSL حدد عنوان الكمبيوتر على الشبكة صراحةً: bash start-trial.sh 192.168.1.x (من ipconfig في Windows)"
    fi
    ip="$( (hostname -I 2>/dev/null || true) | awk '{print $1}')"
    [[ -z "$ip" ]] && ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  fi
  [[ -z "$ip" ]] && die "تعذر معرفة عنوان الجهاز؛ شغّل: bash start-trial.sh <IP>"
  bash ./init-env.sh "$ip" > /dev/null
fi

docker compose up -d --build
url="$(server_url)"
wait_healthy "$url" || { docker compose logs --tail 50 api; exit 1; }

admin_password="$(env_get BOOTSTRAP_ADMIN_PASSWORD)"
cat <<INFO

================ سيرفر القادسية التجريبي يعمل ================
  عنوان السيرفر (يُكتب في التطبيق):  $url
  اسم المستخدم:                       admin
  كلمة المرور المؤقتة (أول دخول فقط): $admin_password
  (بعد تغييرها في التطبيق لا تُستخدم هذه الكلمة مرة أخرى)
  للإيقاف مع الاحتفاظ بالبيانات:  bash stop-trial.sh
  للتحديث لاحقًا:                bash update-trial.sh
===============================================================
INFO
