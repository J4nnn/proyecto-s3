#!/usr/bin/env bash
# Arranca / detiene los servicios en local (java -jar sobre los .jar de target/).
# Uso: servicios.sh start [servicio...] | stop [servicio...] | status
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RUN=$ROOT/informe/.run
mkdir -p "$RUN"
TODOS="auth-service estudiantes-service cursos-service matriculas-service calificaciones-service"
declare -A PORT=([auth-service]=8081 [estudiantes-service]=8082 [cursos-service]=8083 [matriculas-service]=8084 [calificaciones-service]=8085)

cmd=$1; shift
svcs=${*:-$TODOS}

case $cmd in
  start)
    for s in $svcs; do
      jar=$(/bin/ls "$ROOT/$s"/target/*.jar | grep -v original | head -1)
      nohup java -jar "$jar" > "$RUN/$s.log" 2>&1 &
      echo $! > "$RUN/$s.pid"
    done
    for s in $svcs; do
      until curl -s -o /dev/null "http://localhost:${PORT[$s]}/v3/api-docs"; do sleep 1; done
      echo "$s listo en ${PORT[$s]}"
    done;;
  stop)
    for s in $svcs; do
      [ -f "$RUN/$s.pid" ] && kill "$(command cat "$RUN/$s.pid")" 2>/dev/null && echo "$s detenido"
      rm -f "$RUN/$s.pid"
    done
    for s in $svcs; do
      while curl -s -o /dev/null "http://localhost:${PORT[$s]}/v3/api-docs"; do sleep 1; done
    done;;
  status)
    for s in $TODOS; do
      curl -s -o /dev/null -w "$s %{http_code}\n" "http://localhost:${PORT[$s]}/v3/api-docs" || echo "$s caído"
    done;;
esac
