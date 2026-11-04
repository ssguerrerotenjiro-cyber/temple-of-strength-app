#!/bin/bash
# Instala el APK en el emulador, lo abre y comprueba que siga abierto.
# Sale con error (y no se publica nada) si la app se cierra sola.
PKG=com.templeofstrength.app
APK=${1:-salida/TempleOfStrength.apk}
OUT=resultado/api${API:-x}
mkdir -p "$OUT"
adb wait-for-device
adb shell getprop ro.build.version.release > "$OUT/android.txt"
if ! adb install "$APK" > "$OUT/instalar.txt" 2>&1; then
  cat "$OUT/instalar.txt"; echo "::error::El APK no se pudo instalar"; exit 1
fi
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 30
adb exec-out screencap -p > "$OUT/pantalla_30s.png"
PID1=$(adb shell pidof $PKG)
sleep 15
adb exec-out screencap -p > "$OUT/pantalla_45s.png"
PID2=$(adb shell pidof $PKG)
adb logcat -d -v time > "$OUT/logcat.txt"
echo "Proceso a los 30 s: '${PID1}', a los 45 s: '${PID2}'"
if grep -q "FATAL EXCEPTION" "$OUT/logcat.txt" || [ -z "$PID2" ]; then
  grep -A40 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -80
  grep -E "E/flutter" "$OUT/logcat.txt" | head -40
  echo "::error::La app se cerró al abrirla en Android $(cat $OUT/android.txt)"
  exit 1
fi
echo "Errores de Flutter (si hay):"
grep -E "E/flutter" "$OUT/logcat.txt" | head -40
echo "La app abrió y siguió abierta en Android $(cat $OUT/android.txt)."
