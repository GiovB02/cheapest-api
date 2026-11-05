# Ejecuta la matriz de carga del Lab 5 (50, 200, 500 y 1500 hilos) contra POST /ventas/ventas
# y guarda un .jtl y un resumen .json por nivel en lab5-pruebas\resultados\.
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\correr-matriz.ps1 -Ronda 1
param(
  [Parameter(Mandatory = $true)][string]$Ronda,
  [string]$Jmeter = "C:\Users\Giovanna\Downloads\apache-jmeter-5.6.3\bin\jmeter.bat",
  [int]$PausaSeg = 15
)

$niveles = @(
  @{ threads = 50;   rampup = 10 },
  @{ threads = 200;  rampup = 20 },
  @{ threads = 500;  rampup = 50 },
  @{ threads = 1500; rampup = 75 }
)
$dir = Join-Path $PSScriptRoot "resultados"
New-Item -ItemType Directory -Force $dir | Out-Null
$plan = Join-Path $PSScriptRoot "plan-ventas.jmx"
$resumen = Join-Path $PSScriptRoot "resumen.js"
$tabla = @()

foreach ($n in $niveles) {
  $base = Join-Path $dir ("ronda{0}_{1}hilos" -f $Ronda, $n.threads)
  Remove-Item "$base.jtl" -ErrorAction SilentlyContinue
  Write-Host ("[{0}] Ronda {1}: {2} hilos, rampup {3} s ..." -f (Get-Date -Format "HH:mm:ss"), $Ronda, $n.threads, $n.rampup)
  & $Jmeter -n -t $plan "-Jthreads=$($n.threads)" "-Jrampup=$($n.rampup)" -l "$base.jtl" | Select-String "summary ="
  $json = node $resumen "$base.jtl"
  $json | Out-File "$base.json" -Encoding utf8
  $r = $json | ConvertFrom-Json
  $tabla += [pscustomobject]@{
    hilos = $n.threads; rampup_s = $n.rampup; p99_ms = $r.p99_ms; p95_ms = $r.p95_ms
    throughput_rps = $r.throughput_rps; error_pct = $r.error_pct
    r201 = $r.respuestas_201; pending = $r.con_pending_stock_confirmation; r429_pct = $r.pct_429
  }
  Start-Sleep -Seconds $PausaSeg
}

Write-Host ""
Write-Host "=== Resumen ronda $Ronda ==="
$tabla | Format-Table -AutoSize
$tabla | Export-Csv (Join-Path $dir "ronda${Ronda}_resumen.csv") -NoTypeInformation
Write-Host "Fin de la matriz: $(Get-Date -Format 'HH:mm:ss')"
