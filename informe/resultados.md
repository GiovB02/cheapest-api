# Lab 4 — Resultados (borrador de trabajo)

**Distribución GET/POST usada:** 70/30 (riesgo real). Se repiten con 30/70 las filas críticas.
**URL de invocación:** `https://zp5ccgfhs8.execute-api.us-east-1.amazonaws.com/lab`
**Herramienta:** JMeter para Smoke, Baja, Media y Operación normal; script Python (`scripts/load_test.py`) para Alta, Muy alta, Estrés y Estrés fuerte.
**Configuración base:** 1 tarea Fargate (0,5 vCPU / 1 GB) por servicio, RDS db.t3.micro, ALB, API Gateway HTTP.

Umbrales: REQ1 p99 POST < 2000 ms · REQ2 error GET ≤ 10 % · REQ3 throughput total ≥ 83,3 req/s y error POST ≤ 10 %.

## Tabla A — GET (escenario simultáneo)

| Test | Ramp-Up | Threads totales | Herramienta | # Rep | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| Smoke test | 5s | 10 | JMeter | 1 | 479 | 479 | 1,5 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 2 | 543 | 543 | 1,5 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 3 | 444 | 444 | 1,5 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 4 | 489 | 489 | 1,5 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 1 | 458 | 430 | 2,8 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 2 | 509 | 376 | 2,8 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 3 | 431 | 411 | 2,8 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 4 | 430 | 366 | 2,8 | 0,00 |
| Carga media | 20s | 200 | JMeter | 1 | 640 | 486 | 6,8 | 0,00 |
| Carga media | 20s | 200 | JMeter | 2 | 477 | 386 | 6,9 | 0,00 |
| Carga media | 20s | 200 | JMeter | 3 | 443 | 394 | 6,9 | 0,00 |
| Carga media | 20s | 200 | JMeter | 4 | 439 | 375 | 6,9 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 1 | 420 | 371 | 12,7 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 2 | 878 | 490 | 12,8 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 3 | 500 | 388 | 12,7 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 4 | 530 | 376 | 12,8 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 5 | 510 | 421 | 12,8 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 6 | 665 | 373 | 12,8 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 7 | 778 | 480 | 12,8 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 8 | 422 | 370 | 12,7 | 0,00 |
| Alta carga | 75s | 3000 | Python | 1 | 145537 | 114502 | 35,30 | 0,00 |
| Alta carga | 75s | 3000 | Python | 2 | 168808 | 139598 | 27,67 | 4,12 |
| Alta carga | 75s | 3000 | Python | 3 | 178899 | 149399 | 24,61 | 24,69 |
| Alta carga | 75s | 3000 | Python | 4 | 186854 | 158441 | 23,35 | 28,82 |
| Muy alta carga | 100s | 6000 | Python | 1 | 304846 | 270371 | 21,44 | 39,18 |
| Muy alta carga | 100s | 6000 | Python | 2 | 298869 | 265409 | 21,50 | 50,58 |
| Muy alta carga | 100s | 6000 | Python | 3 | 302510 | 266574 | 21,56 | 57,34 |
| Muy alta carga | 100s | 6000 | Python | 4 | 296866 | 260663 | 21,94 | 62,90 |
| Estrés | 150s | 12000 | Python | 1 | 553596 | 504966 | 19,51 | 60,36 |
| Estrés | 150s | 12000 | Python | 2 | 541284 | 494108 | 19,96 | 66,47 |
| Estrés | 150s | 12000 | Python | 3 | 530269 | 485070 | 20,36 | 70,21 |
| Estrés | 150s | 12000 | Python | 4 | 542915 | 496532 | 19,72 | 72,01 |
| Estrés fuerte | 200s | 24000 | Python | 1 | 1185864 | 1110611 | 16,26 | 64,18 |
| Estrés fuerte | 200s | 24000 | Python | 2 | 1116566 | 1047109 | 17,16 | 69,84 |
| Estrés fuerte | 200s | 24000 | Python | 3 | 1070678 | 1002556 | 17,64 | 73,70 |
| Estrés fuerte | 200s | 24000 | Python | 4 | 1063628 | 989289 | 17,78 | 75,48 |
| Estrés fuerte | 200s | 24000 | Python | 5 | 1077037 | 994009 | 18,31 | 77,90 |
| Estrés fuerte | 200s | 24000 | Python | 6 | 1080227 | 1011715 | 17,76 | 77,75 |
| Estrés fuerte | 200s | 24000 | Python | 7 | 1162213 | 1089374 | 16,18 | 76,89 |
| Estrés fuerte | 200s | 24000 | Python | 8 | 1086065 | 1014250 | 17,44 | 79,38 |

