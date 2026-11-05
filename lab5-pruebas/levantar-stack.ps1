# Enciende todo el laboratorio de una vez:
#   1) despliega el stack Cheapest-lab5 en us-east-2 (15 a 20 min)
#   2) siembra los datos de prueba en la RDS (abre y cierra el acceso temporalmente)
#   3) crea el producto externo de prueba y actualiza venta.json, plan-ventas.jmx y sonda.ps1
#      con los IDs/URL nuevos de ESTE despliegue
#   4) verifica los servicios y una venta de prueba
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\levantar-stack.ps1
$ErrorActionPreference = "Stop"
$env:AWS_CLI_FILE_ENCODING = "UTF-8"
$REGION = "us-east-2"
$REGISTRY = "713877988654.dkr.ecr.$REGION.amazonaws.com"
$raiz = Split-Path $PSScriptRoot -Parent

function Log($m) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m) -ForegroundColor Cyan }

$secure = Read-Host "Elige la contrasena de la base de datos (min. 8, solo letras y numeros)" -AsSecureString
$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
if ($pass.Length -lt 8) { throw "La contrasena debe tener al menos 8 caracteres." }

# --- 1) Despliegue --------------------------------------------------------------------------
Log "1/4 Desplegando el stack (15 a 20 min, no cierres esta ventana)..."
aws cloudformation deploy --template-file (Join-Path $raiz "..\laboratorios-main\lab_5\recursos\cloudformation_template.yaml") --stack-name Cheapest-lab5 --region $REGION --parameter-overrides "LogisticaImageUri=$REGISTRY/cheapest-logistica:2.0.0" "InventarioImageUri=$REGISTRY/cheapest-inventario:2.0.0" "VentasImageUri=$REGISTRY/cheapest-ventas:2.0.0" "VentasSidecarImageUri=$REGISTRY/cheapest-ventas-sidecar:1.0.0" "DBPassword=$pass"
if ($LASTEXITCODE -ne 0) { throw "Fallo el despliegue. Revisa CloudFormation > Pilas > Cheapest-lab5 > Eventos." }

$baseUrl = aws cloudformation describe-stacks --stack-name Cheapest-lab5 --region $REGION --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
$apiHost = ([uri]$baseUrl).Host
Log "Stack listo. BASE_URL = $baseUrl"

# --- 2) Seed -------------------------------------------------------------------------------
Log "2/4 Sembrando datos de prueba..."
& (Join-Path $PSScriptRoot "seed-aws.ps1") -DbPassword $pass
$pass = $null

# --- 3) Producto externo + archivos de prueba ---------------------------------------------
Log "3/4 Creando producto externo de prueba y actualizando archivos..."
$body = '{"tiendaId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","codigoBarras":"7700000000001","nombre":"Producto prueba carga","categoria":"General","precioBase":25.5,"monedaId":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","cantidad":1000000}'
$tmp = Join-Path $env:TEMP "pe.json"
[IO.File]::WriteAllText($tmp, $body)
$resp = curl.exe -s -X POST "$baseUrl/ventas/productos-externos" -H "Content-Type: application/json" -d "@$tmp" | ConvertFrom-Json
$peId = $resp.id
if (-not $peId) { throw "No se pudo crear el producto externo." }

$uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
$archivos = @{
  "venta.json"        = @{ patron = "(`"productoExternoId`"\s*:\s*`")$uuid"; reemplazo = "`${1}$peId" }
  "plan-ventas.jmx"   = @{ patron = "(`"productoExternoId`":`")$uuid"; reemplazo = "`${1}$peId" }
}
foreach ($k in $archivos.Keys) {
  $p = Join-Path $PSScriptRoot $k
  $t = [IO.File]::ReadAllText($p)
  $t = [regex]::Replace($t, $archivos[$k].patron, $archivos[$k].reemplazo)
  [IO.File]::WriteAllText($p, $t)
}
# El host (id de la API) cambia en cada despliegue:
foreach ($k in "plan-ventas.jmx", "sonda.ps1") {
  $p = Join-Path $PSScriptRoot $k
  $t = [IO.File]::ReadAllText($p)
  $t = [regex]::Replace($t, "[a-z0-9]{10}\.execute-api\.$REGION\.amazonaws\.com", $apiHost)
  [IO.File]::WriteAllText($p, $t)
}
if (Test-Path (Join-Path $PSScriptRoot "plan-saturacion.jmx")) {
  foreach ($k in "plan-saturacion.jmx") {
    $p = Join-Path $PSScriptRoot $k
    $t = [IO.File]::ReadAllText($p)
    $t = [regex]::Replace($t, "[a-z0-9]{10}\.execute-api\.$REGION\.amazonaws\.com", $apiHost)
    $t = [regex]::Replace($t, "(`"productoExternoId`":`")$uuid", "`${1}$peId")
    [IO.File]::WriteAllText($p, $t)
  }
}
Set-Content (Join-Path $PSScriptRoot "base_url.txt") $baseUrl -Encoding ascii

# --- 4) Verificacion -----------------------------------------------------------------------
Log "4/4 Verificando..."
foreach ($s in "logistica", "inventario", "ventas") {
  Write-Host ("  health {0}: {1}" -f $s, (curl.exe -s -o NUL -w "%{http_code}" "$baseUrl/$s/health"))
}
$code = curl.exe -s -o NUL -w "%{http_code}" -X POST "$baseUrl/ventas/ventas" -H "Content-Type: application/json" -d "@$(Join-Path $PSScriptRoot 'venta.json')"
Write-Host "  venta de prueba: HTTP $code (debe ser 201)"
Write-Host ""
Write-Host "LISTO. BASE_URL = $baseUrl" -ForegroundColor Green
