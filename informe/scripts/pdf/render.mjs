// Convierte informe/INFORME.md (incluye el Anexo B de evidencias) en un HTML listo para imprimir a PDF.
// Uso: node render.mjs <dir_informe> <salida.html>
import fs from 'node:fs';
import path from 'node:path';
import MarkdownIt from 'markdown-it';
import anchor from 'markdown-it-anchor';

const [dir, out] = process.argv.slice(2);
const slug = (s) => s.trim().toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s/g, '-');

const md = new MarkdownIt({ html: true, linkify: false, typographer: false })
  .use(anchor, { slugify: slug });

// Bloques mermaid -> <pre class="mermaid"> para que mermaid.js los dibuje
const fence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, idx, opts, env, self) => {
  const t = tokens[idx];
  if (t.info.trim() === 'mermaid') {
    // En papel, el diagrama de servicios cabe mejor de arriba hacia abajo
    const src = t.content.replace(/^flowchart LR/m, 'flowchart TB');
    return `<pre class="mermaid">${md.utils.escapeHtml(src)}</pre>\n`;
  }
  if (!t.info.trim()) {
    const ancho = Math.max(...t.content.split('\n').map((l) => [...l].length));
    if (ancho <= 125) return `<pre class="ascii">${md.utils.escapeHtml(t.content)}</pre>\n`;
  }
  return fence(tokens, idx, opts, env, self);
};

const informe = fs.readFileSync(path.join(dir, 'INFORME.md'), 'utf8');

let body = md.render(informe);
// Imágenes relativas -> rutas absolutas file://
body = body.replace(/src="((?:evidencias|diagramas)\/[^"]+)"/g, (_, p) => `src="file://${path.join(dir, p)}"`);
// Marca de verificación en las tablas
body = body.replace(/✅/g, '<span class="ok">✔</span>').replace(/❌/g, '<span class="ko">✘</span>');

const css = fs.readFileSync(new URL('./estilo.css', import.meta.url), 'utf8');
const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Informe de análisis · Proyecto final guiado</title>
<style>${css}</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
</head><body>${body}
<script>
mermaid.initialize({ startOnLoad: false, theme: 'neutral', themeVariables: { fontSize: '22px' }, flowchart: { htmlLabels: true, useMaxWidth: true, nodeSpacing: 30, rankSpacing: 45 }, sequence: { useMaxWidth: true } });
mermaid.run({ querySelector: '.mermaid' }).then(() => { document.body.dataset.listo = '1'; });
</script></body></html>`;
fs.writeFileSync(out, html);
console.log('HTML:', out);
