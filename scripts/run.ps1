# Avvia Bruma sul dispositivo collegato, iniettando le chiavi Supabase.
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\run.ps1

$ErrorActionPreference = 'Stop'
$flutterBin = 'C:\src\flutter\bin'
$env:Path = "$flutterBin;$env:Path"
Set-Location "$PSScriptRoot\.."

if (-not (Test-Path 'bruma.env.json')) {
  Write-Host 'Manca bruma.env.json.' -ForegroundColor Yellow
  Write-Host 'Copia bruma.env.example.json in bruma.env.json e inserisci SUPABASE_URL e SUPABASE_ANON_KEY.'
  exit 1
}

flutter run --dart-define-from-file=bruma.env.json
