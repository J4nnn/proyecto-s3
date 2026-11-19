#!/usr/bin/env python3
"""Construye informe/INFORME.md a partir de informe/plantilla.md.

Cada marcador <!-- EVID:archivo.md --> se reemplaza por una tabla-resumen
(paso, petición, esperado, obtenido, mensaje) generada desde las evidencias.
"""
import json
import pathlib
import re

BASE = pathlib.Path(__file__).resolve().parent.parent
EVID = BASE / "evidencias"


# Archivo de evidencia -> (número y título de su subsección en el Anexo B)
ANEXOS = {
    "01-seguridad.md": (1, "Seguridad"),
    "02-auth-service.md": (2, "auth-service"),
    "03-estudiantes-service.md": (3, "estudiantes-service"),
    "04-cursos-service.md": (4, "cursos-service"),
    "05-matriculas-service.md": (5, "matriculas-service"),
    "06-e2-cupos.md": (6, "Extensión E2 · Cupos"),
    "07-e1-integridad.md": (7, "Extensión E1 · Integridad entre servicios"),
    "08-e4-mis-matriculas.md": (8, "Extensión E4 · Mis matrículas"),
    "09-e3-calificaciones.md": (9, "Extensión E3 · Calificaciones"),
    "10-experimento-concurrencia.md": (10, "Experimento de concurrencia"),
    "11-docker.md": (11, "Docker, Swagger y pruebas"),
}


def ancla(num: int, titulo: str) -> str:
    """Ancla estilo GitHub del encabezado 'B.num · titulo'."""
    texto = f"B.{num} · {titulo}".strip().lower()
    texto = re.sub(r"[^\w\s-]", "", texto)
    return re.sub(r"\s", "-", texto)


def anexo_b() -> str:
    partes = [
        "\n\n---\n\n<div class=\"page-break\"></div>\n\n## Anexo B · Evidencias completas\n\n"
        "Petición HTTP y respuesta JSON de cada paso de verificación, tal como las registraron los scripts "
        "descritos en el Anexo A. Los tokens JWT se muestran abreviados como `<token de rol>`.\n"
    ]
    for nombre, (num, titulo) in ANEXOS.items():
        texto = (EVID / nombre).read_text(encoding="utf-8")
        texto = re.sub(r"^### .*\n", "", texto, count=1, flags=re.M).strip()
        partes.append(f"\n<div class=\"page-break\"></div>\n\n### B.{num} · {titulo}\n\n{texto}\n")
    return "".join(partes)


def resumen(nombre: str) -> str:
    texto = (EVID / nombre).read_text(encoding="utf-8")
    bloques = re.split(r"^#### ", texto, flags=re.M)[1:]
    filas = []
    for b in bloques:
        titulo = b.splitlines()[0]
        m = re.match(r"Paso (\S+) — (.*)", titulo)
        if not m:
            continue
        num, desc = m.groups()
        esp = re.search(r"\*\*Esperado:\*\* (.*?)(?: · \*\*Obtenido:\*\* (HTTP \d+))?$", b, re.M)
        esperado = esp.group(1) if esp else ""
        obtenido = esp.group(2) if esp and esp.group(2) else ""
        detalle = ""
        js = re.search(r"```json\n(.*?)```", b, re.S)
        if js:
            try:
                data = json.loads(js.group(1))
                if isinstance(data, dict):
                    partes = []
                    if data.get("errorCode"):
                        partes.append(f"`{data['errorCode']}`")
                    if data.get("message"):
                        partes.append(data["message"])
                    d = data.get("data")
                    if isinstance(d, dict) and "errors" not in data:
                        if "promedioPonderado" in d:
                            partes.append(f"promedioPonderado={d['promedioPonderado']}, completa={str(d['completa']).lower()}")
                        elif "estado" in d:
                            partes.append(f"id={d['id']}, estado={d['estado']}")
                        elif "registradoPor" in d:
                            partes.append(f"registradoPor={d['registradoPor']}")
                        elif "cupoMaximo" in d and "codigo" in d:
                            partes.append(f"{d['codigo']}, cupoMaximo={d['cupoMaximo']}")
                        elif "totalElements" in d:
                            partes.append(f"totalElements={d['totalElements']}, en página={d['numberOfElements']}")
                        elif "valid" in data:
                            pass
                        elif d and set(d) <= {"nombre", "apellido", "email", "edad", "id"}:
                            pass
                        else:
                            errs = "; ".join(f"{k}: {v}" for k, v in d.items() if isinstance(v, str))
                            if errs:
                                partes.append(errs)
                    elif isinstance(d, list):
                        if d and isinstance(d[0], dict) and "promedioPonderado" in d[0]:
                            partes.append(f"{len(d)} resumen(es): " + ", ".join(
                                f"matrícula {x['matriculaId']} → {x['promedioPonderado']}" for x in d))
                        else:
                            partes.append(f"{len(d)} matrícula(s): " + ", ".join(
                                f"id {x['id']} (est. {x['estudianteId']})" for x in d))
                    elif d is not None and not isinstance(d, dict):
                        partes.append(f"data={d}")
                    if "valid" in data:
                        partes.append(f"valid={str(data['valid']).lower()}, role={data.get('role')}, estudianteId={json.dumps(data.get('estudianteId'))}")
                    if "token" in data:
                        partes.append(f"token emitido, role={data.get('role')}")
                    if "openapi" in data:
                        partes.append(f"OpenAPI {data['openapi']}, {len(data.get('paths', []))} rutas")
                    detalle = " · ".join(partes)
            except json.JSONDecodeError:
                pass
        elif "|" in b:
            detalle = "ver tabla en la evidencia"
        ok = "✅"
        if obtenido:
            cod = obtenido.split()[1]
            m2 = re.search(r"\b([1-5]\d\d)\b", esperado)
            if m2 and m2.group(1) != cod:
                ok = "❌"
        filas.append(f"| {num} | {desc} | {esperado} | {obtenido or '—'} {ok} | {detalle} |")
    cab = "| # | Petición | Esperado | Obtenido | Respuesta (resumen) |\n|---|---|---|---|---|"
    num, titulo = ANEXOS[nombre]
    enlace = f"\n\nEvidencia completa (petición y respuesta JSON de cada paso): [Anexo B.{num} · {titulo}](#{ancla(num, titulo)})"
    return cab + "\n" + "\n".join(filas) + enlace


def main() -> None:
    plantilla = (BASE / "plantilla.md").read_text(encoding="utf-8")
    salida = re.sub(r"<!-- EVID:(\S+) -->", lambda m: resumen(m.group(1)), plantilla) + anexo_b()
    (BASE / "INFORME.md").write_text(salida, encoding="utf-8")
    print("INFORME.md generado")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        print(resumen(sys.argv[1]))
    else:
        main()
