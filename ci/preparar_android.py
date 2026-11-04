"""Ajusta el proyecto Android que crea `flutter create` para Temple of Strength.

- Permiso de internet (sin él, la app instalada no se conecta).
- Nombre visible, identificador y versión mínima de Android.
- Código de AdMob y apertura de enlaces https.
- Firma con la llave propia si existe android/key.properties.
- Recordatorios: permisos, receptores, icono de notificación y desugaring.
- Reglas de R8 para que el APK de release no se cierre al abrir.
"""
import os, re, sys, shutil

ID = 'com.templeofstrength.app'
NOMBRE = 'Temple of Strength'
ADMOB = os.environ.get('ADMOB_APP_ID') or 'ca-app-pub-3940256099942544~3347511713'


def leer(p):
    return open(p, encoding='utf-8').read()


def escribir(p, s):
    open(p, 'w', encoding='utf-8').write(s)
    print('Ajustado', p)


# -- AndroidManifest ---------------------------------------------------------
man = 'android/app/src/main/AndroidManifest.xml'
s = leer(man)
if 'android.permission.INTERNET' not in s:
    s = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', s, count=1)
s = re.sub(r'android:label="[^"]*"', f'android:label="{NOMBRE}"', s, count=1)
for permiso in ('android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED'):
    if permiso not in s:
        s = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="%s"/>' % permiso, s, count=1)
if 'ScheduledNotificationReceiver' not in s:
    s = s.replace('</application>', '''    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>''', 1)
if 'com.google.android.gms.ads.APPLICATION_ID' not in s:
    s = s.replace('</application>', f'''    <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="{ADMOB}"/>
    </application>''', 1)
https = '''<intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>'''
if 'android:scheme="https"' not in s:
    if '<queries>' in s:
        s = s.replace('<queries>', '<queries>\n        ' + https, 1)
    else:
        s = s.replace('</manifest>', f'    <queries>\n        {https}\n    </queries>\n</manifest>', 1)
escribir(man, s)

# -- build.gradle(.kts) -----------------------------------------------------
kts = 'android/app/build.gradle.kts'
groovy = 'android/app/build.gradle'
if os.path.exists(kts):
    g = leer(kts)
    g = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{ID}"', g)
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 23)', g)
    # Las notificaciones programadas necesitan «desugaring» de Java.
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    if 'keystorePropertiesFile' not in g:
        # Las importaciones van arriba del todo; el resto, después de plugins {}
        # (Gradle no permite otras instrucciones antes de ese bloque).
        g = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + g
        g = g.replace('\nandroid {', '''
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {''', 1)
        g = g.replace('    buildTypes {', '''    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {''', 1)
        g = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', g)
    escribir(kts, g)
elif os.path.exists(groovy):
    g = leer(groovy)
    g = re.sub(r'applicationId\s*=?\s*"[^"]*"', f'applicationId = "{ID}"', g)
    g = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdkVersion Math.max(flutter.minSdkVersion, 23)', g)
    if 'coreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if 'keystorePropertiesFile' not in g:
        g = g.replace('android {', '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {''', 1)
        g = g.replace('    buildTypes {', '''    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            release {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }

    buildTypes {''', 1)
        g = re.sub(r'signingConfig\s*=?\s*signingConfigs\.debug',
                   'signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug', g)
    escribir(groovy, g)
else:
    sys.exit('No encontré build.gradle de Android')

# -- Icono de las notificaciones (luna y torii en blanco) -------------------
origen = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'res')
destino = 'android/app/src/main/res'
for carpeta in os.listdir(origen):
    os.makedirs(os.path.join(destino, carpeta), exist_ok=True)
    for archivo in os.listdir(os.path.join(origen, carpeta)):
        shutil.copy(os.path.join(origen, carpeta, archivo), os.path.join(destino, carpeta, archivo))
print('Copiado el icono de notificaciones')

# -- Reglas de R8 ------------------------------------------------------------
# WorkManager (lo trae AdMob) crea su base de datos de Room buscando la clase
# «WorkDatabase_Impl» por su nombre. Si R8 le cambia el nombre, la app se cierra
# nada más abrirse con «Failed to create an instance of WorkDatabase».
# Flutter añade android/app/proguard-rules.pro a la compilación de release.
REGLAS = """
# --- Temple of Strength ---
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keepnames class * extends androidx.room.RoomDatabase
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.startup.** { *; }
# Recordatorios (flutter_local_notifications guarda los programados con Gson).
-keep class com.dexterous.** { *; }
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
"""
reglas = 'android/app/proguard-rules.pro'
previo = leer(reglas) if os.path.exists(reglas) else ''
if '--- Temple of Strength ---' not in previo:
    escribir(reglas, previo + REGLAS)
if os.path.exists(kts):
    g = leer(kts)
    if '"proguard-rules.pro"' not in g:
        nuevo = re.sub(r'(buildTypes\s*\{\s*release\s*\{)',
                       r'\1\n            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")', g, count=1)
        if nuevo != g:
            escribir(kts, nuevo)
        else:
            print('Aviso: no encontré buildTypes.release; Flutter añade proguard-rules.pro por su cuenta.')
