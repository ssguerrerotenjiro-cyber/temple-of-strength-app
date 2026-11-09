"""Ajusta el proyecto iOS que crea `flutter create --platforms ios` para Temple of Strength.

Todavía no hay compilación de iPhone (necesita un Mac y la cuenta de Apple
Developer). Cuando la haya, correr esto después de `flutter create` deja los
textos que el iPhone muestra al pedir permisos:

- Ubicación mientras se usa la app (Camino del día). Nunca en segundo plano:
  no se agrega UIBackgroundModes `location`, y la app pide
  `allowBackgroundLocationUpdates: false`.
- Movimiento y actividad física (sensor de pasos del Camino del día).
- Fotos, cámara y micrófono (fotos de progreso, perfil y videos del Clan).

permission_handler solo se usa en Android, así que no hace falta activar
ninguna de sus macros en el Podfile.
"""
import os
import plistlib

RUTA = 'ios/Runner/Info.plist'

if not os.path.exists(RUTA):
    raise SystemExit('No hay proyecto iOS: corre antes `flutter create --platforms ios .`')

with open(RUTA, 'rb') as f:
    info = plistlib.load(f)

info['CFBundleDisplayName'] = 'Temple of Strength'
info['NSLocationWhenInUseUsageDescription'] = (
    'Temple usa tu ubicación mientras la app está abierta para mostrarte en el mapa del Camino del día '
    'y medir tu recorrido. Tu ubicación no sale de tu teléfono.')
info['NSMotionUsageDescription'] = (
    'Temple usa el sensor de movimiento para contar tus pasos del día. Tus pasos se quedan en tu teléfono.')
info.setdefault('NSPhotoLibraryUsageDescription',
                'Para elegir fotos de progreso, de perfil y para el Clan.')
info.setdefault('NSCameraUsageDescription',
                'Para tomar fotos de progreso y para el Clan.')
info.setdefault('NSMicrophoneUsageDescription',
                'Para grabar videos del Clan con sonido.')

with open(RUTA, 'wb') as f:
    plistlib.dump(info, f)
print('Ajustado', RUTA)
