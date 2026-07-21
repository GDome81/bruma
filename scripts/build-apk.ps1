# Compila l'APK di release di Bruma (firmato con debug key, per distribuzione diretta).
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1

$ErrorActionPreference = 'Stop'
$flutterBin = 'C:\src\flutter\bin'
$env:Path = "$flutterBin;$env:Path"
Set-Location "$PSScriptRoot\.."

if (-not (Test-Path 'bruma.env.json')) {
  Write-Host 'Manca bruma.env.json (SUPABASE_URL + SUPABASE_ANON_KEY).' -ForegroundColor Yellow
  exit 1
}

flutter build apk --release --dart-define-from-file=bruma.env.json

$apk = 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $apk) {
  Write-Host ''
  Write-Host "APK pronto: $((Resolve-Path $apk).Path)" -ForegroundColor Green
  Write-Host 'Installalo con:  adb install -r ' + $apk
}
