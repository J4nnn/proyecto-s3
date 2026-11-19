#!/usr/bin/env bash
# Fase 2 (servicios reiniciados, datos recién iniciados): extensiones en orden E2 -> E1 -> E4 -> E3.
cd "$(dirname "$0")" && source lib.sh
E=../evidencias
tokens

# ---------------- E2 · Cupos ----------------
EVID=$E/06-e2-cupos.md; : > $EVID
nota "### Evidencias · Extensión E2 (cupos)\n\nCon los servicios recién reiniciados. Token de admin."
paso 1 "GET /api/cursos/3 (8083)" "RED-001 con cupoMaximo: 2" GET $CUR/api/cursos/3 "$T_ADMIN"
paso 2 "POST /api/matriculas {estudianteId:1, cursoId:3}" "201" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":3}'
paso 3 "POST /api/matriculas {estudianteId:2, cursoId:3}" "201" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":2,"cursoId":3}'
paso 4 "POST /api/matriculas {estudianteId:3, cursoId:3}" "400 El curso no tiene cupos disponibles (2/2)" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":3,"cursoId":3}'
paso 5 "PUT /api/matriculas/2/anular" "200, estado ANULADA" PUT $MAT/api/matriculas/2/anular "$T_ADMIN"
paso 6 "Repetir el paso 4" "201: se liberó un cupo" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":3,"cursoId":3}'
C3=$(curl -s -H "Authorization: Bearer $T_ADMIN" $CUR/api/cursos/3 | jq -c '.data | del(.id) | .cupoMaximo=1')
paso 7 "PUT /api/cursos/3 con los mismos datos y cupoMaximo: 1" "400 El cupo no puede ser menor que las 2 matrícula(s) activa(s) del curso" PUT $CUR/api/cursos/3 "$T_ADMIN" "$C3"
paso 8 "POST /api/cursos sin cupoMaximo" "400 El cupo máximo es obligatorio" POST $CUR/api/cursos "$T_ADMIN" '{"codigo":"SIN-CUPO","nombre":"Sin cupo","creditos":3,"docenteResponsable":"Docente"}'

# ---------------- E1 · Integridad ----------------
EVID=$E/07-e1-integridad.md; : > $EVID
nota "### Evidencias · Extensión E1 (integridad entre servicios)\n\nContinuando con los datos de E2 (curso 3 con dos matrículas activas). Token de admin."
paso 1 "GET /api/matriculas/activas/conteo?cursoId=3" "200 con data: 2" GET "$MAT/api/matriculas/activas/conteo?cursoId=3" "$T_ADMIN"
paso 2 "GET /api/matriculas/activas/conteo (sin filtro)" "400 Envíe exactamente uno de los parámetros…" GET "$MAT/api/matriculas/activas/conteo" "$T_ADMIN"
paso 3 "DELETE /api/cursos/3" "409 No se puede eliminar: el curso tiene 2 matrícula(s) activa(s)" DELETE $CUR/api/cursos/3 "$T_ADMIN"
paso 4 "DELETE /api/estudiantes/1 (tiene una matrícula activa)" "409" DELETE $EST/api/estudiantes/1 "$T_ADMIN"
paso 5 "DELETE /api/estudiantes/50 (sin matrículas)" "200" DELETE $EST/api/estudiantes/50 "$T_ADMIN"
paso 6a "Matricular al estudiante 5 en el curso 2" "201" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":5,"cursoId":2}'
M6=$(echo "$LAST_BODY" | jq .data.id)
paso 6b "DELETE /api/cursos/2" "409 …tiene 1 matrícula(s) activa(s)" DELETE $CUR/api/cursos/2 "$T_ADMIN"
paso 7a "Anular la matrícula $M6" "200" PUT $MAT/api/matriculas/$M6/anular "$T_ADMIN"
paso 7b "Repetir DELETE /api/cursos/2" "200: sin matrículas activas, el curso se elimina" DELETE $CUR/api/cursos/2 "$T_ADMIN"
nota "_El paso 8 (detener matriculas-service) se ejecuta al final; ver la sección de pruebas de caída._"

