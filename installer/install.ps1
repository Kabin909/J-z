$ErrorActionPreference = 'Stop'
function JZ($t){ Write-Host "[J&Z] $t" -ForegroundColor DarkYellow }
function Good($t){ Write-Host "[J&Z] $t" -ForegroundColor Green }
Clear-Host
Write-Host @'
       ██╗ █████╗ ███╗   ██╗███████╗
       ██║██╔══██╗████╗  ██║╚══███╔╝
       ██║███████║██╔██╗ ██║  ███╔╝
  ██   ██║██╔══██║██║╚██╗██║ ███╔╝
  ╚█████╔╝██║  ██║██║ ╚████║███████╗
   ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝
                    PANEL
'@ -ForegroundColor DarkYellow
Write-Host "J&Z Panel Installer — Windows / Docker Desktop" -ForegroundColor White
Write-Host ""
Write-Host "1) Install Panel + Wings (Panel + WSL2 node)" -ForegroundColor Red
Write-Host "2) Install Panel" -ForegroundColor Green
Write-Host "3) Install Wings (WSL2 recommended)" -ForegroundColor Blue
Write-Host "4) Diagnostics" -ForegroundColor Cyan
Write-Host "5) Exit"
$choice = Read-Host "Select an option"
if($choice -eq '5'){ exit 0 }
if(-not (Get-Command docker -ErrorAction SilentlyContinue)){ throw 'Docker Desktop is required for Windows panel testing.' }
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
if($choice -eq '4'){ docker version; docker compose version; docker compose ps; if(Get-Command wsl.exe -ErrorAction SilentlyContinue){wsl --status}; Good 'Diagnostics completed.'; exit 0 }
if($choice -eq '1' -or $choice -eq '2'){
  if(-not (Test-Path '.env')){
  Copy-Item '.env.example' '.env'
  function New-JZSecret([int]$Bytes=32){
    $b = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($b)
    return [Convert]::ToBase64String($b).Replace('+','-').Replace('/','_').TrimEnd('=')
  }
  $envText = Get-Content '.env' -Raw
  $replacements = @{
    'POSTGRES_PASSWORD' = New-JZSecret
    'JWT_SECRET' = New-JZSecret
    'COOKIE_SECRET' = New-JZSecret
    'WINGS_SHARED_SECRET' = New-JZSecret
    'NODE_ENCRYPTION_KEY' = New-JZSecret
    'JZ_BOOTSTRAP_TOKEN' = New-JZSecret
  }
  foreach($k in $replacements.Keys){ $envText = [regex]::Replace($envText, "(?m)^$k=.*$", "$k=$($replacements[$k])") }
  $pg = $replacements['POSTGRES_PASSWORD']
  $envText = [regex]::Replace($envText, '(?m)^DATABASE_URL=.*$', "DATABASE_URL=postgresql://jz:$pg@postgres:5432/jz")
  Set-Content '.env' $envText -NoNewline
  Good 'Generated secure local .env secrets.'
}
  JZ 'Starting PostgreSQL, Redis, API, worker, WebSocket and web services.'
  docker compose up -d --build postgres redis api worker ws web
  Good 'J&Z Panel is available at http://localhost:5173'
  if($choice -eq '1'){ JZ 'Wings runs in Linux. Install/use WSL2 and run installer/install.sh there for a real Docker node.' }
}
if($choice -eq '3'){
  if(-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)){ throw 'WSL2 is required. Run: wsl --install' }
  wsl --status
  Write-Host 'Enter your WSL Linux shell and run: sudo bash installer/install.sh' -ForegroundColor Yellow
}
