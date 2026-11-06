"""Mide cuánto trabaja el navegador con la versión web en reposo.

Abre la app (pantalla de inicio de sesión, que tiene luna, estrellas y
pétalos animados), espera a que se asiente y mide durante unos segundos:
  - cuadros por segundo que pide la app (requestAnimationFrame),
  - tiempo de CPU del hilo principal por segundo (script + dibujo),
  - tareas largas (más de 50 ms), que son las que se sienten como tirones.
Uso: python3 ci/medir_web.py <url> <salida.json> [segundos]
"""
import json
import sys

from playwright.sync_api import sync_playwright

URL = sys.argv[1]
SALIDA = sys.argv[2]
SEGUNDOS = float(sys.argv[3]) if len(sys.argv) > 3 else 8


def medir(p, caso, opciones):
    navegador = p.chromium.launch(args=['--enable-unsafe-swiftshader'])
    contexto = navegador.new_context(**opciones)
    pagina = contexto.new_page()
    cdp = contexto.new_cdp_session(pagina)
    cdp.send('Performance.enable')
    pagina.add_init_script("""
      window.__tareasLargas = [];
      try {
        new PerformanceObserver(l => l.getEntries().forEach(e => window.__tareasLargas.push(e.duration)))
          .observe({ entryTypes: ['longtask'] });
      } catch (e) {}
      window.__cuadros = 0;
      const rafOriginal = window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = cb => rafOriginal(t => { window.__cuadros++; cb(t); });
    """)
    pagina.goto(URL, wait_until='load', timeout=90_000)
    pagina.wait_for_function("() => !document.getElementById('carga')", timeout=120_000)
    pagina.wait_for_timeout(4_000)  # que termine la animación de entrada

    def metricas():
        m = {x['name']: x['value'] for x in cdp.send('Performance.getMetrics')['metrics']}
        return m.get('TaskDuration', 0), m.get('ScriptDuration', 0), m.get('Timestamp', 0)

    pagina.evaluate("() => { window.__cuadros = 0; window.__tareasLargas = []; }")
    t0, s0, ts0 = metricas()
    pagina.wait_for_timeout(int(SEGUNDOS * 1000))
    t1, s1, ts1 = metricas()
    cuadros = pagina.evaluate('() => window.__cuadros')
    largas = pagina.evaluate('() => window.__tareasLargas')
    dt = ts1 - ts0
    navegador.close()
    return {
        'caso': caso,
        'cuadros_por_segundo': round(cuadros / dt, 1),
        'cpu_ms_por_segundo': round((t1 - t0) / dt * 1000, 1),
        'script_ms_por_segundo': round((s1 - s0) / dt * 1000, 1),
        'tareas_largas': len(largas),
        'tarea_larga_max_ms': round(max(largas), 1) if largas else 0,
    }


with sync_playwright() as p:
    def dispositivo(nombre):
        d = dict(p.devices[nombre])
        d.pop('default_browser_type', None)
        return d
    resultados = [
        medir(p, 'iphone', dispositivo('iPhone 13')),
        medir(p, 'computador', {'viewport': {'width': 1440, 'height': 900}}),
    ]

json.dump(resultados, open(SALIDA, 'w'), ensure_ascii=False, indent=2)
for r in resultados:
    print(r)
