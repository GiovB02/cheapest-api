# Carga los datos de prueba (seed) en la RDS del stack Cheapest-lab5.
# Abre la RDS temporalmente (solo para tu IP), corre el seed y SIEMPRE lo cierra al final.
# Uso (desde la carpeta cheapest-api):  .\lab5-pruebas\seed-aws.ps1
param([string]$DbPassword)
$ErrorActionPreference = "Stop"
$env:AWS_CLI_FILE_ENCODING = "UTF-8"
$REGION = "us-east-2"
$DB_ID = "Cheapest-lab5-db"

if ($DbPassword) { $DB_PASSWORD = $DbPassword }
else {
  $secure = Read-Host "Contrasena de la base de datos (la que usaste al desplegar)" -AsSecureString
  $DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

$MY_IP = (curl.exe -s https://checkip.amazonaws.com).Trim()
$SG_RDS_ID = aws ec2 describe-security-groups --region $REGION --filters Name=tag:Name,Values=Cheapest-lab5-rds-sg --query "SecurityGroups[0].GroupId" --output text
$VPC_ID = aws ec2 describe-vpcs --region $REGION --filters Name=tag:Name,Values=Cheapest-lab5-vpc --query "Vpcs[0].VpcId" --output text
$RT_PUBLICA = aws ec2 describe-route-tables --region $REGION --filters Name=vpc-id,Values=$VPC_ID Name=route.destination-cidr-block,Values=0.0.0.0/0 --query "RouteTables[0].RouteTableId" --output text
$SUBNETS_PRIV = aws ec2 describe-subnets --region $REGION --filters Name=vpc-id,Values=$VPC_ID "Name=tag:Name,Values=Cheapest-lab5-private-*" --query "Subnets[].SubnetId" --output text
$SUBNETS_PRIV = $SUBNETS_PRIV -split "\s+" | Where-Object { $_ }
"IP: $MY_IP | SG: $SG_RDS_ID | Tabla publica: $RT_PUBLICA | Subnets privadas: $($SUBNETS_PRIV -join ', ')"

try {
  Write-Host "1/5 Dando ruta a internet a las subnets privadas (temporal)..."
  foreach ($s in $SUBNETS_PRIV) {
    aws ec2 associate-route-table --route-table-id $RT_PUBLICA --subnet-id $s --region $REGION --query AssociationId --output text
  }

  Write-Host "2/5 Haciendo publica la RDS y abriendo el puerto 5432 solo a tu IP..."
  aws rds modify-db-instance --db-instance-identifier $DB_ID --publicly-accessible --apply-immediately --region $REGION --query "DBInstance.DBInstanceStatus" --output text
  aws ec2 authorize-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 5432 --cidr "$MY_IP/32" --region $REGION --query "Return" --output text

  Write-Host "3/5 Esperando a que la RDS quede publica (1 a 4 min)..."
  for ($i = 0; $i -lt 40; $i++) {
    $st = aws rds describe-db-instances --db-instance-identifier $DB_ID --region $REGION --query "DBInstances[0].[PubliclyAccessible,DBInstanceStatus]" --output text
    Write-Host "   $st"
    if ($st -match "True\s+available") { break }
    Start-Sleep -Seconds 15
  }
  $RDS_HOST = aws rds describe-db-instances --db-instance-identifier $DB_ID --region $REGION --query "DBInstances[0].Endpoint.Address" --output text

  Write-Host "4/5 Probando conexion a $RDS_HOST ..."
  $ok = $false
  for ($i = 0; $i -lt 12 -and -not $ok; $i++) {
    $ok = (Test-NetConnection $RDS_HOST -Port 5432 -WarningAction SilentlyContinue).TcpTestSucceeded
    if (-not $ok) { Start-Sleep -Seconds 10 }
  }
  if (-not $ok) { throw "No hay conexion al puerto 5432 de la RDS." }

  Write-Host "5/5 Corriendo el seed..."
  $env:DB_HOST = $RDS_HOST; $env:DB_PORT = "5432"; $env:DB_USERNAME = "postgres"
  $env:DB_PASSWORD = $DB_PASSWORD; $env:DB_NAME = "Cheapest"; $env:SEED_FORCE = "true"
  npm run db:seed
}
finally {
  Write-Host "Cerrando acceso (RDS privada, regla de IP y rutas revertidas)..."
  Remove-Item Env:DB_HOST, Env:DB_PASSWORD -ErrorAction SilentlyContinue
  aws rds modify-db-instance --db-instance-identifier $DB_ID --no-publicly-accessible --apply-immediately --region $REGION --query "DBInstance.DBInstanceStatus" --output text
  aws ec2 revoke-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 5432 --cidr "$MY_IP/32" --region $REGION --query "Return" --output text
  foreach ($s in $SUBNETS_PRIV) {
    $assoc = aws ec2 describe-route-tables --region $REGION --filters Name=association.subnet-id,Values=$s --query "RouteTables[0].Associations[?SubnetId=='$s'].RouteTableAssociationId" --output text
    if ($assoc -and $assoc -ne "None") { aws ec2 disassociate-route-table --association-id $assoc --region $REGION }
  }
  Write-Host "Listo: base cerrada."
}