# ---------------- E4 · Mis matrículas ----------------
EVID=$E/08-e4-mis-matriculas.md; : > $EVID
nota "### Evidencias · Extensión E4 (mis matrículas)\n\nContinuando con los datos de E2/E1."
paso 1 "Login como estudiante y GET /auth/validate" "estudianteId: 1" GET $AUTH/auth/validate "$T_EST"
paso 2 "ADMIN: GET /api/matriculas (matrículas de varios estudiantes)" "Existen matrículas de los estudiantes 1, 2, 3 (y 5)" GET "$MAT/api/matriculas?size=20" "$T_ADMIN"
paso 3 "ESTUDIANTE: GET /api/matriculas/mias" "Solo las matrículas del estudiante 1" GET $MAT/api/matriculas/mias "$T_EST"
paso 4 "ESTUDIANTE: GET /api/matriculas" "403 AUTH_FORBIDDEN" GET $MAT/api/matriculas "$T_EST"
paso 5 "ESTUDIANTE: GET /api/matriculas/2 (de otro estudiante)" "403" GET $MAT/api/matriculas/2 "$T_EST"
paso 6 "ADMIN: GET /api/matriculas/mias" "403" GET $MAT/api/matriculas/mias "$T_ADMIN"

# ---------------- E3 · Calificaciones ----------------
EVID=$E/09-e3-calificaciones.md; : > $EVID
nota "### Evidencias · Extensión E3 (calificaciones-service)\n\nMatrícula 1 activa (estudiante 1) y matrícula 2 anulada, como quedan después de E2."
paso 1 "DOCENTE: POST {matriculaId:1, corte:1, nota:4.0}" "201, registradoPor: docente" POST $CAL/api/calificaciones "$T_DOC" '{"matriculaId":1,"corte":1,"nota":4.0}'
paso 2 "DOCENTE: POST {matriculaId:1, corte:2, nota:3.0}" "201" POST $CAL/api/calificaciones "$T_DOC" '{"matriculaId":1,"corte":2,"nota":3.0}'
paso 3 "DOCENTE: repetir el paso 1" "400 …use PUT para corregirla" POST $CAL/api/calificaciones "$T_DOC" '{"matriculaId":1,"corte":1,"nota":4.0}'
paso 4 "DOCENTE: POST con corte 4 y nota 5.5" "400 con los errores de ambos campos" POST $CAL/api/calificaciones "$T_DOC" '{"matriculaId":1,"corte":4,"nota":5.5}'
paso 5 "DOCENTE: POST sobre la matrícula anulada (id 2)" "400 La matrícula 2 no está activa" POST $CAL/api/calificaciones "$T_DOC" '{"matriculaId":2,"corte":1,"nota":4.0}'
paso 6 "ADMIN: PUT /api/calificaciones/1 {nota:4.5}" "200, registradoPor: admin" PUT $CAL/api/calificaciones/1 "$T_ADMIN" '{"nota":4.5}'
paso 7 "DOCENTE: GET /api/calificaciones/matricula/1" "promedioPonderado: 3.75, completa: false" GET $CAL/api/calificaciones/matricula/1 "$T_DOC"
paso 8 "DOCENTE: GET /api/calificaciones/matricula/99" "404" GET $CAL/api/calificaciones/matricula/99 "$T_DOC"
paso 9 "ESTUDIANTE: POST /api/calificaciones" "403" POST $CAL/api/calificaciones "$T_EST" '{"matriculaId":1,"corte":3,"nota":5.0}'
paso 10 "ESTUDIANTE: GET /api/calificaciones/mias" "Solo el resumen de sus matrículas" GET $CAL/api/calificaciones/mias "$T_EST"
