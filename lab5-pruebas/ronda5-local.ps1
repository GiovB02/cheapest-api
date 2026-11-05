# Ronda 5 (local, Docker): consistencia bajo fallo - Outbox e idempotencia.
# Requisito: el ambiente local arriba con   docker compose -p lab5 up -d --build
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\ronda5-local.ps1
# Imprime cada paso con titulos: tome las capturas de cada bloque de salida.
# "Continue": docker escribe su progreso por stderr y con "Stop" eso abortaria el script.
$ErrorActionPreference = "Continue"
$INV = "http://localhost:3002/inventory"
$VEN = "http://localhost:3003/ventas"
$ITEM = "11111111-1111-4111-8111-111111111111"
$utf8 = New-Object Text.UTF8Encoding($false)

function sql($q) { docker compose -p lab5 exec -T postgres psql -U postgres -d cheapest -c ($q -replace '"', '\"') }
function sqlval($q) { (docker compose -p lab5 exec -T postgres psql -U postgres -d cheapest -t -A -c ($q -replace '"', '\"')).Trim() }
function Titulo($t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Green }
function Post($url, $archivo, $extra = @()) {
  curl.exe -s -i -X POST $url -H "Content-Type: application/json" @extra -d "@$archivo"
}

# Asegura que Inventario este encendido antes de empezar (por si se repite la ronda).
docker compose -p lab5 start inventario 2>&1 | Out-Null
do { Start-Sleep -Milliseconds 500; $c0 = curl.exe -s -o NUL -w "%{http_code}" http://localhost:3002/health } while ($c0 -ne "200")

# --- Preparacion: seed local, producto externo y venta-local.json ---------------------------
Titulo "Preparacion"
$env:DB_SSL = "false"; $env:DB_HOST = "127.0.0.1"; $env:DB_PORT = "5432"
$env:DB_USERNAME = "postgres"; $env:DB_PASSWORD = "postgres"; $env:DB_NAME = "cheapest"
npm run db:seed 2>&1 | Select-String "seeded|already|Failed"

$pe = '{"tiendaId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","codigoBarras":"7700000000003","nombre":"Producto local","categoria":"General","precioBase":25.5,"monedaId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","cantidad":1000000}'
$peFile = Join-Path $env:TEMP "pe_local.json"; [IO.File]::WriteAllText($peFile, $pe, $utf8)
$peId = (curl.exe -s -X POST "$VEN/productos-externos" -H "Content-Type: application/json" -d "@$peFile" | ConvertFrom-Json).id
$ventaFile = Join-Path $PSScriptRoot "venta-local.json"
$venta = '{"tiendaId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","fechaHora":"2026-10-24T10:00:00Z","monedaId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","items":[{"productoExternoId":"' + $peId + '","productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cantidad":1,"precioUnitario":25.5}]}'
[IO.File]::WriteAllText($ventaFile, $venta, $utf8)

Write-Host "Venta normal (Inventario sano) - debe ser 201 SIN pending_stock_confirmation:"
Post "$VEN/ventas" $ventaFile | Select-String "HTTP/|pending_stock_confirmation|`"total`""
Start-Sleep -Seconds 6   # deja que el Outbox entregue el descuento de esta venta

# --- Fase 1, escenario 1: el mismo descuento aplicado dos veces ------------------------------
Titulo "FASE 1 - Escenario 1: peticion repetida SIN idempotencia (POST /inventory/ventas)"
$reg = '{"tiendaId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","ventaId":"f0000000-0000-4000-8000-' + ("{0:000000000000}" -f (Get-Random -Maximum 999999999999)) + '","itemInventarioId":"' + $ITEM + '","fechaVenta":"2026-10-24T10:00:00Z","cantidad":1}'
$regFile = Join-Path $env:TEMP "registro.json"; [IO.File]::WriteAllText($regFile, $reg, $utf8)
Write-Host "Cantidad ANTES:"; sql "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';"
Write-Host "Se envia DOS veces la misma peticion (misma ventaId):"
Post "$INV/ventas" $regFile | Select-String "HTTP/"
Post "$INV/ventas" $regFile | Select-String "HTTP/"
Write-Host "Cantidad DESPUES (debe haber bajado 2 aunque era una sola venta):"; sql "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';"

# --- Fase 1, escenario 2: ventas con Inventario apagado --------------------------------------
Titulo "FASE 1 - Escenario 2: ventas registradas con Inventario APAGADO"
$cantAntes = [int](sqlval "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';")
$ventasAntes = [int](sqlval "SELECT count(*) FROM ventas;")
Write-Host "Antes -> stock: $cantAntes | ventas: $ventasAntes"
docker compose -p lab5 stop inventario 2>&1 | Out-Null
Write-Host "Inventario apagado. Creando 3 ventas (deben ser 201 con pending_stock_confirmation):"
1..3 | ForEach-Object { Post "$VEN/ventas" $ventaFile | Select-String "HTTP/|pending_stock_confirmation" }
Write-Host "Ventas en la tabla (3 mas) y stock (sin cambio):"
sql "SELECT count(*) AS ventas FROM ventas;"
sql "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';"
Write-Host "Tabla outbox_http_calls (3 filas PENDING, attempts crece cada 2 s):"
sql "SELECT id, status, attempts, `"createdAt`" FROM outbox_http_calls ORDER BY `"createdAt`" DESC LIMIT 5;"
Start-Sleep -Seconds 6
sql "SELECT id, status, attempts FROM outbox_http_calls ORDER BY `"createdAt`" DESC LIMIT 5;"

# --- Fase 2: encender Inventario y reconciliar -----------------------------------------------
Titulo "FASE 2 - Encender Inventario y medir la reconciliacion (ASR-4a)"
docker compose -p lab5 start inventario 2>&1 | Out-Null
do { Start-Sleep -Milliseconds 500; $code = curl.exe -s -o NUL -w "%{http_code}" http://localhost:3002/health } while ($code -ne "200")
$tRec = sqlval "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.MS');"
Write-Host "T_rec (Inventario vuelve a responder /health) = $tRec UTC"
$pend = 3
for ($i = 0; $i -lt 60 -and $pend -gt 0; $i++) {
  Start-Sleep -Seconds 2
  $pend = [int](sqlval "SELECT count(*) FROM outbox_http_calls WHERE status <> 'DELIVERED';")
}
Write-Host "Tabla outbox_http_calls tras la recuperacion:"
sql "SELECT id, status, attempts, `"deliveredAt`" FROM outbox_http_calls ORDER BY `"createdAt`" DESC LIMIT 5;"
$seg = sqlval "SELECT round(EXTRACT(EPOCH FROM (max(`"deliveredAt`") - timestamp '$tRec'))::numeric, 1) FROM outbox_http_calls WHERE `"createdAt`" > now() - interval '10 minutes';"
Write-Host "Tiempo de reconciliacion (ultimo deliveredAt - T_rec): $seg s   (umbral ASR-4: < 30 s)" -ForegroundColor Yellow
$cantDesp = [int](sqlval "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';")
Write-Host "Stock: antes de las 3 ventas = $cantAntes, ahora = $cantDesp, bajo $($cantAntes - $cantDesp) (esperado: 3)" -ForegroundColor Yellow

# --- Fase 2: idempotencia (409) ---------------------------------------------------------------
Titulo "FASE 2 - Idempotencia: reenviar una entrega ya hecha con la misma X-Idempotency-Key"
$key = sqlval "SELECT id FROM outbox_http_calls WHERE status = 'DELIVERED' ORDER BY `"createdAt`" DESC LIMIT 1;"
$payload = sqlval "SELECT payload::text FROM outbox_http_calls WHERE id = '$key';"
$plFile = Join-Path $env:TEMP "payload_outbox.json"; [IO.File]::WriteAllText($plFile, $payload, $utf8)
Write-Host "Clave: $key"
Write-Host "Cantidad antes del reenvio:"; sql "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';"
Post "$INV/ventas/desde-outbox" $plFile @("-H", "X-Idempotency-Key: $key") | Select-String "HTTP/|message|statusCode"
Write-Host "Cantidad despues del reenvio (no debe cambiar):"; sql "SELECT cantidad FROM items_inventario WHERE id = '$ITEM';"
Write-Host ""
Write-Host "Fin de la Ronda 5. Para apagar el ambiente local:  docker compose -p lab5 down" -ForegroundColor Cyan
