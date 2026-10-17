"""
Pruebas de carga de Cheapest (Lab 4, microservicios) - matriz completa.

Ejecuta GET y POST en simultaneo (como los dos Thread Groups de JMeter) para
cada fila de la matriz del laboratorio, con sus repeticiones, y registra todo
en un archivo de log y en un CSV de resumen. Muestra una barra de progreso con
tiempo estimado restante.

Requiere una sola libreria externa: httpx
    pip install httpx

Ejemplos:
    # Matriz completa, distribucion 70/30 (GET/POST), contra API Gateway
    python scripts/load_test.py --base-url https://<API_ID>.execute-api.us-east-1.amazonaws.com/lab

    # Solo el smoke test y la operacion normal
    python scripts/load_test.py --base-url <URL> --tests smoke,normal

    # Ver el plan y la duracion estimada sin enviar nada
    python scripts/load_test.py --base-url <URL> --dry-run

    # Ensayo local barato (docker-compose) con la matriz reducida 100x
    python scripts/load_test.py --base-url http://localhost:3001 --user-scale 0.01 --time-scale 0.1 --reps 1 --pause 2

Salida (carpeta results/<fecha-hora>/):
    run.log      log completo: inicio/fin de cada corrida, metricas, tipos de error
    summary.csv  una fila por corrida y endpoint (se escribe corrida a corrida)
    raw_*.csv    peticiones individuales (solo con --raw)
"""

import argparse
import asyncio
import csv
import random
import sys
import time
import uuid
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

# IDs fijos del seed (libs/shared/database/src/seed.sql)
TIENDA_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
ZONA = "Zona Norte"
MONEDA_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
PRODUCTO_ID_FALLBACK = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

REQUEST_TIMEOUT_S = 10
TAIL_ESTIMATE_S = 5  # holgura estimada por corrida para terminar peticiones en vuelo

# clave, nombre, ramp-up (s), threads totales, loops (1 = una peticion por usuario;
# None = bucle sostenido durante --duration), repeticiones minimas
MATRIX = [
    ("smoke", "Smoke test", 5, 10, 1, 4),
    ("baja", "Baja carga", 10, 40, 1, 4),
    ("media", "Carga media", 20, 200, 1, 4),
    ("normal", "Operacion normal", 50, 900, 1, 8),
    ("alta", "Alta carga", 75, 3000, None, 4),
    ("muy-alta", "Muy alta carga", 100, 6000, None, 4),
    ("estres", "Estres", 150, 12000, None, 4),
    ("estres-fuerte", "Estres fuerte", 200, 24000, None, 8),
]


@dataclass
class RequestResult:
    timestamp_iso: str
    status_code: int
    latency_ms: float
    error: str = ""


# ----------------------------------------------------------------- utilidades


def fmt_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}h{m:02d}m" if h else f"{m}m{s:02d}s"


def percentile(sorted_values: list[float], pct: float) -> float:
    if not sorted_values:
        return 0.0
    k = (len(sorted_values) - 1) * (pct / 100)
    f = int(k)
    c = min(f + 1, len(sorted_values) - 1)
    if f == c:
        return sorted_values[f]
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


class Reporter:
    """Escribe en el log y en consola, y mantiene una linea de progreso al final."""

    def __init__(self, log_path: Path):
        self.log_file = open(log_path, "a", encoding="utf-8")
        self._status = ""

    def log(self, msg: str) -> None:
        line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
        self.log_file.write(line + "\n")
        self.log_file.flush()
        sys.stdout.write("\r" + " " * (len(self._status) + 2) + "\r" + line + "\n")
        sys.stdout.flush()
        self._status = ""

    def status(self, text: str) -> None:
        pad = max(0, len(self._status) - len(text))
        sys.stdout.write("\r" + text + " " * pad)
        sys.stdout.flush()
        self._status = text

    def close(self) -> None:
        self.log_file.close()


