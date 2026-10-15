#!/usr/bin/env python3
"""Verifica (y opcionalmente descarga) las fotos de demostración de Eje.

Lee el mapa DEMO de index.html, lo compara con Free Exercise DB
(https://github.com/yuhonas/free-exercise-db, dominio público) y avisa
qué carpetas no existen, con sugerencias de nombres parecidos.

Uso, desde la raíz del repo:
  python3 tools/demos.py              # solo verificar
  python3 tools/demos.py --descargar  # además, copiar las fotos a demos/

Si descargás, agregá  demoBase: 'demos/'  en config.js para que la app
use las copias del repo en vez de las de GitHub.
"""
import difflib, json, pathlib, re, sys, urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DATA = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
IMGS = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"


def mapa_demo():
    html = (RAIZ / "index.html").read_text(encoding="utf-8")
    bloque = re.search(r"const DEMO=\{(.*?)\n\};", html, re.S)
    if not bloque:
        sys.exit("No encontré el bloque DEMO en index.html")
    return dict(re.findall(r"(\w+):\['([^']+)'", bloque.group(1)))


def main():
    descargar = "--descargar" in sys.argv
    demo = mapa_demo()
    print(f"Descargando el listado de Free Exercise DB…")
    with urllib.request.urlopen(DATA, timeout=60) as r:
        ejercicios = json.load(r)
    por_id = {e["id"]: e for e in ejercicios}
    ids = list(por_id)

    faltan = 0
    for nuestro, ext in sorted(demo.items()):
        if ext in por_id:
            print(f"  ok      {nuestro:13} → {ext}")
            if descargar:
                for img in por_id[ext].get("images", [])[:2]:
                    destino = RAIZ / "demos" / img
                    destino.parent.mkdir(parents=True, exist_ok=True)
                    if not destino.exists():
                        urllib.request.urlretrieve(IMGS + img, destino)
        else:
            faltan += 1
            parecidos = difflib.get_close_matches(ext, ids, n=4, cutoff=0.5)
            print(f"  FALTA   {nuestro:13} → {ext}")
            if parecidos:
                print(f"          parecidos: {', '.join(parecidos)}")

    print()
    if faltan:
        print(f"{faltan} sin coincidencia. Corregí esos nombres en el bloque DEMO de index.html.")
        print("Mientras tanto, la app oculta sola las demostraciones que no cargan.")
    else:
        print("Todas las demostraciones existen.")
    if descargar:
        print("Fotos copiadas en demos/. Agregá  demoBase: 'demos/'  en config.js.")


if __name__ == "__main__":
    main()
