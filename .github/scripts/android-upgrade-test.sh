#!/usr/bin/env bash
# اختبار تحديث APK فوق النسخة السابقة على محاكي Android دون حذف التطبيق أو بياناته.
# الاستخدام: bash .github/scripts/android-upgrade-test.sh <APK-السابق> <APK-الجديد>
set -euo pipefail

prev="${1:?APK السابق}"
new="${2:?APK الجديد}"
pkg=com.alqadisiyah.qadisiyah
bt="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"

fail() { echo "فشل: $*" >&2; exit 1; }
cert() { "$bt/apksigner" verify --print-certs "$1" | sed -n 's/.*SHA-256 digest: //p' | head -1; }
vcode() { "$bt/aapt2" dump badging "$1" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p"; }
appid() { "$bt/aapt2" dump badging "$1" | sed -n "s/^package: name='\([^']*\)'.*/\1/p"; }
installed() { adb shell dumpsys package "$pkg" | sed -n "s/.*$1=\([^ ]*\).*/\1/p" | head -1; }

echo "== فحص الملفين قبل التثبيت =="
[[ "$(appid "$prev")" == "$pkg" && "$(appid "$new")" == "$pkg" ]] || fail "Application ID مختلف"
[[ "$(cert "$prev")" == "$(cert "$new")" ]] || fail "التوقيع مختلف؛ لن يقبل Android التحديث فوق النسخة السابقة"
(( $(vcode "$new") > $(vcode "$prev") )) || fail "Version Code الجديد ليس أكبر من السابق"
echo "التوقيع: $(cert "$new")"
echo "Version Code: $(vcode "$prev") -> $(vcode "$new")"

echo "== تثبيت النسخة السابقة وتشغيلها وكتابة بيانات =="
adb install "$prev"
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 15
adb shell "run-as $pkg sh -c 'mkdir -p files && echo kept > files/upgrade-marker'"
first_install="$(installed firstInstallTime)"
adb shell am force-stop "$pkg"

echo "== تثبيت النسخة الجديدة فوقها (بدون حذف) =="
adb install -r "$new"

[[ "$(adb shell "run-as $pkg cat files/upgrade-marker" | tr -d '\r')" == kept ]] || fail "بيانات التطبيق حُذفت"
[[ "$(installed firstInstallTime)" == "$first_install" ]] || fail "التطبيق أعيد تثبيته من الصفر"
[[ "$(installed versionCode)" == "$(vcode "$new")" ]] || fail "النسخة المثبتة ليست الجديدة"

adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 15
[[ -n "$(adb shell pidof "$pkg" | tr -d '\r')" ]] || fail "التطبيق لا يعمل بعد التحديث"
echo "نجح: تم التحديث فوق النسخة السابقة مع بقاء البيانات (firstInstallTime=$first_install)."
