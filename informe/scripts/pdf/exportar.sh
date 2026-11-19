#!/usr/bin/env bash
# Regenera informe/INFORME.md y lo exporta a informe/INFORME.pdf.
# Requiere Node.js y Google Chrome. Uso: informe/scripts/pdf/exportar.sh
set -e
cd "$(dirname "$0")"
INF=$(cd ../.. && pwd)
[ -d node_modules ] || npm install --silent markdown-it@14.1.0 markdown-it-anchor@9.2.0
python3 -I ../construir_informe.py
node render.mjs "$INF" "$PWD/informe.html"
google-chrome --headless=new --disable-gpu --no-sandbox --allow-file-access-from-files \
  --run-all-compositor-stages-before-draw --virtual-time-budget=20000 --no-pdf-header-footer \
  --print-to-pdf="$INF/INFORME.pdf" "file://$PWD/informe.html" 2>/dev/null
rm -f informe.html
echo "PDF generado: $INF/INFORME.pdf"
