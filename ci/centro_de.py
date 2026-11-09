"""Imprime «x y», el centro del primer elemento de un volcado de uiautomator
cuya descripción contiene el texto dado. No imprime nada si no lo encuentra."""
import re
import sys
import xml.etree.ElementTree as ET

ruta, texto = sys.argv[1], sys.argv[2]
try:
    raiz = ET.parse(ruta).getroot()
except Exception:
    sys.exit(0)
for nodo in raiz.iter('node'):
    if texto in (nodo.get('content-desc') or '') or texto in (nodo.get('text') or ''):
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', nodo.get('bounds') or '')
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
