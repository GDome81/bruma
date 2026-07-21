# Applica lo schema Bruma a un progetto Supabase cloud tramite CLI.
# ALTERNATIVA piu' semplice: incolla supabase\migrations\20260720000000_init.sql
# nel SQL Editor del dashboard Supabase ed eseguilo.
#
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\apply-supabase.ps1 -ProjectRef <ref>

param(
  [Parameter(Mandatory = $true)][string]$ProjectRef
)

$ErrorActionPreference = 'Stop'
Set-Location "$PSScriptRoot\.."

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  Write-Host 'Supabase CLI non trovato.' -ForegroundColor Yellow
  Write-Host 'Installa con Scoop:  scoop install supabase'
  Write-Host 'oppure vedi https://supabase.com/docs/guides/cli'
  Write-Host ''
  Write-Host 'In alternativa, senza CLI: incolla supabase\migrations\20260720000000_init.sql nel SQL Editor del dashboard.'
  exit 1
}

if (-not (Test-Path 'supabase\config.toml')) {
  Write-Host 'Inizializzo la cartella supabase (rispondi N alle domande opzionali)...'
  supabase init
}

supabase link --project-ref $ProjectRef
supabase db push
Write-Host 'Schema applicato.' -ForegroundColor Green
