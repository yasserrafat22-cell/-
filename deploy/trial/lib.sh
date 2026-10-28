# دوال مشتركة لسكربتات السيرفر التجريبي. تُستدعى بـ: source lib.sh
# قاعدة ثابتة: لا يوجد في أي سكربت `docker compose down -v` ولا حذف لـ .env.

die() { echo "خطأ: $*" >&2; exit 1; }

env_get() {
  [[ -f .env ]] || die "ملف .env غير موجود في $(pwd)"
  sed -n "s/^$1=//p" .env | tr -d '\r' | head -n1
}

server_url() { echo "http://$(env_get BIND_ADDRESS):5080"; }

wait_healthy() {
  local url="$1"
  for _ in $(seq 1 90); do
    curl -sf "$url/health/db" >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

postgres_running() {
  [[ -n "$(docker compose ps --status running -q postgres 2>/dev/null)" ]]
}
