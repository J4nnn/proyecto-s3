#!/usr/bin/env bash
# Fase 1 (datos recién iniciados): verificaciones de Seguridad (1-8), auth, estudiantes, cursos y matrículas (1-9).
# Los pasos que requieren detener servicios se ejecutan en fase3-caidas.sh.
cd "$(dirname "$0")" && source lib.sh
E=../evidencias; mkdir -p $E
tokens

# ---------------- Seguridad ----------------
EVID=$E/01-seguridad.md; : > $EVID
nota "### Evidencias · Seguridad\n\nSobre servicios recién iniciados (local)."
paso 1 "GET /api/cursos/1 sin autorizar" "401 AUTH_HEADER_MISSING" GET $CUR/api/cursos/1 ""
paso 2 "GET /api/cursos/1 con un token inventado" "401 TOKEN_INVALID" GET $CUR/api/cursos/1 "eyJhbGciOiJIUzI1NiJ9.inventado.firmafalsa"
paso 3 "DOCENTE: POST /api/cursos" "403 AUTH_FORBIDDEN" POST $CUR/api/cursos "$T_DOC" \
  '{"codigo":"DOC-001","nombre":"Curso docente","creditos":3,"docenteResponsable":"Docente","cupoMaximo":10}'
paso 4 "ESTUDIANTE: GET /api/cursos" "200" GET $CUR/api/cursos "$T_EST"
paso 5 "ESTUDIANTE: GET /api/estudiantes (8082)" "403" GET $EST/api/estudiantes "$T_EST"
code=$(curl -s -o /tmp/.apidocs -w '%{http_code}' $CUR/v3/api-docs)
nota "#### Paso 6 — GET /v3/api-docs sin token\n\n**Esperado:** 200 · **Obtenido:** HTTP $code\n\n\`\`\`http\nGET $CUR/v3/api-docs\nAuthorization: (sin encabezado Authorization)\n\`\`\`\n\n\`\`\`json\n$(jq '{openapi, info, paths: (.paths|keys)}' /tmp/.apidocs)\n\`\`\`\n\n(Se muestra un extracto: versión, info y rutas documentadas.)"
echo "[6] GET /v3/api-docs -> $code"
paso 7 "ADMIN: POST /api/matriculas (8084) con {estudianteId:2, cursoId:2}" "201: el token se propagó a estudiantes y cursos" \
  POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":2,"cursoId":2}'
nota "#### Paso 8 — Consola H2 de auth (jdbc:h2:mem:authdb): SELECT * FROM usuarios\n\n**Esperado:** contraseñas con formato \`\$2a\$10\$…\` (BCrypt)\n\n$(h2sql $AUTH jdbc:h2:mem:authdb 'SELECT * FROM usuarios')\n"
nota "_El paso 9 (detener auth-service) se ejecuta al final; ver la sección de pruebas de caída._"

