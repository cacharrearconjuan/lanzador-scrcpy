"""Copia el lanzador poniendo el numero de version, sin tocar nada mas.

Uso: python3 scripts/poner_version.py ORIGEN DESTINO 1.2.0
Trabaja en bytes para conservar los finales de linea CRLF.
"""
import re
import sys

origen, destino, version = sys.argv[1], sys.argv[2], sys.argv[3]
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    sys.exit(f"Version no valida: {version}")

datos = open(origen, "rb").read()
buscar = b"$VersionLanzador = 'dev'"
if datos.count(buscar) != 1:
    sys.exit("No encuentro la linea $VersionLanzador = 'dev' (o sale mas de una vez)")

datos = datos.replace(buscar, b"$VersionLanzador = '" + version.encode() + b"'")
open(destino, "wb").write(datos)
print(f"{destino}: version {version}")
