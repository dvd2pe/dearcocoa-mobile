#!/usr/bin/env bash
# Tour demo DearCocoa su emulatore: install APK + tap guidati + screencap.
# Chiamato dalla workflow shots.yml (dvd2pe/actions-probe) dopo il boot.
#
# Perche' un FILE: android-emulator-runner esegue lo script inline riga per
# riga in shell separate (variabili e blocchi multi-riga non sopravvivono).
# Un file bash eseguito in un colpo solo non ha questi problemi.
set -uo pipefail

APP_DIR="${GITHUB_WORKSPACE:-$PWD}/app"
OUT="$APP_DIR/build/app/outputs/apk/global/release"
APK="$OUT/app-global-x86_64-release.apk"
if [ ! -f "$APK" ]; then
  APK=$(find "$APP_DIR/build/app/outputs" -name "*x86_64*.apk" -not -path "*intermediates*" | head -1)
fi
echo "APK: $APK"
if [ ! -f "$APK" ]; then
  echo "APK x86_64 non trovato" >&2
  exit 1
fi

adb install -r "$APK"

PKG=app.dearcocoa.mobile
for P in android.permission.CAMERA android.permission.RECORD_AUDIO \
         android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS android.permission.READ_MEDIA_IMAGES \
         android.permission.ACTIVITY_RECOGNITION; do
  adb shell pm grant $PKG $P 2>/dev/null || true
done
adb shell input keyevent 82 || true
adb shell input keyevent 4 || true
sleep 3

W=$(adb shell wm size | grep -oE '[0-9]+' | head -1)
H=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+' | tail -1)
echo "screen: ${W}x${H}"
BAR_Y=$((H - H * 8 / 100))
mkdir -p /tmp/shots
shot() { adb exec-out screencap -p > "/tmp/shots/$1.png"; }

# 01-02 avvio + timeline
adb shell am start -n $PKG/.MainActivity || true
sleep 25
shot 01_timeline_avvio
sleep 5
shot 02_timeline

# 03 menu radiale (pulsante AI centrale)
adb shell input tap $((W / 2)) $BAR_Y || true
sleep 3
shot 03_menu_radiale
adb shell input keyevent 4 || true
sleep 2

# 04-06 tab Community (gate demo login) e ritorno timeline
adb shell input tap $((W * 32 / 100)) $BAR_Y || true
sleep 6
shot 04_community
adb shell input tap $((W / 2)) $((H * 28 / 100)) || true
sleep 8
shot 05_dopo_login_demo
adb shell input tap $((W * 8 / 100)) $BAR_Y || true
sleep 5
shot 06_timeline_loggato

# 07 tab Events
adb shell input tap $((W * 68 / 100)) $BAR_Y || true
sleep 6
shot 07_events

# 08 tab Library
adb shell input tap $((W * 92 / 100)) $BAR_Y || true
sleep 6
shot 08_library

# 09-10 esplorazione header timeline
adb shell input tap $((W * 8 / 100)) $BAR_Y || true
sleep 4
adb shell input tap $((W - W * 22 / 100)) $((H * 17 / 100)) || true
sleep 4
shot 09_header_tap_1
adb shell input tap $((W - W * 10 / 100)) $((H * 17 / 100)) || true
sleep 4
shot 10_header_tap_2
adb shell input keyevent 4 || true
sleep 2

# 11 community come ultimo stato
adb shell input tap $((W * 32 / 100)) $BAR_Y || true
sleep 4
shot 11_ultimo_tab

echo "== shots generati =="
ls -lh /tmp/shots