def bar(fraction: float, width: int = 24) -> str:
    fraction = min(max(fraction, 0.0), 1.0)
    filled = int(width * fraction)
    return "[" + "#" * filled + "-" * (width - filled) + "]"


# ----------------------------------------------------------------- peticiones


async def fetch_producto_ids(client: httpx.AsyncClient, base_url: str, n: int) -> list[str]:
    """Trae hasta n productoId reales; si falla, usa el producto fijo del seed."""
    try:
        resp = await client.get(f"{base_url}/logistics/productos", timeout=15)
        resp.raise_for_status()
        ids = [p["id"] for p in resp.json() if "id" in p]
        if len(ids) >= n:
            return random.sample(ids, n)
        if ids:
            return [random.choice(ids) for _ in range(n)]
    except Exception:
        pass
    return [PRODUCTO_ID_FALLBACK] * n


def build_pedido_body(producto_ids: list[str]) -> dict:
    """Pedido grande (25 items), igual que en los Labs 2 y 3."""
    items = [
        {
            "productoId": pid,
            "cantidad": random.randint(1, 10),
            "precioUnitario": round(random.uniform(1000, 50000), 2),
            "descuento": 0,
            "monedaId": MONEDA_ID,
        }
        for pid in producto_ids
    ]
    monto_total = sum(i["cantidad"] * i["precioUnitario"] for i in items)
    return {
        "identificador": f"PED-LOAD-{uuid.uuid4()}",
        "tiendaId": TIENDA_ID,
        "fechaHoraCreacion": datetime.now(timezone.utc).isoformat(),
        "montoTotal": round(monto_total, 2),
        "monedaId": MONEDA_ID,
        "estado": "creado",
        "items": items,
    }


async def send(client: httpx.AsyncClient, base_url: str, kind: str, producto_ids: list[str]) -> RequestResult:
    ts = datetime.now(timezone.utc).isoformat()
    start = time.perf_counter()
    try:
        if kind == "GET":
            resp = await client.get(
                f"{base_url}/logistics/tenderos/productos-disponibles",
                params={"tiendaId": TIENDA_ID, "zona": ZONA},
                timeout=REQUEST_TIMEOUT_S,
            )
        else:
            resp = await client.post(
                f"{base_url}/logistics/pedidos",
                json=build_pedido_body(producto_ids),
                headers={"Accept": "application/json"},
                timeout=REQUEST_TIMEOUT_S,
            )
        latency = (time.perf_counter() - start) * 1000
        error = "" if resp.status_code < 400 else f"HTTP {resp.status_code}"
        return RequestResult(ts, resp.status_code, latency, error)
    except httpx.TimeoutException:
        return RequestResult(ts, 0, (time.perf_counter() - start) * 1000, "timeout")
    except httpx.RequestError as exc:
        return RequestResult(
            ts, 0, (time.perf_counter() - start) * 1000, f"connection_error: {type(exc).__name__}"
        )


async def user(
    client, base_url, kind, offset, end_time, loops, producto_ids, results, run_start
) -> None:
    """Un usuario virtual: espera su turno del ramp-up y manda 1 peticion (loops=1)
    o peticiones en bucle hasta end_time (loops=None)."""
    delay = run_start + offset - time.perf_counter()
    if delay > 0:
        await asyncio.sleep(delay)
    if loops == 1:
        results.append(await send(client, base_url, kind, producto_ids))
        return
    while time.perf_counter() < end_time:
        results.append(await send(client, base_url, kind, producto_ids))


