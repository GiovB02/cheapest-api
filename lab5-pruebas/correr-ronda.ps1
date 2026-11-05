# Corre UNA ronda completa del Lab 5 (rondas 1 a 3), de principio a fin:
#   1) aplica la configuracion de la ronda y reinicia Inventario (T0)
#   2) arranca la sonda en segundo plano
#   3) a T0 + 1 min corre la matriz de carga (50/200/500/1500 hilos)
#   4) espera hasta T0 + 12 min mostrando la cuenta regresiva
#   5) detiene la sonda y consulta CloudWatch (RequestCount a Inventario)
#   6) imprime un resumen final y guarda todo en lab5-pruebas\resultados\
#
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\correr-ronda.ps1 -Ronda 1
#   Ronda 1 = linea base (sin sidecar)          Ronda 2 = sidecar solo reintentos (requiere imagen 1.0.0-solo-retry)
#   Ronda 3 = sidecar completo (circuit breaker)
#   Ronda 4 = sidecar completo + rate limiting en API Gateway (100 req/s, burst 200) + prueba de saturacion a 300 req/s
param([Parameter(Mandatory = $true)][ValidateSet("1", "2", "3", "4")][string]$Ronda)

$ErrorActionPreference = "Stop"
$env:AWS_CLI_FILE_ENCODING = "UTF-8"
$REGION = "us-east-2"
$dir = Join-Path $PSScriptRoot "resultados"
New-Item -ItemType Directory -Force $dir | Out-Null

function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) -ForegroundColor Cyan }

# --- 1) Configuracion de la ronda + reinicio de Inventario -------------------------------
$ventasModo = @{ "1" = "sin-sidecar"; "2" = "solo-retry"; "3" = "completo"; "4" = "completo" }[$Ronda]
if ($Ronda -eq "4") {
  $apiId = aws apigatewayv2 get-apis --region $REGION --query "Items[?Name=='Cheapest-ms-api'].ApiId" --output text
  Log "Ronda 4 - activando rate limiting en API Gateway ($apiId, etapa lab): Rate=100 req/s, Burst=200"
  aws apigatewayv2 update-stage --api-id $apiId --stage-name lab --default-route-settings "ThrottlingRateLimit=100,ThrottlingBurstLimit=200" --region $REGION --query "DefaultRouteSettings" --output json
}
Log "Ronda $Ronda - aplicando configuracion: Ventas=$ventasModo, Inventario=falla (5 s de retraso, recupera a los 10 min)"
node (Join-Path $PSScriptRoot "ecs-config.js") "--ventas=$ventasModo" "--inventario=falla"
if ($LASTEXITCODE -ne 0) { throw "ecs-config.js fallo" }

$t0 = [datetimeoffset]::Parse((Get-Content (Join-Path $dir "ultimo_arranque_svc-Cheapest-inventario.txt")).Trim()).LocalDateTime
Log "T0 (arranque de Inventario) = $($t0.ToString('HH:mm:ss')). Inventario degradado hasta $($t0.AddMinutes(10).ToString('HH:mm:ss'))."
if ((Get-Date) -gt $t0.AddMinutes(4)) { Write-Warning "Pasaron mas de 4 min desde T0; quedara menos ventana de fallo. Considera repetir la ronda." }

# --- 2) Sonda en segundo plano ------------------------------------------------------------
$sonda = Start-Process powershell -PassThru -WindowStyle Minimized -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'sonda.ps1')`" -Ronda $Ronda"
Log "Sonda iniciada (PID $($sonda.Id)), escribe en resultados\sonda_ronda_$Ronda.log"

# --- 3) Matriz a T0 + 1 min --------------------------------------------------------------
$inicioMatriz = $t0.AddMinutes(1)
while ((Get-Date) -lt $inicioMatriz) { Start-Sleep -Seconds 2 }
Log "Iniciando matriz de carga."
& (Join-Path $PSScriptRoot "correr-matriz.ps1") -Ronda $Ronda

# --- 4) Esperar hasta T0 + 12 min --------------------------------------------------------
$fin = $t0.AddMinutes(12)
Log "Matriz terminada. Esperando hasta $($fin.ToString('HH:mm:ss')) para observar la recuperacion (solo corre la sonda)..."
while ((Get-Date) -lt $fin) {
  $resta = [int]($fin - (Get-Date)).TotalSeconds
  Write-Host ("`r   faltan {0:00}:{1:00}   ultima linea de la sonda: {2}   " -f [math]::Floor($resta / 60), ($resta % 60), (Get-Content (Join-Path $dir "sonda_ronda_$Ronda.log") -Tail 1)) -NoNewline
  Start-Sleep -Seconds 5
}
Write-Host ""

