#!/usr/bin/env bash
# Tour demo DearCocoa su emulatore: install APK firmato + sign-in demo + tap + screencap.
# Chiamato dalla workflow shots.yml (dvd2pe/actions-probe) dopo il boot.
#
# NOTE:
# - android-emulator-runner esegue lo script inline RIGA PER RIGA in shell
#   separate: per questo il tour e' un FILE bash (variabili/blocchi sopravvivono).
# - L'app parte su una WELCOME con 5 demo account: il tap su una riga entra.
# - Con rendering software (swiftshader) il launcher puo' andare in ANR e il
#   dialog "Pixel Launcher isn't responding" copre lo schermo e BLOCCA i tap:
#   hide_error_dialogs=1 lo sopprime (fix della run del 19/11, 1080x2400).
# - Il tap sull'account viene VERIFICATO confrontando l'hash dello screencap
#   prima/dopo: se lo schermo non cambia si riprova sulle righe successive.
set -uo pipefail

APP_DIR="${GITHUB_WORKSPACE:-$PWD}/app"
OUT="$APP_DIR/build/app/outputs/apk/global/release"
PKG=app.dearcocoa.mobile
mkdir -p /tmp/shots

# ---- 1) trova l'APK x86_64 release firmato ----
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

# ---- 2) installa e VERIFICA ----
if ! adb install -r "$APK"; then
  echo "INSTALL FALLITA (APK unsigned?)" >&2
  exit 1
fi
if ! adb shell pm list packages | grep -q "$PKG"; then
  echo "APP NON INSTALLATA dopo adb install" >&2
  exit 1
fi
echo "install OK: $PKG"

# ---- 3) tema chiaro + niente dialog ANR/crash che coprono lo schermo ----
adb shell cmd uimode night no || true
adb shell settings put global hide_error_dialogs 1 || true
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

# ---- 5) lancia l'app ----
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
  exit 1
fi
sleep 20  # boot interno app (rendering software lento a 1080x2400)

shot() { adb exec-out screencap -p > "/tmp/shots/$1.png"; }
scr_hash() { adb exec-out screencap -p 2>/dev/null | md5sum | cut -d' ' -f1; }

W=$(adb shell wm size | grep -oE '[0-9]+' | head -1)
H=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+' | tail -1)
DEN=$(adb shell wm density 2>/dev/null | grep -oE '[0-9]+' | head -1)
DEN=${DEN:-420}
DPR=$(( DEN / 160 ))
echo "screen: ${W}x${H} density: $DEN (dpr $DPR)"

BAR_Y=$(( H - H * 8 / 100 ))            # riga tab (5 zone)
AI_Y=$(( H - H * 14 / 100 ))            # centro bottone AI (elevato)

# ---- 01 welcome reale (5 demo account) ----
shot 01_benvenuto
sleep 2

# ---- 02 sign-in con verifica: tap riga demo account, controlla cambio schermo ----
SIGNIN_OK=0
for PCT in 22 30 38; do
  HB=$(scr_hash)
  adb shell input tap $(( W / 2 )) $(( H * PCT / 100 )) || true
  sleep 12
  HA=$(scr_hash)
  sleep 3
  HA2=$(scr_hash)
  echo "tap account $PCT%: hash $HB -> $HA / $HA2"
  if [ "$HA" != "$HB" ] && [ "$HA2" != "$HB" ]; then
    echo "SCHERMO CAMBIATO dopo tap a $PCT%: sign-in presumibilmente OK"
    SIGNIN_OK=1
    break
  fi
done
[ "$SIGNIN_OK" = "1" ] || echo "ATTENZIONE: nessun cambio schermo dopo i tap account (welcome ancora attiva?)" >&2

sleep 5
shot 02_dopo_signin

# torna alla timeline (chiude eventuali dettagli aperti dai tap extra)
adb shell input keyevent 4 || true
sleep 2
adb shell input tap $(( W * 10 / 100 )) "$BAR_Y" || true
sleep 6
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
