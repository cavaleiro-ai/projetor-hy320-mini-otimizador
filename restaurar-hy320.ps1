# Desfaz o que o otimizar-hy320.ps1 fez no projetor HY320 / HY320 Mini.
#
# Uso:
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15                     # reativa pacotes e volta os ajustes ao original
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15 -RemoverProjectivy  # tambem desinstala o Projectivy Launcher
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15 -ResetCompilacao    # tambem descarta a compilacao nativa dos apps
#   .\restaurar-hy320.ps1 -Ip 192.168.0.15 -Simular            # so mostra o que faria, sem alterar nada
#
# Os valores originais vem de backup\estado-original.txt, gravado pelo otimizar-hy320.ps1.
# Sem esse arquivo (backup de uma versao antiga), usa os padroes de fabrica do firmware detectado.
param(
  [string]$Ip,
  [switch]$ResetCompilacao,
  [switch]$RemoverProjectivy,
  [switch]$Simular
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
$arquivoEstado = Join-Path $PSScriptRoot 'backup\estado-original.txt'
$projectivy = 'com.spocky.projengmenu'

# Telas iniciais de fabrica conhecidas (mesmos perfis do otimizar-hy320.ps1), para backups sem estado-original.txt.
$telasDeFabrica = [ordered]@{
  'com.chiptrip.install.launcher'     = 'com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity'
  'com.htc.htclauncherhighenglishd08' = 'com.htc.htclauncherhighenglishd08/com.htc.activity.HomeActivity'
}

function Sh([string]$cmd) {
  if ($Simular) { Write-Host "  [simulacao] adb shell $cmd" -ForegroundColor DarkGray; return }
  & adb -s $alvo shell $cmd
}
function Ler([string]$cmd) { ((& adb -s $alvo shell $cmd) -join '').Trim() }

& adb connect $alvo | Out-Null
$hardware = Ler 'getprop ro.hardware'
$modelo = Ler 'getprop ro.product.model'
if ($hardware -ne 'sun50iw12p1' -or $modelo -notlike 'HY320*') {
  Write-Host "ABORTADO: $alvo nao e um HY320 com Allwinner H713 (hardware='$hardware', modelo='$modelo')." -ForegroundColor Red
  exit 1
}
if ($Simular) { Write-Host '--- SIMULACAO: nada sera alterado ---' -ForegroundColor Cyan }

# Le os valores originais. "null" significa que a chave nao existia: nesse caso ela e apagada.
$original = @{}
if (Test-Path $arquivoEstado) {
  foreach ($linha in Get-Content $arquivoEstado) {
    if ($linha -match '^([^=]+)=(.*)$') { $original[$Matches[1].Trim()] = $Matches[2].Trim() }
  }
  Write-Host "Usando os valores originais de $arquivoEstado"
} else {
  Write-Host 'Sem backup\estado-original.txt (backup de versao antiga): usando os padroes de fabrica.' -ForegroundColor Yellow
  # Padroes de fabrica medidos no firmware HY320mini_Android11_202506182038.
  $original = @{
    window_animation_scale = '1.0'; transition_animation_scale = '1.0'; animator_duration_scale = 'null'
    private_dns_mode = 'null'; private_dns_specifier = 'null'; ntp_server = 'null'
    bluetooth_on = '1'; screensaver_enabled = ''
  }
}

function Restaurar([string]$ns, [string]$chave) {
  if (-not $original.ContainsKey($chave) -or $original[$chave] -eq '') { return }
  $v = $original[$chave]
  if ($v -eq 'null') { Sh "settings delete $ns $chave" | Out-Null } else { Sh "settings put $ns $chave $v" }
}

Restaurar 'global' 'window_animation_scale'
Restaurar 'global' 'transition_animation_scale'
Restaurar 'global' 'animator_duration_scale'
Sh 'cmd wifi set-verbose-logging enabled' | Out-Null
Restaurar 'global' 'bluetooth_on'
Write-Host 'Ajustes de animacao, log de Wi-Fi e Bluetooth (vale no proximo boot) restaurados'

# Bloqueio de anuncios: volta ao DNS e ao servidor de hora que o aparelho tinha.
# O modo e gravado por ultimo para ocorrer uma unica validacao do DNS privado.
Restaurar 'global' 'ntp_server'
Restaurar 'global' 'private_dns_specifier'
Restaurar 'global' 'private_dns_mode'
Write-Host 'DNS privado e servidor de hora restaurados'

Restaurar 'secure' 'screensaver_enabled'

# Volta a tela inicial que estava em uso antes da otimizacao.
$tela = $original['tela_inicial']
if (-not $tela -or $tela -like "$projectivy/*") {
  # Sem registro (ou o Projectivy ja era a tela inicial): usa a de fabrica que existir no aparelho.
  $instalados = @(& adb -s $alvo shell 'pm list packages') -replace 'package:', '' | ForEach-Object { $_.Trim() }
  $tela = $telasDeFabrica.GetEnumerator() | Where-Object { $instalados -contains $_.Key } | Select-Object -First 1 -ExpandProperty Value
}
if ($tela) {
  Sh "cmd package set-home-activity $tela" | Out-Null
  Write-Host "Tela inicial original restaurada: $tela"
} else {
  Write-Host 'Tela inicial de fabrica nao identificada neste firmware; a tela inicial atual foi mantida.' -ForegroundColor Yellow
}
if ($RemoverProjectivy) {
  Write-Host ("Removendo Projectivy: {0}" -f ((Sh "pm uninstall $projectivy") -join ' '))
}

if (Test-Path $arquivoDesativados) {
  foreach ($pkg in (Get-Content $arquivoDesativados | Where-Object { $_ } | Select-Object -Unique)) {
    Write-Host ("Reativando {0}: {1}" -f $pkg, ((Sh "pm enable $pkg") -join ' '))
  }
  if (-not $Simular) { Remove-Item $arquivoDesativados -Confirm:$false }
}

if ($ResetCompilacao) {
  Write-Host 'Descartando compilacao nativa (pode demorar)...'
  Sh 'cmd package compile --reset -a' | Select-Object -Last 1
}

Write-Host 'Concluido. Reinicie o projetor.' -ForegroundColor Green
