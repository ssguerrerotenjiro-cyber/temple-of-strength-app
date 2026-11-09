#!/bin/bash
# Camino del día en el emulador, por etapas, para saber qué falla si algo falla:
#   1. La app sin permisos (escena del templo, sin mapa).
#   2. Con el permiso de actividad física (sensor de pasos).
#   3. Con la ubicación: mapa en vivo y una caminata simulada.
#   4. La pantalla del camino.
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
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null
adb shell cmd location set-location-enabled true 2>/dev/null

# Registro continuo: si el emulador se cae, queda lo último que pasó.
adb logcat -c
adb logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGCAT=$!

vivo() { [ "$(timeout 10 adb get-state 2>/dev/null)" = "device" ]; }
captura() { timeout 20 adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
abrir() {
  adb shell am force-stop $PKG
  adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
}
etapa() { # $1 = nombre, $2 = segundos
  for s in $(seq 5 5 "$2"); do
    sleep 5
    if ! vivo; then
      echo "::error::El emulador se cayó en la etapa «$1», unos $s s después de abrir la app"
      kill $LOGCAT 2>/dev/null
      exit 1
    fi
  done
  captura "$1"
  echo "Etapa «$1»: bien"
}

# Punto de partida: Parque de la 93, Bogotá.
LAT0=4.67640
LON0=-74.04830
caminar() { # $1 = desde, $2 = hasta (pasos de unos 8 m hacia el nororiente)
  for i in $(seq "$1" "$2"); do
    LAT=$(python3 -c "print(f'{$LAT0 + $i*0.00007:.6f}')")
    LON=$(python3 -c "print(f'{$LON0 + $i*0.00003:.6f}')")
    timeout 10 adb emu geo fix "$LON" "$LAT" > /dev/null 2>&1
    sleep 2
    if ! vivo; then
      echo "::error::El emulador se cayó durante la caminata (paso $i)"
      kill $LOGCAT 2>/dev/null
      exit 1
    fi
  done
}

# Etapa 0: el emulador solo, sin la app (¿se cae por sí mismo?).
for s in $(seq 5 5 40); do
  sleep 5
  if ! vivo; then echo "::error::El emulador se cayó solo, sin abrir la app ($s s)"; kill $LOGCAT 2>/dev/null; exit 1; fi
done
adb shell am start -a android.settings.SETTINGS > /dev/null 2>&1
for s in $(seq 5 5 20); do
  sleep 5
  if ! vivo; then echo "::error::El emulador se cayó con Ajustes abierto ($s s)"; kill $LOGCAT 2>/dev/null; exit 1; fi
done
captura 0_ajustes
echo "Etapa «0_emulador_solo»: bien"

abrir
etapa 1_sin_permisos 25

adb shell pm grant $PKG android.permission.ACTIVITY_RECOGNITION 2>/dev/null
abrir
etapa 2_con_pasos 20

adb shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
adb shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION 2>/dev/null
timeout 10 adb emu geo fix $LON0 $LAT0 > /dev/null 2>&1
abrir
etapa 3_mapa 30
caminar 1 15
sleep 4
captura 4_mapa_caminando
echo "Etapa «caminata»: bien"

# Abrir la pantalla del camino tocando el banner (sin uiautomator: con la
# animación del mapa nunca queda «quieto» y se cuelga).
TAM=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1)
W=${TAM%x*}; H=${TAM#*x}
adb shell input tap $((W / 2)) $((H * 30 / 100))
sleep 8
captura 5_pantalla
caminar 16 26
sleep 4
captura 6_pantalla_caminando

kill $LOGCAT 2>/dev/null
echo "Errores de Flutter (si hay):"
grep -E "E/flutter" "$OUT/logcat.txt" | head -60
if grep -q "FATAL EXCEPTION" "$OUT/logcat.txt" || [ -z "$(adb shell pidof $PKG)" ]; then
  grep -A40 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -80
  echo "::error::La app se cerró durante la prueba del camino"
  exit 1
fi
echo "El camino se probó sin cierres en Android $(cat "$OUT/android.txt")."