async def run_once(
    client, base_url, ramp, get_users, post_users, loops, duration, producto_ids, on_tick
) -> tuple[dict[str, list[RequestResult]], float]:
    results: dict[str, list[RequestResult]] = {"GET": [], "POST": []}
    run_start = time.perf_counter()
    end_time = run_start + ramp + (duration if loops is None else 0)
    tasks = []
    for kind, n in (("GET", get_users), ("POST", post_users)):
        for i in range(n):
            offset = ramp * i / n if n else 0
            tasks.append(
                asyncio.create_task(
                    user(client, base_url, kind, offset, end_time, loops, producto_ids, results[kind], run_start)
                )
            )

    async def ticker():
        while True:
            on_tick(time.perf_counter() - run_start, results)
            await asyncio.sleep(0.5)

    tick = asyncio.create_task(ticker())
    try:
        await asyncio.gather(*tasks)
    finally:
        tick.cancel()
    return results, time.perf_counter() - run_start


# ------------------------------------------------------------------- metricas


def summarize(results: list[RequestResult], wall: float) -> dict:
    n = len(results)
    lat = sorted(r.latency_ms for r in results)
    errors = [r for r in results if r.error]
    return {
        "n": n,
        "p99": percentile(lat, 99),
        "p95": percentile(lat, 95),
        "avg": (sum(lat) / n) if n else 0.0,
        "throughput": n / wall if wall > 0 else 0.0,
        "error_pct": (len(errors) / n * 100) if n else 0.0,
        "error_types": Counter(r.error for r in errors),
    }


SUMMARY_FIELDS = [
    "start_iso", "end_iso", "test", "rep", "threads_total", "get_threads", "post_threads",
    "ramp_s", "duration_s", "endpoint", "n", "p99_ms", "p95_ms", "avg_ms",
    "throughput_rps", "error_pct", "total_throughput_rps",
]


# ----------------------------------------------------------------------- main


def build_plan(args) -> list[dict]:
    selected = [k.strip() for k in args.tests.split(",")] if args.tests else None
    if selected:
        unknown = set(selected) - {m[0] for m in MATRIX}
        if unknown:
            sys.exit(f"Pruebas desconocidas: {', '.join(sorted(unknown))}. Validas: {', '.join(m[0] for m in MATRIX)}")
    plan = []
    for key, name, ramp, threads, loops, reps in MATRIX:
        if selected and key not in selected:
            continue
        threads = max(2, round(threads * args.user_scale))
        get_users = min(threads - 1, max(1, round(threads * args.get_pct / 100)))
        plan.append(
            {
                "key": key, "name": name, "ramp": max(1, round(ramp * args.time_scale)),
                "threads": threads, "get_users": get_users, "post_users": threads - get_users,
                "loops": loops, "duration": max(1, round(args.duration * args.time_scale)),
                "reps": args.reps if args.reps else reps,
            }
        )
    return plan


def planned_run_seconds(t: dict) -> float:
    return t["ramp"] + (t["duration"] if t["loops"] is None else 0) + TAIL_ESTIMATE_S


