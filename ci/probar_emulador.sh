#!/bin/bash
# Instala el APK publicado en un emulador, lo abre y guarda lo que pase.
set -x
PKG=com.templeofstrength.app
OUT=resultado/api$API
mkdir -p $OUT
adb wait-for-device
adb shell getprop ro.build.version.release > $OUT/android.txt
adb install TempleOfStrength.apk > $OUT/instalar.txt 2>&1; echo "codigo=$?" >> $OUT/instalar.txt
cat $OUT/instalar.txt
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
sleep 25
adb shell pidof $PKG > $OUT/pid.txt; echo "pid=$(cat $OUT/pid.txt)"
adb exec-out screencap -p > $OUT/pantalla_25s.png
sleep 20
adb shell pidof $PKG >> $OUT/pid.txt
adb exec-out screencap -p > $OUT/pantalla_45s.png
adb logcat -d -v time > $OUT/logcat.txt
echo "===== FALLOS ====="
grep -n -A40 "FATAL EXCEPTION\|AndroidRuntime" $OUT/logcat.txt | head -150
echo "===== FLUTTER ====="
grep -n "flutter\|E/.*templeofstrength\|Exception" $OUT/logcat.txt | head -120
exit 0
