# Impacto del Outbox en la latencia (ASR-4b): fila de 500 hilos / 50 s con Inventario SANO
# (FAULT_DELAY_MS=0) y las tacticas combinadas activas. Compara luego su p99 con la fila de
# 500 hilos de la Ronda 4 (resultados\ronda4_500hilos.json).
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\correr-latencia-outbox.ps1
$ErrorActionPreference = "Stop"
$env:AWS_CLI_FILE_ENCODING = "UTF-8"
$dir = Join-Path $PSScriptRoot "resultados"
$jm = "C:\Users\Giovanna\Downloads\apache-jmeter-5.6.3\bin\jmeter.bat"

Write-Host "[$(Get-Date -Format HH:mm:ss)] Reiniciando Inventario SANO (sin retraso)..." -ForegroundColor Cyan
node (Join-Path $PSScriptRoot "ecs-config.js") "--inventario=sano"
if ($LASTEXITCODE -ne 0) { throw "ecs-config.js fallo" }
Start-Sleep -Seconds 20

$out = Join-Path $dir "outbox_sano_500hilos.jtl"
Remove-Item $out -ErrorAction SilentlyContinue
Write-Host "[$(Get-Date -Format HH:mm:ss)] 500 hilos, rampup 50 s, Inventario sano..." -ForegroundColor Cyan
& $jm -n -t (Join-Path $PSScriptRoot "plan-ventas.jmx") "-Jthreads=500" "-Jrampup=50" -l $out | Select-String "summary ="
$js = node (Join-Path $PSScriptRoot "resumen.js") $out
$js | Out-File (Join-Path $dir "outbox_sano_500hilos.json") -Encoding utf8
Write-Host "=== Outbox activo, Inventario sano, 500 hilos ===" -ForegroundColor Green
$js

$ref = Join-Path $dir "ronda4_500hilos.json"
if (Test-Path $ref) {
  $a = Get-Content $ref -Raw | ConvertFrom-Json
  $b = $js | ConvertFrom-Json
  Write-Host ("Ronda 4 (500 hilos): p99={0} ms | Outbox sano: p99={1} ms | diferencia={2} ms" -f $a.p99_ms, $b.p99_ms, ($b.p99_ms - $a.p99_ms)) -ForegroundColor Yellow
}
