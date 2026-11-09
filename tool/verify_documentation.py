"""Comprueba comentarios y responsabilidades de todas las clases de producción."""
from pathlib import Path  # Recorre los archivos propios sin depender del directorio de ejecución.
import re  # Identifica tipos declarados sin incorporar dependencias de la aplicación.
import sys  # Entrega un estado utilizable por una terminal o comprobación automatizada.

project_root = Path(__file__).resolve().parents[1]  # Localiza la raíz del repositorio.
readme = (project_root / "README.md").read_text(encoding="utf-8")  # Consulta el catálogo que acompaña a la entrega.
problems = []  # Acumula declaraciones pendientes de documentación.
declarations = 0  # Cuenta clases, estados privados y enumeraciones.
for source in sorted((project_root / "lib").rglob("*.dart")):
    lines = source.read_text(encoding="utf-8").splitlines()  # Conserva posiciones para los diagnósticos.
    for position, line in enumerate(lines):
        match = re.match(r"\s*(?:abstract\s+class|class|enum|typedef)\s+(\w+)", line)
        if not match:
            continue  # Ignora instrucciones que no declaran un tipo propio.
        declarations += 1
        name = match.group(1)  # Mantiene el identificador inglés utilizado en el código.
        if not any(previous.lstrip().startswith("///") for previous in lines[max(0, position - 3):position]):
            problems.append(f"{source.relative_to(project_root)}:{position + 1}: falta comentario de {name}")
        if f"`{name}`" not in readme:
            problems.append(f"README.md: falta responsabilidad de {name}")
if problems:
    print("\n".join(problems))  # Publica únicamente rutas y nombres del repositorio.
    sys.exit(1)
print(f"Documentación verificada: {declarations} clases y enumeraciones.")
