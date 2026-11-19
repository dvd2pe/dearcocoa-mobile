#!/usr/bin/env bash
# Tour demo DearCocoa su emulatore: install APK firmato + sign-in demo + tap + screencap.
# Chiamato dalla workflow shots.yml (dvd2pe/actions-probe) dopo il boot.
#
# NOTE:
# - android-emulator-runner esegue lo script inline RIGA PER RIGA in shell
#   separate: per questo il tour e' un FILE bash (variabili/blocchi sopravvivono).
# - L'app parte su una WELCOME con 5 demo account ("Pick an account to step
#   right in"): il tap sul primo account entra e mostra la Timeline.
# - uiautomator non espone i nodi Flutter: tutti i tap usano coordinate
#   geometriche derivate dal design reale (barra 393dp: Timeline 9.8%,
#   Community 27.4%, AI 50%, Events 72.6%, Library 91.7%).
set -uo pipefail

APP_DIR="${GITHUB_WORKSPACE:-$PWD}/app"
OUT="$APP_DIR/build/app/outputs/apk/global/release"
PKG=app.dearcocoa.mobile
mkdir -p /tmp/shots

# ---- 1) trova l'APK x86_64 release firmato (gradle prima, flutter-apk poi) ----
APK="$OUT/app-global-x86_64-release.apk"
if [ ! -f "$APK" ]; then
  APK=$(find "$APP_DIR/build/app/outputs/apk" -name "*x86_64*.apk" -not -path "*intermediates*" | head -1)
fi
if [ ! -f "$APK" ]; then
  APK=$(find "$APP_DIR/build/app/outputs/flutter-apk" -name "*x86_64*.apk" -not -path "*intermediates*" | head -1)
fi
echo "APK: $APK"
if [ ! -f "$APK" ]; then
  echo "APK x86_64 non trovato" >&2
  exit 1
fi

# ---- 2) installa e VERIFICA: unsigned/non-installata = errore bloccante ----
if ! adb install -r "$APK"; then
  echo "INSTALL FALLITA (APK unsigned?)" >&2
  exit 1
fi
if ! adb shell pm list packages | grep -q "$PKG"; then
  echo "APP NON INSTALLATA dopo adb install" >&2
  exit 1
fi
echo "install OK: $PKG"

# ---- 3) tema chiaro (il promo DearCocoa e' light) ----
adb shell cmd uimode night no || true
sleep 2

# ---- 4) permessi + wake + sblocco ----
for P in android.permission.CAMERA android.permission.RECORD_AUDIO \
         android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_IMAGES \
         android.permission.ACTIVITY_RECOGNITION; do
  adb shell pm grant $PKG $P 2>/dev/null || true
done
adb shell input keyevent 82 || true
adb shell input keyevent 4 || true
sleep 2

# ---- 5) lancia l'app (monkey risolve da solo la Activity giusta) ----
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true

FG=""
for i in $(seq 1 30); do
  sleep 2
  FG=$(adb shell dumpsys activity activities 2>/dev/null | grep -i "resumedactivity" | grep -i dearcocoa || true)
  if [ -n "$FG" ]; then
    echo "APP IN PRIMO PIANO (dopo ~$((i*2))s)"
    break
  fi
done
if [ -z "$FG" ]; then
  echo "FATALE: app non risulta in primo piano" >&2
  adb shell dumpsys activity activities 2>/dev/null | grep -i "resumedactivity" || true
  exit 1
fi
sleep 15  # boot interno app

shot() { adb exec-out screencap -p > "/tmp/shots/$1.png"; }

W=$(adb shell wm size | grep -oE '[0-9]+' | head -1)
H=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+' | tail -1)
DEN=$(adb shell wm density 2>/dev/null | grep -oE '[0-9]+' | head -1)
DEN=${DEN:-420}
DPR=$(( DEN / 160 ))
echo "screen: ${W}x${H} density: $DEN (dpr $DPR)"

BAR_Y=$(( H - H * 8 / 100 ))            # riga tab della barra (5 zone)
AI_Y=$(( H - H * 14 / 100 ))            # centro bottone AI (elevato sopra la barra)

# ---- 01 welcome reale (5 demo account) ----
shot 01_benvenuto
sleep 3

# ---- 02 sign-in col primo demo account (riga alta della lista) ----
adb shell input tap $(( W / 2 )) $(( H * 22 / 100 )) || true
sleep 12
shot 02_dopo_signin

# ---- 03 timeline ----
sleep 5
shot 03_timeline

# ---- 04 menu radiale (pulsante AI centrale) ----
adb shell input tap $(( W / 2 )) "$AI_Y" || true
sleep 3
shot 04_menu_radiale
adb shell input keyevent 4 || true
sleep 2

# ---- 05 tab Community ----
adb shell input tap $(( W * 27 / 100 )) "$BAR_Y" || true
sleep 6
shot 05_community

# ---- 06 tab Events ----
adb shell input tap $(( W * 73 / 100 )) "$BAR_Y" || true
sleep 6
shot 06_events

# ---- 07 tab Library ----
adb shell input tap $(( W * 92 / 100 )) "$BAR_Y" || true
sleep 6
shot 07_library

# ---- 08 timeline finale ----
adb shell input tap $(( W * 10 / 100 )) "$BAR_Y" || true
sleep 4
shot 08_timeline_finale

echo "== shots generati =="
ls -lh /tmp/shots
