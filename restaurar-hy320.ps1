# Desfaz o que o otimizar-hy320.ps1 fez no projetor HY320 Mini.
#
# Uso:
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15                     # reativa pacotes e volta os ajustes ao original
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15 -RemoverProjectivy  # tambem desinstala o Projectivy Launcher
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15 -ResetCompilacao    # tambem descarta a compilacao nativa dos apps
param(
  [string]$Ip,
  [switch]$ResetCompilacao,
  [switch]$RemoverProjectivy
)

# Permite usar um adb.exe copiado para a pasta dos scripts (o PowerShell nao procura na pasta atual).
$env:Path = "$PSScriptRoot;$env:Path"
# ADB recem-instalado pelo winget ainda nao esta no PATH deste terminal: procura na pasta dele.
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $adbWinget = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter 'Google.PlatformTools*' -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'platform-tools' } | Where-Object { Test-Path (Join-Path $_ 'adb.exe') } | Select-Object -First 1
  if ($adbWinget) { $env:Path = "$adbWinget;$env:Path" }
}

if (-not $Ip) {
  Write-Host 'Informe o IP do projetor. Exemplo: .\restaurar-hy320.ps1 -Ip 192.168.0.15' -ForegroundColor Yellow
  exit 1
}
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Write-Host 'ADB nao encontrado. Instale com: winget install Google.PlatformTools (e abra um novo PowerShell).' -ForegroundColor Red
  exit 1
}

$alvo = "${Ip}:5555"
$arquivoDesativados = Join-Path $PSScriptRoot 'backup\desativados-por-otimizacao.txt'

function Sh([string]$cmd) { & adb -s $alvo shell $cmd }

& adb connect $alvo | Out-Null
$hardware = (Sh 'getprop ro.hardware') -join ''
if ($hardware.Trim() -ne 'sun50iw12p1') {
  Write-Host "ABORTADO: $alvo nao e o HY320 Mini (hardware='$hardware')." -ForegroundColor Red
  exit 1
}

# Valores originais de fabrica do firmware HY320mini_Android11_202506182038.
Sh 'settings put global window_animation_scale 1.0'
Sh 'settings put global transition_animation_scale 1.0'
Sh 'settings delete global animator_duration_scale' | Out-Null
Sh 'cmd wifi set-verbose-logging enabled' | Out-Null
Sh 'settings put global bluetooth_on 1'
Write-Host 'Ajustes de animacao, log de Wi-Fi e Bluetooth (vale no proximo boot) restaurados'

# Bloqueio de anuncios: volta ao DNS da rede e ao servidor de hora padrao.
Sh 'settings delete global private_dns_mode' | Out-Null
Sh 'settings delete global private_dns_specifier' | Out-Null
Sh 'settings delete global ntp_server' | Out-Null
Write-Host 'DNS privado (bloqueio de anuncios) removido'

# Volta a tela inicial original do fabricante.
Sh 'cmd package set-home-activity com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity' | Out-Null
Write-Host 'Tela inicial original restaurada'
if ($RemoverProjectivy) {
  Write-Host ("Removendo Projectivy: {0}" -f ((Sh 'pm uninstall com.spocky.projengmenu') -join ' '))
}

if (Test-Path $arquivoDesativados) {
  foreach ($pkg in (Get-Content $arquivoDesativados | Where-Object { $_ } | Select-Object -Unique)) {
    Write-Host ("Reativando {0}: {1}" -f $pkg, ((Sh "pm enable $pkg") -join ' '))
  }
  Remove-Item $arquivoDesativados -Confirm:$false
}

if ($ResetCompilacao) {
  Write-Host 'Descartando compilacao nativa (pode demorar)...'
  Sh 'cmd package compile --reset -a' | Select-Object -Last 1
}

Write-Host 'Concluido. Reinicie o projetor.' -ForegroundColor Green
