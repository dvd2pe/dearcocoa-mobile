#!/usr/bin/env bash
# Tour demo DearCocoa su emulatore: install APK firmato + tap guidati + screencap.
# Chiamato dalla workflow shots.yml (dvd2pe/actions-probe) dopo il boot.
#
# Perche' un FILE: android-emulator-runner esegue lo script inline riga per
# riga in shell separate (variabili e blocchi multi-riga non sopravvivono).
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

# ---- 3) tema chiaro (l'emulatore parte in dark; il promo DearCocoa e' light) ----
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
  echo "ATTENZIONE: app non risulta in primo piano" >&2
  adb shell dumpsys activity activities 2>/dev/null | grep -i "resumedactivity" || true
fi
sleep 15  # boot interno app (db, onboarding)

shot() { adb exec-out screencap -p > "/tmp/shots/$1.png"; }

# helper: centro di un nodo semantico (uiautomator dump) per label
find_label() {
  LBL=$1
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1 || true
  python3 /tmp/tapfind.py "$LBL" 2>/dev/null || true
}

cat > /tmp/tapfind.py <<'PYEOF'
import re, sys
lbl = sys.argv[1].strip().lower()
try:
    xml = open('/tmp/ui.xml', encoding='utf-8', errors='replace').read()
except OSError:
    sys.exit(0)
for tag in re.findall(r'<node\b[^>]*>', xml):
    if 'bounds="' not in tag:
        continue
    vals = []
    for attr in ('text', 'content-desc'):
        m = re.search(r'\b' + attr + r'="([^"]*)"', tag)
        if m:
            vals.append(m.group(1))
    if any(v.strip().lower() == lbl for v in vals):
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if b:
            x1, y1, x2, y2 = map(int, b.groups())
            print(f'{(x1 + x2) // 2} {(y1 + y2) // 2}')
        sys.exit(0)
PYEOF

tap_label() {
  LBL=$1; FX=$2; FY=$3
  XY=$(find_label "$LBL")
  if [ -n "$XY" ]; then
    echo "tap '$LBL' -> $XY (semantica)"
    adb shell input tap $XY || true
  else
    echo "tap '$LBL' -> $FX,$FY (geometrico)"
    adb shell input tap "$FX" "$FY" || true
  fi
}

# geometria: densita' per convertire dp -> px
DEN=$(adb shell wm density 2>/dev/null | grep -oE '[0-9]+' | head -1)
DEN=${DEN:-420}
DPR=$(( DEN / 160 ))

W=$(adb shell wm size | grep -oE '[0-9]+' | head -1)
H=$(adb shell wm size | tr -d '\r' | grep -oE '[0-9]+' | tail -1)
echo "screen: ${W}x${H} density: $DEN (dpr $DPR)"

# ---- 01-02 avvio + timeline ----
shot 01_timeline_avvio
sleep 5
shot 02_timeline

# centro del bottone AI: ~40dp sopra il centro del tab Timeline (design 88dp,
# cerchio 68dp, top -16 rispetto alla barra). Fallback: 14% dal fondo.
AI_X=$(( W / 2 ))
TY=$(find_label "Timeline")
if [ -n "$TY" ]; then
  TYY=$(echo "$TY" | awk '{print $2}')
  AI_Y=$(( TYY - 40 * DPR ))
  echo "AI center da semantica: $AI_X,$AI_Y"
else
  AI_Y=$(( H - H * 14 / 100 ))
  echo "AI center geometrico: $AI_X,$AI_Y"
fi

# ---- 03 menu radiale (pulsante AI centrale) ----
adb shell input tap "$AI_X" "$AI_Y" || true
sleep 3
shot 03_menu_radiale
adb shell input keyevent 4 || true
sleep 2

# ---- 04-06 tab Community (gate demo login) e ritorno timeline ----
tap_label "Community" $(( W * 32 / 100 )) $(( H - H * 8 / 100 ))
sleep 6
shot 04_community
adb shell input tap $(( W / 2 )) $(( H * 28 / 100 )) || true
sleep 8
shot 05_dopo_login_demo
tap_label "Timeline" $(( W * 8 / 100 )) $(( H - H * 8 / 100 ))
sleep 5
shot 06_timeline_loggato

# ---- 07 tab Events ----
tap_label "Events" $(( W * 68 / 100 )) $(( H - H * 8 / 100 ))
sleep 6
shot 07_events

# ---- 08 tab Library ----
tap_label "Library" $(( W * 92 / 100 )) $(( H - H * 8 / 100 ))
sleep 6
shot 08_library

# ---- 09-10 esplorazione header timeline ----
tap_label "Timeline" $(( W * 8 / 100 )) $(( H - H * 8 / 100 ))
sleep 4
adb shell input tap $(( W - W * 22 / 100 )) $(( H * 17 / 100 )) || true
sleep 4
shot 09_header_tap_1
adb shell input tap $(( W - W * 10 / 100 )) $(( H * 17 / 100 )) || true
sleep 4
shot 10_header_tap_2
adb shell input keyevent 4 || true
sleep 2

# ---- 11 community come ultimo stato ----
tap_label "Community" $(( W * 32 / 100 )) $(( H - H * 8 / 100 ))
sleep 4
shot 11_ultimo_tab

echo "== shots generati =="
ls -lh /tmp/shots