async def main_async(args) -> None:
    plan = build_plan(args)
    total_runs = sum(t["reps"] for t in plan)
    planned_total = sum(planned_run_seconds(t) * t["reps"] + args.pause * t["reps"] for t in plan) - args.pause

    if args.dry_run:
        print(f"Base URL: {args.base_url}\nDistribucion GET/POST: {args.get_pct}/{100 - args.get_pct}\n")
        print(f"{'Prueba':<18}{'Ramp':>6}{'Threads':>9}{'GET':>7}{'POST':>7}{'Loops':>7}{'Reps':>6}{'min/rep':>9}")
        for t in plan:
            print(
                f"{t['name']:<18}{t['ramp']:>5}s{t['threads']:>9}{t['get_users']:>7}{t['post_users']:>7}"
                f"{(t['loops'] or 'N/A'):>7}{t['reps']:>6}{planned_run_seconds(t) / 60:>9.1f}"
            )
        print(f"\nCorridas: {total_runs}. Duracion estimada total (con pausas de {args.pause}s): {fmt_duration(planned_total)}")
        return

    out_dir = Path(args.out_dir) / datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    rep = Reporter(out_dir / "run.log")
    summary_path = out_dir / "summary.csv"
    with open(summary_path, "w", newline="", encoding="utf-8") as f:
        csv.DictWriter(f, SUMMARY_FIELDS).writeheader()

    rep.log(f"Carpeta de resultados: {out_dir}")
    rep.log(f"Base URL: {args.base_url} | GET/POST: {args.get_pct}/{100 - args.get_pct} | "
            f"corridas: {total_runs} | duracion estimada: {fmt_duration(planned_total)}")
    if args.user_scale != 1 or args.time_scale != 1:
        rep.log(f"AVISO: matriz reducida (user-scale={args.user_scale}, time-scale={args.time_scale}); no es valida como entrega.")

    max_users = max(t["threads"] for t in plan)
    limits = httpx.Limits(max_connections=max_users + 50, max_keepalive_connections=max_users)
    done_seconds = 0.0
    run_idx = 0
    global_start = time.perf_counter()

    async with httpx.AsyncClient(limits=limits) as client:
        producto_ids = await fetch_producto_ids(client, args.base_url, 25)
        rep.log(f"Productos para los POST: {len(set(producto_ids))} distintos")
        try:
            for t in plan:
                for r in range(1, t["reps"] + 1):
                    run_idx += 1
                    label = f"{t['name']} rep {r}/{t['reps']}"
                    run_plan_s = planned_run_seconds(t)
                    start_iso = datetime.now(timezone.utc).isoformat()
                    rep.log(f"INICIO {label} | threads={t['threads']} (GET {t['get_users']} / POST {t['post_users']}) "
                            f"ramp={t['ramp']}s loops={t['loops'] or 'N/A'}")

                    def on_tick(elapsed, results, label=label, run_plan_s=run_plan_s, base=done_seconds, idx=run_idx):
                        frac = (base + min(elapsed, run_plan_s)) / planned_total if planned_total else 1
                        remaining = max(0, planned_total - base - min(elapsed, run_plan_s))
                        get_r, post_r = results["GET"], results["POST"]
                        get_e = sum(1 for x in get_r if x.error)
                        post_e = sum(1 for x in post_r if x.error)
                        rep.status(
                            f"{bar(frac)} {frac * 100:5.1f}% | {idx}/{total_runs} {label} {elapsed:4.0f}s | "
                            f"GET {len(get_r)}/{get_e}err POST {len(post_r)}/{post_e}err | ETA {fmt_duration(remaining)}"
                        )

                    results, wall = await run_once(
                        client, args.base_url, t["ramp"], t["get_users"], t["post_users"],
                        t["loops"], t["duration"], producto_ids, on_tick,
                    )
                    end_iso = datetime.now(timezone.utc).isoformat()
                    stats = {k: summarize(results[k], wall) for k in ("GET", "POST")}
                    total_thr = (stats["GET"]["n"] + stats["POST"]["n"]) / wall if wall > 0 else 0.0

                    rep.log(f"FIN    {label} | duracion real {wall:.1f}s | throughput total {total_thr:.2f} req/s")
                    with open(summary_path, "a", newline="", encoding="utf-8") as f:
                        writer = csv.DictWriter(f, SUMMARY_FIELDS)
                        for k in ("GET", "POST"):
                            s = stats[k]
                            rep.log(
                                f"       {k:<4} n={s['n']} p99={s['p99']:.0f}ms p95={s['p95']:.0f}ms "
                                f"avg={s['avg']:.0f}ms thr={s['throughput']:.2f}/s err={s['error_pct']:.2f}%"
                                + (f" errores={dict(s['error_types'])}" if s["error_types"] else "")
                            )
                            writer.writerow({
                                "start_iso": start_iso, "end_iso": end_iso, "test": t["name"], "rep": r,
                                "threads_total": t["threads"], "get_threads": t["get_users"],
                                "post_threads": t["post_users"], "ramp_s": t["ramp"],
                                "duration_s": f"{wall:.1f}", "endpoint": k, "n": s["n"],
                                "p99_ms": f"{s['p99']:.1f}", "p95_ms": f"{s['p95']:.1f}", "avg_ms": f"{s['avg']:.1f}",
                                "throughput_rps": f"{s['throughput']:.2f}", "error_pct": f"{s['error_pct']:.2f}",
                                "total_throughput_rps": f"{total_thr:.2f}",
                            })
                    # Cumplimiento de umbrales (informativo)
                    req1 = stats["POST"]["p99"] < 2000
                    req2 = stats["GET"]["error_pct"] <= 10
                    req3 = total_thr >= 83.3 and stats["POST"]["error_pct"] <= 10
                    rep.log(f"       ASR: REQ1 p99 POST<2000ms={'OK' if req1 else 'NO'} | "
                            f"REQ2 err GET<=10%={'OK' if req2 else 'NO'} | "
                            f"REQ3 thr>=83.3 y err POST<=10%={'OK' if req3 else 'NO'}")

                    if args.raw:
                        with open(out_dir / f"raw_{t['key']}_rep{r}.csv", "w", newline="", encoding="utf-8") as f:
                            w = csv.writer(f)
                            w.writerow(["endpoint", "timestamp_iso", "status_code", "latency_ms", "error"])
                            for k in ("GET", "POST"):
                                for x in results[k]:
                                    w.writerow([k, x.timestamp_iso, x.status_code, f"{x.latency_ms:.2f}", x.error])

                    done_seconds += run_plan_s
                    if run_idx < total_runs:
                        for left in range(int(args.pause), 0, -1):
                            frac = (done_seconds + (args.pause - left)) / planned_total if planned_total else 1
                            rep.status(
                                f"{bar(frac)} {frac * 100:5.1f}% | pausa {left:3d}s antes de la siguiente corrida | "
                                f"ETA {fmt_duration(planned_total - done_seconds - (args.pause - left))}"
                            )
                            await asyncio.sleep(1)
                        done_seconds += args.pause
        finally:
            rep.log(f"Terminado/interrumpido tras {fmt_duration(time.perf_counter() - global_start)}. "
                    f"Resumen: {summary_path}")
            rep.close()


