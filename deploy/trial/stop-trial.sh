#!/usr/bin/env bash
# إيقاف السيرفر التجريبي مع الاحتفاظ بكل البيانات.
set -euo pipefail
cd "$(dirname "$0")"
docker compose stop
echo "تم الإيقاف. البيانات محفوظة؛ للتشغيل: docker compose up -d"
