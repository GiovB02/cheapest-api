# Sonda de recuperacion: 1 venta cada 2 s. Guarda hora, codigo HTTP, latencia y si fue PENDING.
# Uso: .\lab5-pruebas\sonda.ps1 -Ronda 1      (detener con Ctrl+C)
param(
  [Parameter(Mandatory = $true)][int]$Ronda,
  [string]$BaseUrl = "https://7umdj0brv9.execute-api.us-east-2.amazonaws.com/lab"
)

$dir = Join-Path $PSScriptRoot "resultados"
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir "sonda_ronda_$Ronda.log"
$venta = Join-Path $PSScriptRoot "venta.json"
$tmp = Join-Path $env:TEMP "sonda_resp.txt"

"hora codigo tiempo_s pending" | Out-File $log -Encoding ascii
Write-Host "Sonda ronda $Ronda -> $log  (Ctrl+C para detener)"

while ($true) {
  $hora = Get-Date -Format "HH:mm:ss"
  $out = curl.exe -s -o $tmp -w "%{http_code} %{time_total}" -X POST "$BaseUrl/ventas/ventas" -H "Content-Type: application/json" -d "@$venta"
  $pend = "-"
  if ((Test-Path $tmp) -and (Select-String -Path $tmp -Pattern "pending_stock_confirmation" -Quiet)) { $pend = "PENDING" }
  # Add-Content con ASCII: Tee-Object -Append escribe UTF-16 y deja el archivo con dos codificaciones.
  $linea = "$hora $out $pend"
  Add-Content -Path $log -Value $linea -Encoding ascii
  Write-Host $linea
  Start-Sleep -Seconds 2
}
