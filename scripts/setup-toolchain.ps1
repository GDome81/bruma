# Prepara la toolchain di build per Bruma su Windows.
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\setup-toolchain.ps1

$ErrorActionPreference = 'Stop'
$flutterBin = 'C:\src\flutter\bin'

Write-Host '== Bruma — setup toolchain ==' -ForegroundColor Cyan

if (-not (Test-Path "$flutterBin\flutter.bat")) {
  Write-Host "Flutter non trovato in $flutterBin." -ForegroundColor Yellow
  Write-Host 'Clono Flutter stable...'
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git C:\src\flutter
}

# Aggiunge Flutter al PATH utente (persistente) se assente.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$flutterBin*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$flutterBin", 'User')
  Write-Host "Aggiunto $flutterBin al PATH utente. Riavvia il terminale per renderlo permanente." -ForegroundColor Green
}
$env:Path = "$flutterBin;$env:Path"

# Android Studio (porta Android SDK + JDK + emulatore) via winget, se assente.
$studio = Get-Command 'studio64.exe' -ErrorAction SilentlyContinue
if (-not $studio -and -not (Test-Path "$env:ProgramFiles\Android\Android Studio")) {
  Write-Host 'Installo Android Studio via winget (potrebbe chiedere conferma UAC)...'
  winget install -e --id Google.AndroidStudio --accept-package-agreements --accept-source-agreements
} else {
  Write-Host 'Android Studio risulta gia presente.'
}

Write-Host ''
Write-Host 'PROSSIMI PASSI MANUALI:' -ForegroundColor Cyan
Write-Host '  1) Apri Android Studio una volta e completa il primo avvio'
Write-Host '     (installa Android SDK + platform-tools dal SDK Manager).'
Write-Host '  2) Accetta le licenze Android:   flutter doctor --android-licenses'
Write-Host '  3) Verifica l ambiente:          flutter doctor'
Write-Host '  4) Collega il telefono con Debug USB attivo:  flutter devices'
Write-Host ''
Write-Host 'Diagnostica attuale:' -ForegroundColor Cyan
& "$flutterBin\flutter.bat" doctor