# --- 5) Detener sonda y consultar CloudWatch ---------------------------------------------
Stop-Process -Id $sonda.Id -Force -ErrorAction SilentlyContinue
Log "Sonda detenida. Esperando 2 min a que CloudWatch publique las metricas..."
Start-Sleep -Seconds 120

$tgArn, $lbArn = (aws elbv2 describe-target-groups --names Cheapest-lab5-inventario-tg --region $REGION --query "TargetGroups[0].[TargetGroupArn,LoadBalancerArns[0]]" --output text) -split "\s+"
$tgDim = $tgArn.Substring($tgArn.IndexOf("targetgroup/"))
$lbDim = $lbArn.Substring($lbArn.IndexOf("loadbalancer/") + 13)
$ini = $t0.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$end = $fin.AddMinutes(2).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Metrica($nombre) {
  $j = aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name $nombre --dimensions "Name=TargetGroup,Value=$tgDim" "Name=LoadBalancer,Value=$lbDim" --start-time $ini --end-time $end --period 60 --statistics Sum --region $REGION --output json | ConvertFrom-Json
  return $j.Datapoints | Sort-Object Timestamp
}
$req = Metrica "RequestCount"
$err5 = Metrica "HTTPCode_Target_5XX_Count"
$totalReq = ($req | Measure-Object Sum -Sum).Sum
$total5xx = ($err5 | Measure-Object Sum -Sum).Sum

# --- 6) Resumen ---------------------------------------------------------------------------
$matriz = Import-Csv (Join-Path $dir "ronda${Ronda}_resumen.csv")
$ventas201 = ($matriz | Measure-Object r201 -Sum).Sum
$sondaLog = Get-Content (Join-Path $dir "sonda_ronda_$Ronda.log")
$sonda201 = @($sondaLog | Where-Object { $_ -match " 201 " }).Count
$sondaTotal = [math]::Max(0, $sondaLog.Count - 1)
$ventasTot = [int]$ventas201 + $sonda201

$resumen = [pscustomobject]@{
  ronda = $Ronda; T0 = $t0.ToString("HH:mm:ss"); ventana_cloudwatch = "$ini .. $end"
  requestcount_inventario_total = $totalReq; http5xx_inventario_total = $total5xx
  ventas_201_matriz = [int]$ventas201; ventas_201_sonda = $sonda201; ventas_201_total = $ventasTot
  llamadas_disponibilidad = ($totalReq - $ventasTot)
}
$resumen | ConvertTo-Json | Out-File (Join-Path $dir "ronda${Ronda}_cloudwatch_resumen.json") -Encoding utf8
$req | Select-Object Timestamp, Sum | Export-Csv (Join-Path $dir "ronda${Ronda}_requestcount_por_minuto.csv") -NoTypeInformation

Write-Host ""
Write-Host "================ RESUMEN RONDA $Ronda ================" -ForegroundColor Green
$matriz | Format-Table hilos, rampup_s, p99_ms, p95_ms, throughput_rps, error_pct, r201, pending, r429_pct -AutoSize
Write-Host "Sonda: $sondaTotal peticiones ($sonda201 con 201). Ver resultados\sonda_ronda_$Ronda.log"
Write-Host "CloudWatch RequestCount a Inventario (T0..T0+14 min): $totalReq  |  5xx: $total5xx"
Write-Host "Ventas con 201: $ventasTot  ->  llamadas de disponibilidad = $($totalReq - $ventasTot)  (anota este numero: sirve para el factor de amplificacion)"
Write-Host "Todo guardado en lab5-pruebas\resultados\ (ronda${Ronda}_*)."

# --- 7) Solo Ronda 4: prueba de saturacion a 300 req/s (Inventario ya recuperado, fuera de la ventana de CloudWatch) ---
if ($Ronda -eq "4") {
  Log "Parte 2: saturacion a 300 req/s durante 120 s (el rate limit deberia devolver 429)..."
  $jm = "C:\Users\Giovanna\Downloads\apache-jmeter-5.6.3\bin\jmeter.bat"
  $sat = Join-Path $dir "ronda4_saturacion.jtl"
  Remove-Item $sat -ErrorAction SilentlyContinue
  & $jm -n -t (Join-Path $PSScriptRoot "plan-saturacion.jmx") -l $sat | Select-String "summary ="
  $js = node (Join-Path $PSScriptRoot "resumen.js") $sat
  $js | Out-File (Join-Path $dir "ronda4_saturacion.json") -Encoding utf8
  Write-Host "=== Saturacion 300 req/s ===" -ForegroundColor Green
  $js
}
