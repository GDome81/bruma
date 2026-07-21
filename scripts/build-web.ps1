# Compila la versione web (PWA) di Bruma per il deploy statico.
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\build-web.ps1 [-BaseHref /sottocartella/]
#
# L'output è in build\web : carica QUELLA cartella sul tuo host statico.

param(
  [string]$BaseHref = "/"
)

$ErrorActionPreference = 'Stop'
$flutterBin = 'C:\src\flutter\bin'
$env:Path = "$flutterBin;$env:Path"
Set-Location "$PSScriptRoot\.."

if (-not (Test-Path 'bruma.env.json')) {
  Write-Host 'Manca bruma.env.json (SUPABASE_URL + SUPABASE_ANON_KEY).' -ForegroundColor Yellow
  exit 1
}

# La anon key è PUBBLICA per design (la RLS protegge i dati), quindi è sicuro
# includerla nel bundle web.
flutter build web --release --base-href $BaseHref --dart-define-from-file=bruma.env.json

Write-Host ''
Write-Host "Fatto. Cartella da pubblicare: $((Resolve-Path 'build\web').Path)" -ForegroundColor Green
Write-Host 'Servi sempre in HTTPS (necessario per fotocamera e PWA). Vedi WEB_DEPLOY.md.'