# ---------------- auth-service ----------------
EVID=$E/02-auth-service.md; : > $EVID
nota "### Evidencias · auth-service\n\n"
paso 1 "POST /auth/login con admin / admin123" "200 con token, username y role" POST $AUTH/auth/login "" '{"username":"admin","password":"admin123"}'
paso 2 "Login con contraseña incorrecta" "401 AUTH_INVALID_CREDENTIALS" POST $AUTH/auth/login "" '{"username":"admin","password":"mala"}'
nota "Comprobación adicional (usuario inexistente → mismo mensaje):"
paso 2b "Login con usuario inexistente" "401 AUTH_INVALID_CREDENTIALS, mismo mensaje que el paso 2" POST $AUTH/auth/login "" '{"username":"noexiste","password":"x"}'
paso 3 "Login con cuerpo {}" "400 VALIDATION_ERROR" POST $AUTH/auth/login "" '{}'
paso 4 "GET /auth/validate con token de admin" "200, valid: true, role: ADMIN" GET $AUTH/auth/validate "$T_ADMIN"
paso 5 "GET /auth/validate con token de estudiante" "estudianteId: 1" GET $AUTH/auth/validate "$T_EST"
paso 6 "GET /auth/validate sin autorizar" "401 AUTH_INVALID_TOKEN" GET $AUTH/auth/validate ""
# Se altera una letra del payload del token (el JWT ya no coincide con la firma)
ALT=$(python3 -I -c 'import sys;t=sys.argv[1];h,p,s=t.split(".");i=10;c="A" if p[i]!="A" else "B";print(h+"."+p[:i]+c+p[i+1:]+"."+s)' "$T_ADMIN")
paso 7 "GET /auth/validate con el token alterado (una letra del payload cambiada)" "401 AUTH_INVALID_TOKEN" GET $AUTH/auth/validate "$ALT"
nota "#### Paso 8 — Consola H2 (jdbc:h2:mem:authdb): SELECT * FROM usuarios\n\n**Esperado:** contraseñas cifradas y estudiante_id = 1 solo para el estudiante\n\n$(h2sql $AUTH jdbc:h2:mem:authdb 'SELECT ID, USERNAME, ROLE, ESTUDIANTE_ID, PASSWORD FROM usuarios')\n"
nota "Decodificación (sin secreto) del payload del token de estudiante — muestra que el contenido del JWT es legible:\n\n\`\`\`json\n$(echo "$T_EST" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq .)\n\`\`\`"

# ---------------- estudiantes-service ----------------
EVID=$E/03-estudiantes-service.md; : > $EVID
nota "### Evidencias · estudiantes-service\n\nToken de admin salvo que se indique."
paso 1 "GET /api/estudiantes?page=0&size=5" "200, 5 estudiantes y totalElements: 50" GET "$EST/api/estudiantes?page=0&size=5" "$T_ADMIN"
paso 2 "GET /api/estudiantes/999" "404 Estudiante no encontrado: 999" GET $EST/api/estudiantes/999 "$T_ADMIN"
paso 3 "POST estudiante Ana Ruiz" "201" POST $EST/api/estudiantes "$T_ADMIN" '{"nombre":"Ana","apellido":"Ruiz","email":"ana.ruiz@correo.edu","edad":20}'
paso 4 "Repetir el paso 3" "400 Ya existe un estudiante con el email…" POST $EST/api/estudiantes "$T_ADMIN" '{"nombre":"Ana","apellido":"Ruiz","email":"ana.ruiz@correo.edu","edad":20}'
paso 5 "POST con email no-es-correo y edad 0" "400 Error de validación con ambos campos" POST $EST/api/estudiantes "$T_ADMIN" '{"nombre":"Ana","apellido":"Ruiz","email":"no-es-correo","edad":0}'
E2=$(curl -s -H "Authorization: Bearer $T_ADMIN" $EST/api/estudiantes/2 | jq -c '.data | {nombre, apellido, edad}')
B6=$(echo "$E2" | jq -c '. + {email:"estudiante2@demoacademico.edu"}')
paso 6 "PUT /api/estudiantes/2 con el correo del estudiante 3" "400 Ya existe otro estudiante con el email…" PUT $EST/api/estudiantes/2 "$T_ADMIN" "$B6"
paso 7a "DOCENTE: GET /api/estudiantes/1" "200" GET $EST/api/estudiantes/1 "$T_DOC"
paso 7b "DOCENTE: POST /api/estudiantes" "403" POST $EST/api/estudiantes "$T_DOC" '{"nombre":"Doc","apellido":"Ente","email":"doc@correo.edu","edad":30}'
paso 8 "ESTUDIANTE: GET /api/estudiantes/1" "403" GET $EST/api/estudiantes/1 "$T_EST"
paso 9 "GET /api/estudiantes/abc" "400 Solicitud inválida… (no 401)" GET $EST/api/estudiantes/abc "$T_ADMIN"

