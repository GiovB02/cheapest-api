// Resume un .jtl (CSV) de JMeter: p95, p99, error %, throughput, PENDING y 429.
// Uso: node lab5-pruebas/resumen.js lab5-pruebas/resultados/archivo.jtl
const fs = require('fs');

const file = process.argv[2];
if (!file) {
  console.error('Uso: node resumen.js archivo.jtl');
  process.exit(1);
}

// Lector CSV con comillas: los mensajes de error de JMeter traen comas y saltos
// de linea dentro de campos entre comillas.
function parseCsv(text) {
  const out = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field);
      field = '';
      if (row.length > 1 || row[0] !== '') out.push(row);
      row = [];
    } else {
      field += ch;
    }
  }
  if (field !== '' || row.length) {
    row.push(field);
    out.push(row);
  }
  return out;
}

const table = parseCsv(fs.readFileSync(file, 'utf8'));
const head = table[0];
const ix = (name) => head.indexOf(name);

const rows = table.slice(1).map((c) => {
  return {
    ts: Number(c[ix('timeStamp')]),
    el: Number(c[ix('elapsed')]),
    code: c[ix('responseCode')],
    msg: c[ix('responseMessage')],
    ok: c[ix('success')] === 'true',
  };
});

const n = rows.length;
const sorted = rows.map((r) => r.el).sort((a, b) => a - b);
const pct = (p) => sorted[Math.min(n - 1, Math.ceil((p / 100) * n) - 1)];
const t0 = Math.min(...rows.map((r) => r.ts));
const t1 = Math.max(...rows.map((r) => r.ts + r.el));

const codes = {};
rows.forEach((r) => {
  codes[r.code] = (codes[r.code] || 0) + 1;
});

const count = (fn) => rows.filter(fn).length;

console.log(
  JSON.stringify(
    {
      archivo: file,
      peticiones: n,
      p50_ms: pct(50),
      p95_ms: pct(95),
      p99_ms: pct(99),
      max_ms: sorted[n - 1],
      error_pct: Number(((count((r) => !r.ok) / n) * 100).toFixed(2)),
      throughput_rps: Number((n / ((t1 - t0) / 1000)).toFixed(2)),
      respuestas_201: count((r) => r.code === '201'),
      con_pending_stock_confirmation: count((r) => r.msg === 'PENDING'),
      pct_429: Number(((count((r) => r.code === '429') / n) * 100).toFixed(2)),
      codigos: codes,
      inicio: new Date(t0).toISOString(),
      fin: new Date(t1).toISOString(),
    },
    null,
    2,
  ),
);
