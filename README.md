# Temple of Strength

App de entrenamiento con alma de dojo (Flutter). Código privado.

- `lib/main.dart`: toda la app.
- `assets/`: sonidos e icono.
- `.github/workflows/apk.yml`: cada cambio en `main` construye el APK firmado y lo publica en *Releases*.
- `ci/preparar_android.py`: ajusta el proyecto Android que genera `flutter create` (internet, nombre, identificador `com.templeofstrength.app`, AdMob, firma).

Para una versión nueva: sube `version:` en `pubspec.yaml` (por ejemplo `1.0.1+1`) y haz un cambio en `main`.