# ---------------- cursos-service ----------------
EVID=$E/04-cursos-service.md; : > $EVID
nota "### Evidencias · cursos-service\n\nToken de admin salvo que se indique."
paso 1 "GET /api/cursos" "200 con los tres cursos semilla y su cupoMaximo" GET $CUR/api/cursos "$T_ADMIN"
ARQ='{"codigo":"ARQ-001","nombre":"Arquitectura","creditos":3,"docenteResponsable":"Docente","cupoMaximo":20}'
paso 2 "POST curso ARQ-001" "201" POST $CUR/api/cursos "$T_ADMIN" "$ARQ"
ARQ_ID=$(echo "$LAST_BODY" | jq .data.id)
paso 3 "Repetir el paso 2" "400 Ya existe un curso con el código: ARQ-001" POST $CUR/api/cursos "$T_ADMIN" "$ARQ"
paso 4 "POST con creditos: 11" "400 Los créditos máximos son 10" POST $CUR/api/cursos "$T_ADMIN" '{"codigo":"ARQ-002","nombre":"Arquitectura","creditos":11,"docenteResponsable":"Docente","cupoMaximo":20}'
C1=$(curl -s -H "Authorization: Bearer $T_ADMIN" $CUR/api/cursos/1 | jq -c '.data | del(.id) | .codigo="BD2-001"')
paso 5 "PUT /api/cursos/1 con codigo BD2-001" "400 Ya existe otro curso con el código: BD2-001" PUT $CUR/api/cursos/1 "$T_ADMIN" "$C1"
paso 6a "ESTUDIANTE: GET /api/cursos" "200" GET $CUR/api/cursos "$T_EST"
paso 6b "ESTUDIANTE: POST /api/cursos" "403" POST $CUR/api/cursos "$T_EST" '{"codigo":"EST-001","nombre":"X","creditos":3,"docenteResponsable":"Docente","cupoMaximo":20}'
paso 7 "DELETE /api/cursos/$ARQ_ID (curso creado en el paso 2)" "200 (no tiene matrículas)" DELETE $CUR/api/cursos/$ARQ_ID "$T_ADMIN"

# ---------------- matriculas-service ----------------
EVID=$E/05-matriculas-service.md; : > $EVID
nota "### Evidencias · matriculas-service\n\nToken de admin salvo que se indique. (La matrícula id 1 la creó el paso 7 de la guía de seguridad.)"
paso 1 "POST {estudianteId:1, cursoId:1}" "201, estado ACTIVA" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":1}'
MID=$(echo "$LAST_BODY" | jq .data.id)
paso 2 "Repetir el paso 1" "400 Ya existe una matrícula activa…" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":1}'
paso 3 "POST con estudianteId 999" "400 El estudiante indicado no existe" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":999,"cursoId":1}'
paso 4 "POST con cursoId 999" "400 El curso indicado no existe" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":999}'
paso 5 "POST con cuerpo {}" "400 Error de validación" POST $MAT/api/matriculas "$T_ADMIN" '{}'
paso 6 "PUT /api/matriculas/$MID/anular" "200, estado ANULADA" PUT $MAT/api/matriculas/$MID/anular "$T_ADMIN"
paso 7 "Repetir el paso 6" "400 La matrícula ya se encuentra anulada" PUT $MAT/api/matriculas/$MID/anular "$T_ADMIN"
paso 8 "Repetir el paso 1" "201: una matrícula anulada no bloquea una nueva" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":1}'
paso 9a "DOCENTE: GET /api/matriculas" "200" GET $MAT/api/matriculas "$T_DOC"
paso 9b "DOCENTE: POST /api/matriculas" "403" POST $MAT/api/matriculas "$T_DOC" '{"estudianteId":3,"cursoId":1}'
nota "_El paso 10 (detener estudiantes-service) se ejecuta al final; ver la sección de pruebas de caída._"
