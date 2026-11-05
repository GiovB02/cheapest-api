# Resultados consolidados - Lab 5 (generado automaticamente desde lab5-pruebas/resultados)

Region us-east-2. Matriz sobre POST /ventas/ventas. Inventario degradado 5 s (FAULT_DELAY_MS=5000) durante 10 min desde T0.

## Ronda 1 - Linea base (sin sidecar)

| Hilos | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % | 201 | con pending | 429 % |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 | 10 | 5657 | 5403 | 3.33 | 0 | 50 | 0 | 0 |
| 200 | 20 | 15355 | 15313 | 5.53 | 0.5 | 199 | 0 | 0 |
| 500 | 50 | 15494 | 15317 | 7.27 | 0.4 | 498 | 0 | 0 |
| 1500 | 75 | 15382 | 15309 | 16.2 | 0.13 | 1498 | 0 | 0 |

- CloudWatch RequestCount a Inventario (T0..T0+14 min): **6813**; ventas 201 (matriz + sonda): **2356**; llamadas de disponibilidad: **4457**; factor de amplificacion vs linea base: **1**
- Sonda: 111 peticiones, 111 con 201, 0 con pending_stock_confirmation; latencia sonda min/max: 0.302596 / 20.388262 s

## Ronda 2 - Sidecar: solo reintentos

| Hilos | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % | 201 | con pending | 429 % |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 | 10 | 5662 | 5350 | 3.33 | 0 | 50 | 42 | 0 |
| 200 | 20 | 15347 | 15306 | 5.7 | 0 | 200 | 187 | 0 |
| 500 | 50 | 15321 | 15301 | 7.23 | 0.2 | 499 | 436 | 0 |
| 1500 | 75 | 15387 | 15300 | 16.15 | 0.2 | 1497 | 1360 | 0 |

- CloudWatch RequestCount a Inventario (T0..T0+14 min): **6662**; ventas 201 (matriz + sonda): **2365**; llamadas de disponibilidad: **4297**; factor de amplificacion vs linea base: **0.96**
- Sonda: 119 peticiones, 119 con 201, 59 con pending_stock_confirmation; latencia sonda min/max: 0.298095 / 5.553935 s

## Ronda 3 - Sidecar: retry + circuit breaker (con healthy_panic_threshold=0)

| Hilos | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % | 201 | con pending | 429 % |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 | 10 | 5718 | 5418 | 3.57 | 0 | 50 | 42 | 0 |
| 200 | 20 | 10376 | 10302 | 6.72 | 0 | 200 | 194 | 0 |
| 500 | 50 | 11290 | 10304 | 8.34 | 0.2 | 499 | 486 | 0 |
| 1500 | 75 | 15304 | 10306 | 17.36 | 0.6 | 1491 | 1465 | 0 |

- CloudWatch RequestCount a Inventario (T0..T0+14 min): **5882**; ventas 201 (matriz + sonda): **2404**; llamadas de disponibilidad: **3478**; factor de amplificacion vs linea base: **0.78**
- Sonda: 164 peticiones, 164 con 201, 105 con pending_stock_confirmation; latencia sonda min/max: 0.292271 / 5.664046 s

## Ronda 4 - Sidecar completo + rate limiting API Gateway (100 req/s, burst 200)

| Hilos | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % | 201 | con pending | 429 % |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 | 10 | 5702 | 5464 | 3.33 | 0 | 50 | 22 | 0 |
| 200 | 20 | 15298 | 10310 | 7.36 | 0 | 200 | 133 | 0 |
| 500 | 50 | 15419 | 15313 | 7.71 | 0 | 500 | 283 | 0 |
| 1500 | 75 | 15389 | 10543 | 16.22 | 0.53 | 1492 | 1360 | 0 |

- CloudWatch RequestCount a Inventario (T0..T0+14 min): **6650**; ventas 201 (matriz + sonda): **2386**; llamadas de disponibilidad: **4264**; factor de amplificacion vs linea base: **0.96**
- Sonda: 144 peticiones, 144 con 201, 56 con pending_stock_confirmation; latencia sonda min/max: 0.305364 / 6.529499 s

## Ronda 4 - prueba de saturacion (150 hilos, 120 s, objetivo 300 req/s)

- Peticiones: 14198; throughput alcanzado: 117.3 req/s (el objetivo de 300 no se alcanzo por la capacidad del generador de carga); 201: 10988; **429: 22.59 %**; p99: 2257 ms

## Costo del Outbox en latencia (500 hilos, ramp-up 50 s, Inventario sano, tacticas combinadas)

- p99: 10374 ms; p95: 10317 ms; p50: 310 ms; throughput: 7.87 req/s; error: 0.4 %; 201: 498
- Referencia Ronda 4 (500 hilos, con Inventario degradado): p99 15419 ms. OJO: no es una comparacion limpia (ver notas).

## Ronda 5 (local, Docker) - ultima ejecucion registrada en la terminal

- Escenario 1 (sin idempotencia): la misma peticion enviada 2 veces bajo el stock en 2 (99 -> 97).
- Escenario 2 (Inventario apagado): 3 ventas 201 con pending_stock_confirmation; stock sin cambio (97); 3 filas PENDING en outbox_http_calls con attempts creciendo.
- Fase 2: reconciliacion PENDING -> DELIVERED en 2,9 s desde T_rec (umbral 30 s); stock 97 -> 94 (exactamente 3); reenvio con la misma X-Idempotency-Key -> HTTP 409, stock sin cambio (94).

## Notas y hallazgos para el analisis

- Primer intento de la Ronda 3: el circuito NO abrio (0 respuestas 503 UH). Causa: Envoy entra en modo panico con <50 % de hosts sanos y sigue enviando al host expulsado. Se anadio common_lb_config.healthy_panic_threshold=0. Datos en ronda3_intento1_circuito_no_abre/.
- El stock inicial es de 100 unidades; al agotarse, el Outbox recibe 400 de Inventario y reintenta sin parar (~300 peticiones/min de fondo tras cada carga). Eso infla el RequestCount a Inventario en todas las rondas.
- ASR-1 (p99 < 3000 ms): no se cumple con timeout=5s, porque las primeras peticiones esperan el timeout completo antes de que el circuito abra y el p99 incluye todas.
- Prueba del costo del Outbox: con Inventario sano el p99 fue alto (cola de ~10 s en ~5 % de peticiones) y hubo 2 ConnectTimeout; no hay una linea base 'sin Outbox' en el codigo para comparar. Resultado no concluyente: documentar como limitacion.

