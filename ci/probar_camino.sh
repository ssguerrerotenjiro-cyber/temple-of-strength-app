#!/bin/bash
# Camino del día en el emulador: da los permisos, simula una caminata con
# ubicaciones falsas y guarda capturas del banner y de la pantalla del camino.
# Usa la vista de prueba (VISTA_PRUEBA=true): abre el Dojo sin cuenta.
PKG=com.templeofstrength.app
APK=${1:-salida/prueba.apk}
OUT=resultado/camino
mkdir -p "$OUT"
adb wait-for-device
adb shell getprop ro.build.version.release > "$OUT/android.txt"
if ! adb install -r "$APK" > "$OUT/instalar.txt" 2>&1; then
  cat "$OUT/instalar.txt"; echo "::error::El APK no se pudo instalar"; exit 1
fi
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACTIVITY_RECOGNITION POST_NOTIFICATIONS; do
  adb shell pm grant $PKG android.permission.$p 2>/dev/null
done
adb shell cmd location set-location-enabled true 2>/dev/null
adb shell settings put secure location_mode 3 2>/dev/null

# Punto de partida: Parque de la 93, Bogotá.
LAT0=4.67640
LON0=-74.04830
caminar() { # $1 = desde, $2 = hasta (pasos de unos 8 m hacia el nororiente)
  for i in $(seq "$1" "$2"); do
    LAT=$(python3 -c "print(f'{$LAT0 + $i*0.00007:.6f}')")
    LON=$(python3 -c "print(f'{$LON0 + $i*0.00003:.6f}')")
    adb emu geo fix "$LON" "$LAT"
    sleep 2
  done
}
adb emu geo fix $LON0 $LAT0
sleep 3
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 30
adb exec-out screencap -p > "$OUT/01_dojo.png"
caminar 1 15
sleep 4
adb exec-out screencap -p > "$OUT/02_dojo_caminando.png"

# Abrir la pantalla del camino tocando el banner.
adb shell uiautomator dump /sdcard/vista.xml > /dev/null 2>&1
adb pull /sdcard/vista.xml "$OUT/vista.xml" > /dev/null 2>&1
XY=$(python3 ci/centro_de.py "$OUT/vista.xml" "Camino del día")
if [ -z "$XY" ]; then
  TAM=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1)
  W=${TAM%x*}; H=${TAM#*x}
  XY="$((W / 2)) $((H * 34 / 100))"
fi
echo "Toque en $XY"
adb shell input tap $XY
sleep 8
adb exec-out screencap -p > "$OUT/03_pantalla.png"
caminar 16 26
sleep 4
adb exec-out screencap -p > "$OUT/04_pantalla_caminando.png"

adb logcat -d -v time > "$OUT/logcat.txt"
echo "Errores de Flutter (si hay):"
grep -E "E/flutter" "$OUT/logcat.txt" | head -60
if grep -q "FATAL EXCEPTION" "$OUT/logcat.txt" || [ -z "$(adb shell pidof $PKG)" ]; then
  grep -A40 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -80
  echo "::error::La app se cerró durante la prueba del camino"
  exit 1
fi
echo "El camino se probó sin cierres en Android $(cat "$OUT/android.txt")."
