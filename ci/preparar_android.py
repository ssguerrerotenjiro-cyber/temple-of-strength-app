"""Ajusta el proyecto Android que crea `flutter create` para Temple of Strength.

- Permiso de internet (sin él, la app instalada no se conecta).
- Nombre visible, identificador y versión mínima de Android.
- Código de AdMob y apertura de enlaces https.
- Firma con la llave propia si existe android/key.properties.
"""
import os, re, sys

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
