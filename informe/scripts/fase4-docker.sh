#!/usr/bin/env bash
# Fase 4: verificación de la guía "Docker, Swagger y pruebas" (requiere `docker compose up -d --build` previo).
cd "$(dirname "$0")" && source lib.sh
E=../evidencias; ROOT=$(cd ../.. && pwd)
EVID=$E/11-docker.md; : > $EVID
for p in 8081 8082 8083 8084 8085; do until curl -s -o /dev/null http://localhost:$p/v3/api-docs; do sleep 1; done; done

nota "### Evidencias · Docker, Swagger y pruebas\n\nCon Docker $(docker version --format '{{.Server.Version}}') (modo rootless) y $(docker compose version --short | sed 's/^/Compose v/')."
nota "#### Paso 1 — docker compose ps\n\n**Esperado:** cinco servicios en estado running\n\n\`\`\`\n$(cd $ROOT && docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.State}}\t{{.Status}}\t{{.Ports}}')\n\`\`\`"

for p in 1 2 3 4 5; do
  timeout 60 google-chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars --window-size=1280,900 \
    --virtual-time-budget=8000 --screenshot=$E/capturas/swagger-docker-808$p.png http://localhost:808$p/swagger-ui.html 2>/dev/null
done
nota "#### Paso 2 — Swagger de cada servicio (contenedores)\n\n$(for p in 1 2 3 4 5; do echo "- http://localhost:808$p/swagger-ui.html → HTTP $(curl -s -o /dev/null -w '%{http_code}' -L http://localhost:808$p/swagger-ui.html) · captura en la sección 12.1 del informe"; done)"

tokens
paso 3 "Login como admin (8081) y POST /api/matriculas (8084) con {estudianteId:1, cursoId:1}" "201: los servicios se comunican por la red de Docker" POST $MAT/api/matriculas "$T_ADMIN" '{"estudianteId":1,"cursoId":1}'
paso 3b "GET /api/matriculas antes del reinicio" "1 matrícula" GET $MAT/api/matriculas "$T_ADMIN"

nota "#### Paso 4 — docker compose logs matriculas-service\n\n**Esperado:** los registros de arranque y de la petición (extracto)\n\n\`\`\`\n$(cd $ROOT && docker compose logs --no-color matriculas-service | grep -E 'Starting|Tomcat started|Started Matriculas|Initializing|DispatcherServlet|Completed initialization' | sed -E 's/[[:space:]]+$//' | head -15)\n\`\`\`\n\nObservación: matriculas-service tiene \`show-sql: false\` y ningún componente registra las peticiones, así que la petición del paso 3 **no deja una línea propia** en el log. La única huella de tráfico es la inicialización perezosa del \`DispatcherServlet\` (\`Initializing Servlet 'dispatcherServlet'\`), que ocurre con la primera petición HTTP que recibe el contenedor (aquí, la sonda a \`/v3/api-docs\` que espera a que el servicio esté listo). Para tener trazas por petición habría que activar, por ejemplo, \`logging.level.org.springframework.web=DEBUG\` o los access logs de Tomcat."

(cd $ROOT && docker compose restart matriculas-service) >/dev/null 2>&1
until curl -s -o /dev/null http://localhost:8084/v3/api-docs; do sleep 1; done
paso 5 "docker compose restart matriculas-service y GET /api/matriculas" "Lista vacía: H2 en memoria pierde los datos al reiniciar" GET $MAT/api/matriculas "$T_ADMIN"

nota "#### Paso 6 — mvn test en los cinco servicios\n\n**Esperado:** 27 pruebas, 0 fallos\n\n\`\`\`\n$(for s in auth-service estudiantes-service cursos-service matriculas-service calificaciones-service; do echo "== $s"; grep -E 'Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+$|BUILD' $E/mvn-test/$s-resumen.txt; done)\n\`\`\`\n\nTotal: 4 + 3 + 4 + 8 + 8 = **27 pruebas, 0 fallos, 0 errores**."

nota "#### Paso 7 — docker compose down\n\n**Esperado:** los contenedores se detienen y se eliminan\n\n\`\`\`\n$(cd $ROOT && docker compose down 2>&1)\n\n\$ docker compose ps\n$(cd $ROOT && docker compose ps 2>&1)\n\`\`\`"
