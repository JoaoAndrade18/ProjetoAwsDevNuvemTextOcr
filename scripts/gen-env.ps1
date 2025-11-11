param(
  [string]$BackendEnvPath = "..\backend\.env",
  [string]$WorkerEnvPath  = "..\worker\.env"
)
$ErrorActionPreference = "Stop"

# Descobre a pasta do terraform relativa a este script (funciona de qualquer cwd)
$TfDir = Join-Path $PSScriptRoot "..\terraform"

# pegar outputs do terraform (em JSON)
Push-Location $TfDir
try {
  $o = terraform output -json | ConvertFrom-Json
} finally {
  Pop-Location
}

function Get-EnvFromFile($path) {
  $h = @{}
  if (Test-Path $path) {
    foreach ($line in Get-Content $path) {
      if ($line -match "^\s*#") { continue }
      if ($line -match "^\s*$") { continue }
      $kv = $line -split "=",2
      if ($kv.Length -eq 2) { $h[$kv[0]] = $kv[1] }
    }
  }
  return $h
}

$oldBackend = Get-EnvFromFile $BackendEnvPath
$oldWorker  = Get-EnvFromFile $WorkerEnvPath

function New-RandomString([int]$len=48) {
  -join ((48..57)+(65..90)+(97..122) | Get-Random -Count $len | ForEach-Object {[char]$_})
}

# Segredos
$DJANGO_SECRET_KEY = $oldBackend["DJANGO_SECRET_KEY"]
if (-not $DJANGO_SECRET_KEY) { $DJANGO_SECRET_KEY = "sk_" + (New-RandomString 48) }

$RDS_PASSWORD = $oldBackend["RDS_PASSWORD"]
if (-not $RDS_PASSWORD) { $RDS_PASSWORD = "change_me_strong_password" }

# Helper para outputs
function Get-Out($obj, $name) {
  if ($obj.PSObject.Properties.Name -contains $name) { return $obj.$name.value }
  return ""
}

# valores do Terraform
$AWS_REGION = Get-Out $o "aws_region"
$S3_BUCKET  = Get-Out $o "s3_bucket"
$SQS_URL    = Get-Out $o "sqs_queue_url"
$DDB_TABLE  = Get-Out $o "dynamo_table"
$RDS_HOST   = Get-Out $o "rds_endpoint"
$RDS_DB     = Get-Out $o "rds_db_name"
$RDS_USER_OUT = Get-Out $o "rds_user"   

# Fallbacks
if (-not $AWS_REGION -and $env:AWS_REGION) { $AWS_REGION = $env:AWS_REGION }
if (-not $RDS_DB) {
  if ($oldBackend["RDS_DB"]) { $RDS_DB = $oldBackend["RDS_DB"] } else { $RDS_DB = "ocrjobs" }
}

# Resolve RDS_USER sem usar ternário
if ($RDS_USER_OUT) {
  $RDS_USER_BACKEND = $RDS_USER_OUT
  $RDS_USER_WORKER  = $RDS_USER_OUT
} else {
  if ($oldBackend["RDS_USER"]) { $RDS_USER_BACKEND = $oldBackend["RDS_USER"] } else { $RDS_USER_BACKEND = "ocruser" }
  if ($oldWorker["RDS_USER"])  { $RDS_USER_WORKER  = $oldWorker["RDS_USER"]  } else { $RDS_USER_WORKER  = "ocruser" }
}

# backend/.env
$backendEnv = @"
# === generated from terraform outputs ===
AWS_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET
SQS_QUEUE_URL=$SQS_URL
DDB_TABLE_LOGS=$DDB_TABLE

# credenciais locais (se usar sem IAM na EC2)
AWS_ACCESS_KEY_ID=${env:AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${env:AWS_SECRET_ACCESS_KEY}

# Django
DJANGO_SECRET_KEY=$DJANGO_SECRET_KEY
DEBUG=1

# RDS
RDS_ENGINE=postgres
RDS_HOST=$RDS_HOST
RDS_PORT=5432
RDS_DB=$RDS_DB
RDS_USER=$RDS_USER_BACKEND
RDS_PASSWORD=$RDS_PASSWORD  # A senha pode ser setada aqui. ex: 1234_@#$
RDS_SSLMODE=require
# regras
SQS_RETENTION_SECONDS=172800
"@

# worker/.env
$workerRdsPass = $oldWorker["RDS_PASSWORD"]
if (-not $workerRdsPass) { $workerRdsPass = $RDS_PASSWORD }

$workerEnv = @"
# === generated from terraform outputs ===
AWS_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET
SQS_QUEUE_URL=$SQS_URL
DDB_TABLE_LOGS=$DDB_TABLE

AWS_ACCESS_KEY_ID=${env:AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${env:AWS_SECRET_ACCESS_KEY}

# RDS
RDS_ENGINE=postgres
RDS_HOST=$RDS_HOST
RDS_PORT=5432
RDS_DB=$RDS_DB
RDS_USER=$RDS_USER_WORKER
RDS_PASSWORD=$workerRdsPass

SQS_RETENTION_SECONDS=172800
"@

# escrever
$backendEnv | Out-File -FilePath $BackendEnvPath -Encoding ascii -Force
$workerEnv  | Out-File -FilePath $WorkerEnvPath  -Encoding ascii -Force

Write-Host "   .env gerados:"
Write-Host "   $BackendEnvPath"
Write-Host "   $WorkerEnvPath"
