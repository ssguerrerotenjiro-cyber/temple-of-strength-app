"""Prueba la versión web en navegadores de verdad antes de publicarla.

Abre la app como un Android (Chromium), un iPhone (Chromium y WebKit, el
motor de Safari) y un computador, espera a que dibuje su primera pantalla y
guarda una captura de cada uno. Falla si en Chromium la app no llega a
dibujarse. Uso: python3 ci/probar_web.py <url> <carpeta de salida>
"""
import json
import pathlib
import sys
import time

from playwright.sync_api import sync_playwright

URL = sys.argv[1]
SALIDA = pathlib.Path(sys.argv[2])
SALIDA.mkdir(parents=True, exist_ok=True)


def dispositivo(p, nombre):
    d = dict(p.devices[nombre])
    d.pop('default_browser_type', None)
    return d


def probar(p, caso, motor, opciones, obligatorio=True):
    navegador = None
    # En GitHub ya viene Chrome instalado: se usa ese y, si no está, el de Playwright.
    for canal in (('chrome', None) if motor == 'chromium' else (None,)):
        try:
            navegador = getattr(p, motor).launch(**({'channel': canal} if canal else {}))
            break
        except Exception as e:  # WebKit o Chrome pueden no estar instalados
            falla = e
    if navegador is None:
        return {'caso': caso, 'ok': None if not obligatorio else False, 'obligatorio': obligatorio,
                'motivo': f'Sin {motor}: {falla}'[:300]}
    contexto = navegador.new_context(locale='es-CO', **opciones)
    pagina = contexto.new_page()
    errores, consola = [], []
    pagina.on('pageerror', lambda e: errores.append(str(e)[:500]))
    pagina.on('console', lambda m: consola.append(f'{m.type}: {m.text}'[:400])
              if m.type in ('error', 'warning') else None)
    t0 = time.time()
    ok, motivo, primer = True, '', None
    try:
        pagina.goto(URL, wait_until='load', timeout=90_000)
        pagina.wait_for_function("() => !document.getElementById('carga')", timeout=120_000)
        primer = round(time.time() - t0, 1)
    except Exception as e:
        ok, motivo = False, f'La app no dibujó su primera pantalla: {e}'[:400]
    pagina.wait_for_timeout(6_000)
    pagina.screenshot(path=str(SALIDA / f'{caso}.png'))
    navegador.close()
    return {'caso': caso, 'motor': motor, 'ok': ok, 'obligatorio': obligatorio,
            'primer_cuadro_s': primer, 'motivo': motivo, 'errores': errores[:20], 'consola': consola[:40]}


with sync_playwright() as p:
    resultados = [
        probar(p, 'android', 'chromium', dispositivo(p, 'Pixel 7')),
        probar(p, 'iphone', 'chromium', dispositivo(p, 'iPhone 13')),
        probar(p, 'computador', 'chromium', {'viewport': {'width': 1440, 'height': 900}}),
        probar(p, 'computador_mediano', 'chromium', {'viewport': {'width': 900, 'height': 820}}),
        probar(p, 'iphone_safari', 'webkit', dispositivo(p, 'iPhone 13'), obligatorio=False),
    ]

(SALIDA / 'resultado.json').write_text(json.dumps(resultados, ensure_ascii=False, indent=2), encoding='utf-8')
for r in resultados:
    estado = {True: 'bien', False: 'FALLÓ', None: 'omitida'}[r['ok']]
    print(f"{r['caso']:<20} {estado:<8} primer cuadro: {r.get('primer_cuadro_s')} s  "
          f"errores: {len(r.get('errores', []))}  {r.get('motivo', '')}")
    for e in r.get('errores', [])[:5]:
        print('   ·', e)
if any(r['ok'] is False and r['obligatorio'] for r in resultados):
    sys.exit(1)