## Tabla B — POST (escenario simultáneo)

| Test | Ramp-Up | Threads totales | Herramienta | # Rep | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| Smoke test | 5s | 10 | JMeter | 1 | 505 | 505 | 0,85 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 2 | 543 | 543 | 0,86 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 3 | 377 | 377 | 0,86 | 0,00 |
| Smoke test | 5s | 10 | JMeter | 4 | 507 | 507 | 0,87 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 1 | 476 | 197 | 1,3 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 2 | 508 | 178 | 1,3 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 3 | 448 | 194 | 1,3 | 0,00 |
| Baja carga | 10s | 40 | JMeter | 4 | 456 | 148 | 1,3 | 0,00 |
| Carga media | 20s | 200 | JMeter | 1 | 362 | 242 | 3,0 | 0,00 |
| Carga media | 20s | 200 | JMeter | 2 | 354 | 183 | 3,0 | 0,00 |
| Carga media | 20s | 200 | JMeter | 3 | 385 | 362 | 3,0 | 0,00 |
| Carga media | 20s | 200 | JMeter | 4 | 475 | 312 | 3,0 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 1 | 200 | 171 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 2 | 491 | 259 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 3 | 324 | 209 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 4 | 336 | 197 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 5 | 548 | 249 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 6 | 332 | 182 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 7 | 636 | 264 | 3,4 | 0,00 |
| Operación normal | 50s | 900 | JMeter | 8 | 350 | 187 | 3,4 | 0,00 |
| Alta carga | 75s | 3000 | Python | 1 | 145581 | 116962 | 14,65 | 0,00 |
| Alta carga | 75s | 3000 | Python | 2 | 173920 | 147874 | 10,71 | 15,86 |
| Alta carga | 75s | 3000 | Python | 3 | 186617 | 153406 | 9,22 | 47,27 |
| Alta carga | 75s | 3000 | Python | 4 | 185291 | 162384 | 9,17 | 48,34 |
| Muy alta carga | 100s | 6000 | Python | 1 | 301740 | 274654 | 8,70 | 55,18 |
| Muy alta carga | 100s | 6000 | Python | 2 | 302439 | 267714 | 8,89 | 63,69 |
| Muy alta carga | 100s | 6000 | Python | 3 | 302595 | 266880 | 9,07 | 74,14 |
| Muy alta carga | 100s | 6000 | Python | 4 | 293727 | 264158 | 9,01 | 80,31 |
| Estrés | 150s | 12000 | Python | 1 | 552948 | 503370 | 8,28 | 73,84 |
| Estrés | 150s | 12000 | Python | 2 | 542422 | 494191 | 8,31 | 79,80 |
| Estrés | 150s | 12000 | Python | 3 | 534083 | 486083 | 8,62 | 82,10 |
| Estrés | 150s | 12000 | Python | 4 | 543295 | 493886 | 8,41 | 81,86 |
| Estrés fuerte | 200s | 24000 | Python | 1 | 1185409 | 1117300 | 6,91 | 79,53 |
| Estrés fuerte | 200s | 24000 | Python | 2 | 1115296 | 1045644 | 7,31 | 83,22 |
| Estrés fuerte | 200s | 24000 | Python | 3 | 1073745 | 1003103 | 7,56 | 85,96 |
| Estrés fuerte | 200s | 24000 | Python | 4 | 1071737 | 995695 | 7,58 | 87,16 |
| Estrés fuerte | 200s | 24000 | Python | 5 | 1089254 | 1003229 | 7,80 | 90,20 |
| Estrés fuerte | 200s | 24000 | Python | 6 | 1081661 | 1009788 | 7,52 | 89,70 |
| Estrés fuerte | 200s | 24000 | Python | 7 | 1163283 | 1091024 | 6,92 | 87,99 |
| Estrés fuerte | 200s | 24000 | Python | 8 | 1093734 | 1017530 | 7,44 | 91,83 |

