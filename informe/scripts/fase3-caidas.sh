#!/usr/bin/env bash
# Fase 3: verificaciones que detienen servicios (se hacen al final, como piden las guías).
cd "$(dirname "$0")" && source lib.sh
E=../evidencias
tokens

# Matrículas · paso 10: estudiantes-service caído
./servicios.sh stop estudiantes-service
EVID=$E/05-matriculas-service.md
nota "#### Pruebas de caída (ejecutadas al final)\n\nSe detuvo estudiantes-service (\`servicios.sh stop estudiantes-service\`)."
paso 10 "Con estudiantes-service detenido, registrar otra matrícula" "502 No fue posible consultar el estudiante…" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":4,"cursoId":1}'

# E1 · paso 8: matriculas-service caído
./servicios.sh stop matriculas-service
EVID=$E/07-e1-integridad.md
nota "#### Prueba de caída (ejecutada al final)\n\nSe detuvo matriculas-service (\`servicios.sh stop matriculas-service\`)."
paso 8 "Con matriculas-service detenido: DELETE /api/cursos/1" "502 No fue posible verificar las matrículas del curso…" DELETE $CUR/api/cursos/1 "$T_ADMIN"
paso 8b "GET /api/cursos/1 (comprobar que el curso sigue existiendo)" "200" GET $CUR/api/cursos/1 "$T_ADMIN"

# Seguridad · paso 9: auth-service caído
./servicios.sh stop auth-service
EVID=$E/01-seguridad.md
nota "#### Prueba de caída (ejecutada al final)\n\nSe detuvo auth-service (\`servicios.sh stop auth-service\`)."
paso 9 "Con auth-service detenido: ESTUDIANTE GET /api/cursos" "401 TOKEN_VALIDATION_ERROR" GET $CUR/api/cursos "$T_EST"

./servicios.sh stop
