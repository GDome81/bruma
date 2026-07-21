# Avvia Bruma come web server (per simulare piu' utenti in finestre separate).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\run-web.ps1
# Poi apri http://localhost:8080 in una finestra normale (utente A) e una in
# incognito (utente B): storage separato = identita' separate.

$ErrorActionPreference = 'Stop'
$flutterBin = 'C:\src\flutter\bin'
$env:Path = "$flutterBin;$env:Path"
Set-Location "$PSScriptRoot\.."

if (-not (Test-Path 'bruma.env.json')) {
  Write-Host 'Manca bruma.env.json (SUPABASE_URL + SUPABASE_ANON_KEY).' -ForegroundColor Yellow
  exit 1
}

Write-Host 'Apri http://localhost:8080 in due finestre (una normale + una incognito).' -ForegroundColor Cyan
flutter run -d web-server --web-port 8080 --dart-define-from-file=bruma.env.json