def main() -> None:
    p = argparse.ArgumentParser(description="Matriz de pruebas de carga de Cheapest (GET + POST simultaneos)")
    p.add_argument("--base-url", required=True,
                   help="URL base, p. ej. https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab (sin / final)")
    p.add_argument("--get-pct", type=int, default=70, help="%% de threads para GET (el resto es POST). Default 70")
    p.add_argument("--tests", help=f"Claves separadas por coma. Validas: {', '.join(m[0] for m in MATRIX)}. Default: todas")
    p.add_argument("--reps", type=int, help="Forzar el numero de repeticiones de cada prueba (default: minimo de la matriz)")
    p.add_argument("--duration", type=int, default=60, help="Segundos sostenidos tras el ramp-up en filas sin loops. Default 60")
    p.add_argument("--pause", type=int, default=90, help="Segundos de espera entre corridas. Default 90")
    p.add_argument("--out-dir", default="results", help="Carpeta base de resultados. Default results/")
    p.add_argument("--raw", action="store_true", help="Guardar tambien cada peticion individual (archivos grandes)")
    p.add_argument("--dry-run", action="store_true", help="Mostrar el plan y la duracion estimada sin enviar trafico")
    p.add_argument("--user-scale", type=float, default=1.0, help="Multiplica los threads (ensayos locales)")
    p.add_argument("--time-scale", type=float, default=1.0, help="Multiplica ramp-up y duracion (ensayos locales)")
    args = p.parse_args()
    args.base_url = args.base_url.rstrip("/")
    if not 1 <= args.get_pct <= 99:
        sys.exit("--get-pct debe estar entre 1 y 99")

    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        print("\nInterrumpido por el usuario. Lo ya medido quedo en summary.csv y run.log.")


if __name__ == "__main__":
    main()
