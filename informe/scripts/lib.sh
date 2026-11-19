#!/usr/bin/env bash
# Utilidades para ejecutar las verificaciones de las guías y guardar evidencias en Markdown.
# Uso: source lib.sh; set EVID=archivo.md; luego llamar a `paso`.

AUTH=${AUTH:-http://localhost:8081}
EST=${EST:-http://localhost:8082}
CUR=${CUR:-http://localhost:8083}
MAT=${MAT:-http://localhost:8084}
CAL=${CAL:-http://localhost:8085}

# login usuario clave -> imprime el token
login() {
  curl -s -X POST "$AUTH/auth/login" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1\",\"password\":\"$2\"}" | jq -r .token
}

tokens() {
  T_ADMIN=$(login admin admin123)
  T_DOC=$(login docente docente123)
  T_EST=$(login estudiante estudiante123)
  export T_ADMIN T_DOC T_EST
}

# nombre legible del token para la evidencia (no se imprime el JWT completo)
quien() {
  case "$1" in
    "") echo "(sin encabezado Authorization)";;
    "$T_ADMIN") echo "Bearer <token de admin>";;
    "$T_DOC") echo "Bearer <token de docente>";;
    "$T_EST") echo "Bearer <token de estudiante>";;
    *) echo "Bearer ${1:0:25}…";;
  esac
}

# paso NUM "descripción" "resultado esperado" METODO URL TOKEN [CUERPO]
paso() {
  local num="$1" desc="$2" esperado="$3" metodo="$4" url="$5" token="$6" body="${7:-}"
  local args=(-s -o /tmp/.evid_body -w '%{http_code}' -X "$metodo" "$url")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  local code; code=$(curl "${args[@]}")
  LAST_CODE=$code
  LAST_BODY=$(command cat /tmp/.evid_body)
  {
    echo "#### Paso $num — $desc"
    echo
    echo "**Esperado:** $esperado · **Obtenido:** HTTP $code"
    echo
    echo '```http'
    echo "$metodo ${url}"
    echo "Authorization: $(quien "$token")"
    if [ -n "$body" ]; then echo "Content-Type: application/json"; echo; echo "$body"; fi
    echo '```'
    echo
    echo '```json'
    if echo "$LAST_BODY" | jq . >/dev/null 2>&1; then echo "$LAST_BODY" | jq .; else echo "$LAST_BODY"; fi
    echo '```'
    echo
  } >> "$EVID"
  echo "[$num] $metodo $url -> $code"
}

nota() { echo -e "$*\n" >> "$EVID"; }

# Ejecuta una consulta SQL en la consola H2 de un servicio y guarda la tabla resultante.
# h2sql BASE_URL JDBC_URL "SQL"
h2sql() {
  local base="$1" jdbc="$2" sql="$3" jar=/tmp/.h2cookies sid page
  rm -f $jar
  page=$(curl -s -c $jar -b $jar "$base/h2-console/")
  sid=$(echo "$page" | grep -o 'jsessionid=[a-z0-9]*' | head -1 | cut -d= -f2)
  curl -s -c $jar -b $jar "$base/h2-console/login.do?jsessionid=$sid" \
    --data-urlencode "language=es" --data-urlencode "setting=Generic H2 (Embedded)" \
    --data-urlencode "name=Generic H2 (Embedded)" --data-urlencode "driver=org.h2.Driver" \
    --data-urlencode "url=$jdbc" --data-urlencode "user=sa" --data-urlencode "password=" >/dev/null
  curl -s -c $jar -b $jar "$base/h2-console/query.do?jsessionid=$sid" --data-urlencode "sql=$sql" \
    | python3 -I -c '
import sys,re,html
t=sys.stdin.read()
m=re.search(r"(?s)<table class=.resultSet.*?</table>",t)
if not m: print(t[:2000]); sys.exit()
rows=re.findall(r"(?s)<tr>(.*?)</tr>",m.group(0))
for i,r in enumerate(rows):
    cells=[html.unescape(re.sub(r"<[^>]+>","",c)).strip() for c in re.findall(r"(?s)<t[hd][^>]*>(.*?)</t[hd]>",r)]
    print("| "+" | ".join(cells)+" |")
    if i==0: print("|"+"---|"*len(cells))
'
}
