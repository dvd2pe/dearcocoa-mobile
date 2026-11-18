#!/usr/bin/env bash
# DearCocoa — build APK demo firmato (flavor global), riproducibile ovunque.
# Uso: bash app/scripts/build_demo_apk.sh
# Output: app/dearcocoa-demo.apk (firmato con keystore demo locale, installabile)
set -euo pipefail
cd "$(dirname "$0")/.."   # app/

: "${ANDROID_HOME:?Serve ANDROID_HOME con SDK Android (platform-tools, platforms;android-35/36, build-tools;36.0.0, ndk;27.0.12077973)}"

# 1. Build release firmata con il keystore demo (creato se assente, mai committato)
KS=android/app/demo.keystore
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -alias dearcocoa -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass dearcocoa2026 -keypass dearcocoa2026 \
    -dname "CN=DearCocoa Demo, O=DearCocoa, C=IT"
fi
cat > android/app/key-global.properties <<EOF
keyAlias=dearcocoa
keyPassword=dearcocoa2026
storeFile=$KS
storePassword=dearcocoa2026
EOF

# 2. Build release (flavor global = appLabel DearCocoa, appId app.dearcocoa.mobile)
flutter pub get
flutter build apk --release --flavor global

# 3. Firma (se il build non ha già usato il keystore) e ridenomina
OUT=build/app/outputs/flutter-apk
APK=$(ls "$OUT"/app-global-release*.apk 2>/dev/null | head -1 || ls "$OUT"/*.apk | head -1)
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
"$BT/zipalign" -f -p 4 "$APK" "$OUT/dearcocoa-demo-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:dearcocoa2026 \
  --out dearcocoa-demo.apk "$OUT/dearcocoa-demo-aligned.apk"
rm -f "$OUT/dearcocoa-demo-aligned.apk"

echo "OK → $(pwd)/dearcocoa-demo.apk ($(du -h dearcocoa-demo.apk | cut -f1))"