## Tabla C — Corrida con escalamiento

| Servicio escalado | Desired count | Test | Endpoint | # Rep | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| Logística | 2 | Operación normal | GET | 1 | 11547 | 10933 | 11,1 | 66,03 |
| Logística | 2 | Operación normal | POST | 1 | 18185 | 14948 | 4,8 | 95,56 |
| Logística | 2 | Operación normal | GET | 2 | 10266 | 9939 | 11,1 | 62,22 |
| Logística | 2 | Operación normal | POST | 2 | 23221 | 19364 | 4,8 | 85,93 |
| Logística | 2 | Alta carga | GET | 1 | 164665 | 135931 | 21,88 | 88,63 |
| Logística | 2 | Alta carga | POST | 1 | 158181 | 136207 | 9,22 | 92,68 |
| Logística | 2 | Alta carga | GET | 2 | 156676 | 129682 | 22,26 | 86,89 |
| Logística | 2 | Alta carga | POST | 2 | 152841 | 126172 | 9,50 | 95,60 |

> Nota: estas dos repeticiones de Operación normal con 2 tareas se ejecutaron **después** de ~4 h de pruebas pesadas contra la misma RDS. Con 1 tarea y la base "fresca", la misma fila dio 0 % de error. El resultado está confundido por el estado de la base de datos (créditos de CPU de la t3.micro y crecimiento de la tabla de pedidos); ver análisis.

## Resumen por fila (promedio de repeticiones, 70/30)

| Test | Error % GET | Error % POST | Throughput total (req/s) | p99 POST (ms)* | REQ1 | REQ2 | REQ3 |
| --- | ---: | ---: | ---: | ---: | :-: | :-: | :-: |
| Alta carga | 14,4 | 27,9 | 38,7 | 172852 | NO | NO | NO |
| Muy alta carga | 52,5 | 68,3 | 30,5 | 300125 | NO | NO | NO |
| Estrés | 67,3 | 79,4 | 28,3 | 543187 | NO | NO | NO |
| Estrés fuerte | 74,4 | 86,9 | 24,7 | 1109265 | NO | NO | NO |

\* En las filas pesadas el p99 está inflado por la saturación del generador de carga (un solo PC con httpx): latencias de cientos de segundos con timeout de 10 s. El error % y los HTTP 500 sí provienen del servidor (CloudWatch Logs: `Error: timeout exceeded when trying to connect`, agotamiento del pool de conexiones de pg).

## Hallazgo: créditos de CPU de la RDS (db.t3.micro)

CloudWatch `CPUCreditBalance` de `cheapest-rds` (mínimo por periodo de 30 min, UTC): 12,7 a las 21:27 y **0,0 desde las 21:57 hasta el final** (02:57). Alta carga, rep 1 corrió 21:53-21:56 (con créditos, 0 % de error); desde la rep 2 (21:57) la RDS quedó limitada a su CPU base y aparecen los errores. Es decir, el "punto de inflexión" de la matriz coincide con el agotamiento de los créditos de CPU de una instancia *burstable*, además del pool de 10 conexiones por tarea (`DatabaseConnections` plana en 10) y de la CPU de RDS al ~99 % (CloudWatch). Las repeticiones posteriores (incluida la corrida con 2 tareas) se midieron con la base ya limitada.

## Notas
- Smoke 1: los intentos previos con errores (host mal escrito, protocolo, path sin `/lab`) fueron de configuración de JMeter y no cuentan como repeticiones.
- El throughput del POST en JMeter aparece en req/min; aquí se convierte a req/s (50,9/min = 0,85/s).
