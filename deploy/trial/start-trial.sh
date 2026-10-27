#!/usr/bin/env bash
# سيرفر القادسية التجريبي — Linux/macOS. الاستخدام: ./start-trial.sh [عنوان-IP]
set -euo pipefail
cd "$(dirname "$0")"

command -v docker >/dev/null || { echo "Docker غير مثبت" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker لا يعمل" >&2; exit 1; }

ip="${1:-}"
if [[ -z "$ip" ]]; then
  ip="$( (hostname -I 2>/dev/null || true) | awk '{print $1}')"
  [[ -z "$ip" ]] && ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
[[ -z "$ip" ]] && { echo "تعذر معرفة عنوان الجهاز؛ شغّل: ./start-trial.sh <IP>" >&2; exit 1; }

if [[ -f .env ]]; then
  # الأسرار تبقى كما هي؛ يُحدّث عنوان الجهاز فقط.
  sed -i.bak "s/^BIND_ADDRESS=.*/BIND_ADDRESS=${ip}/" .env && rm -f .env.bak
else
  ./init-env.sh "$ip" > /dev/null
fi

docker compose up -d --build
url="http://${ip}:5080"
for _ in $(seq 1 90); do
  curl -sf "$url/health/db" >/dev/null && break
  sleep 2
done
curl -sf "$url/health/db" >/dev/null || { docker compose logs --tail 50 api; exit 1; }

admin_password="$(sed -n 's/^BOOTSTRAP_ADMIN_PASSWORD=//p' .env)"
cat <<INFO

================ سيرفر القادسية التجريبي يعمل ================
  عنوان السيرفر (يُكتب في التطبيق):  $url
  اسم المستخدم:                       admin
  كلمة المرور المؤقتة (أول دخول):    $admin_password
  للإيقاف:  docker compose down
===============================================================
INFO
