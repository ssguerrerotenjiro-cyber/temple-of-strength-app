# Temple of Strength en VS Code

Código completo de la versión 1.7.0, con la carpeta `android/` ya preparada (permisos, nombre, icono y AdMob). Sirve para correr la app en tu celular Android desde VS Code y probar el **Camino del día** (mapa, pasos, km y calorías).

> **Los pasos se cuentan con el sensor del teléfono.** El emulador de Android no tiene ese sensor: ahí los pasos salen del GPS. Para ver el conteo real, usa tu celular.

## 1. Lo que necesitas instalado (una sola vez)

1. **Flutter**, canal estable. Guía oficial: https://docs.flutter.dev/get-started. Este paquete se armó con la versión que dice `FLUTTER_USADO.txt`; una igual o más nueva sirve.
2. **Android Studio**, solo para el SDK de Android. Ábrelo una vez y deja que instale el SDK.
3. **VS Code** con la extensión **Flutter** (VS Code la recomienda al abrir la carpeta).
4. En una terminal, corre `flutter doctor` y `flutter doctor --android-licenses` (acepta todo con `y`). Las líneas de Android y VS Code deben salir con ✓.

## 2. Abrir el proyecto

1. Descomprime el zip en una carpeta sin espacios raros, por ejemplo `C:\proyectos\temple`.
2. En VS Code: **Archivo → Abrir carpeta…** y elige esa carpeta.
3. En la terminal de VS Code (**Terminal → Nueva terminal**):

   ```
   flutter pub get
   ```

## 3. Preparar tu celular

1. **Desinstala la app de Temple** que bajaste de la página. Esta versión se firma con otra llave (la de pruebas) y Android no deja instalarla encima. Tu cuenta, tu progreso y tus fotos están en el servidor: no se pierden.
2. Activa las **Opciones de desarrollador**: Ajustes → Acerca del teléfono → toca 7 veces «Número de compilación».
3. En Opciones de desarrollador, activa **Depuración por USB**.
4. Conecta el celular por cable y acepta el aviso «¿Permitir depuración por USB?».
5. Abajo a la derecha en VS Code debe aparecer el nombre de tu celular. Si no, toca ahí y elígelo.

## 4. Correr la app

En VS Code, ve a **Ejecutar y depurar** (Ctrl+Shift+D), elige una configuración arriba y presiona **F5**:

| Configuración | Para qué |
| --- | --- |
| **Temple · vista de prueba (sin cuenta)** | Abre el Dojo directo, sin iniciar sesión. Lo más rápido para probar los pasos. |
| **Temple · con mi cuenta** | La app normal: inicias sesión y ves el aviso del Camino la primera vez. |
| **Temple · rápida como el APK (release)** | Igual de fluida que el APK, pero sin recarga en caliente. |

La primera vez tarda varios minutos (descarga Gradle y compila). Las siguientes son mucho más rápidas, y con la app abierta puedes guardar un cambio en el código y verlo al instante (recarga en caliente).

## 5. Probar el Camino del día

**Con la vista de prueba:**

1. En el banner del Dojo dice «Falta el permiso de ubicación». Toca **Permitir**.
2. Acepta **Actividad física** (los pasos) y **Ubicación → Mientras se usa la app**.
3. Sal a un lugar abierto: aparece el mapa con tu punto violeta.
4. Camina 30 o 40 pasos con el celular en la mano o el bolsillo. El contador sube (el sensor a veces entrega los pasos con unos segundos de retraso).
5. Toca el banner para abrir la pantalla grande: distancia, calorías, ritmo, la semana, tu estatura y tu meta.

**Con tu cuenta:** en el Dojo verás «Tu camino del día» y el botón **Activar**. Al tocarlo sale el aviso que explica qué se usa; después Android pide los permisos.

**Para empezar de cero** (volver a ver el botón Activar o reiniciar los pasos): Ajustes del celular → Apps → Temple of Strength → Almacenamiento → **Borrar datos**.

**En el emulador** (si no tienes el celular a mano): los pasos salen del GPS. Para simular una caminata: en el emulador, **⋮ → Location → Routes**, traza una ruta y dale «Play route».

## 6. Si algo falla

- **Error de Gradle o de versión de Android al compilar:** borra la carpeta `android` y vuelve a crearla con tu versión de Flutter:

  ```
  flutter create --org com.templeofstrength --project-name temple_of_strength --platforms android .
  python ci/preparar_android.py
  flutter pub get
  dart run flutter_launcher_icons
  ```

  (`python` necesita Python 3 instalado: https://www.python.org/downloads/).
- **«INSTALL_FAILED_UPDATE_INCOMPATIBLE»:** todavía está instalada la app de la página. Desinstálala (paso 3.1).
- **El contador de pasos no sube:** revisa que el permiso «Actividad física» esté permitido (Ajustes → Apps → Temple of Strength → Permisos). Algunos celulares muy básicos no tienen sensor de pasos; en ese caso la app los calcula con el GPS mientras está abierta.
- **El mapa sale vacío:** necesita internet para descargar el mapa.

## Qué hay en el paquete

- `lib/main.dart`: toda la app. `lib/camino_app.dart`: el Camino del día (solo en la app). `lib/camino_web.dart`: lo que usa la web en su lugar.
- `assets/`: sonidos, icono y el estilo del mapa.
- `android/`: el proyecto Android ya preparado (sin la llave de firma: se firma con la de pruebas).
- `pubspec.lock`: las versiones exactas de los paquetes con las que se probó.
- `ci/`: los scripts que preparan Android y iPhone.

**Nunca pongas llaves ni contraseñas en el código** (ni la de la IA, ni la de firma). La app de iPhone no se puede compilar en Windows: necesita un Mac.
