// Ejecuta una consulta de CloudWatch Logs Insights por CLI y la imprime como tabla.
//   node lab5-pruebas/logs-insights.js --desde=2026-10-25T16:36:00Z --hasta=2026-10-25T16:52:00Z [--modo=resumen|tiempo]
// Grupo: /ecs/Cheapest-ventas-sidecar. "resumen" cuenta por codigo/flag; "tiempo" por tramos de 30 s.
const { execFileSync } = require('child_process');

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, '').split('=')));
const REGION = 'us-east-2';
const group = args.grupo || '/ecs/Cheapest-ventas-sidecar';
const parse = 'parse @message /HTTP\\/1\\.1" (?<code>\\d{3}) (?<flags>\\S+) / | filter ispresent(code)';
const query =
  args.modo === 'tiempo'
    ? `${parse} | stats count(*) as peticiones by bin(30s) as ventana, code, flags | sort by ventana asc`
    : `${parse} | stats count(*) as n by code, flags | sort by n desc`;

const aws = (a) =>
  execFileSync('aws', [...a, '--region', REGION, '--output', 'json'], { encoding: 'utf8', maxBuffer: 1 << 26 });

const start = Math.floor(new Date(args.desde).getTime() / 1000);
const end = Math.floor(new Date(args.hasta).getTime() / 1000);
const { queryId } = JSON.parse(
  aws(['logs', 'start-query', '--log-group-name', group, '--start-time', String(start), '--end-time', String(end), '--query-string', query]),
);

let res;
for (let i = 0; i < 30; i++) {
  res = JSON.parse(aws(['logs', 'get-query-results', '--query-id', queryId]));
  if (res.status === 'Complete') break;
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000);
}
const rows = (res.results || []).map((r) => Object.fromEntries(r.filter((f) => f.field !== '@ptr').map((f) => [f.field, f.value])));
console.table(rows);
console.log(`${rows.length} filas, estado: ${res.status}`);
