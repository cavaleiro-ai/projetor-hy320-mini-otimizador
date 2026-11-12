# Otimiza o projetor HY320 Mini (Allwinner H713, Android 11) via ADB pela rede.
# Tudo aqui e reversivel com .\restaurar-hy320.ps1
#
# Uso:
#   .\otimizar-hy320.ps1 -Ip 192.168.0.15              # basico: ajustes + testes de fabrica + compila apps
#   .\otimizar-hy320.ps1 -Ip 192.168.0.15 -Completo    # basico + as quatro opcoes abaixo
#
# Opcoes (cada uma tem uma contrapartida, por isso sao opcionais):
#   -BloquearAnuncios      usa o DNS privado do Android com o AdGuard DNS, que bloqueia dominios
#                          de anuncio e rastreamento no sistema inteiro, sem instalar app
#                          (nao remove anuncios dentro do YouTube; as consultas de DNS passam pelo AdGuard)
#   -DesativarFabricante   desativa a loja do fabricante e os atualizadores automaticos
#                          (o projetor deixa de receber atualizacoes do fabricante)
#   -DesligarBluetooth     Bluetooth inicia desligado (religue nas Configuracoes quando quiser)
#   -InstalarProjectivy    instala o Projectivy Launcher como tela inicial
#                          (mais organizado, mas usa mais memoria que a tela original)
#   -Desativar pkg1,pkg2   desativa outros pacotes informados
#   -PularCompilacao       nao recompila os apps (etapa demorada, 10 a 15 minutos)
param(
  [string]$Ip,
  [switch]$Completo,
  [switch]$BloquearAnuncios,
  [switch]$DesativarFabricante,
  [switch]$DesligarBluetooth,
  [switch]$InstalarProjectivy,
  [string[]]$Desativar = @(),
  [switch]$PularCompilacao
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
  Write-Host 'Informe o IP do projetor. Exemplo: .\otimizar-hy320.ps1 -Ip 192.168.0.15' -ForegroundColor Yellow
  Write-Host 'Para descobrir o IP, rode .\encontrar-projetor.ps1 ou veja em Configuracoes > Rede e Internet no projetor.'
  exit 1
}
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Write-Host 'ADB nao encontrado. Instale com: winget install Google.PlatformTools (e abra um novo PowerShell).' -ForegroundColor Red
  exit 1
}
if ($Completo) { $BloquearAnuncios = $true; $DesativarFabricante = $true; $DesligarBluetooth = $true; $InstalarProjectivy = $true }

# Chamado com "powershell -File", "a,b" chega como um texto unico: separa aqui.
$Desativar = @($Desativar | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$alvo = "${Ip}:5555"
$pastaBackup = Join-Path $PSScriptRoot 'backup'
$arquivoDesativados = Join-Path $pastaBackup 'desativados-por-otimizacao.txt'

# Sem uso em um projetor: testes de fabrica da Allwinner (so servem na linha de producao)
# e a pilha de impressao do Android (o spooler sobe em todo boot).
$testesDeFabrica = 'com.softwinner.dragonbox', 'com.softwinner.agingdragonbox', 'com.softwinner.dragonatt',
                   'com.android.printspooler', 'com.android.bips', 'com.android.printservice.recommendation'

# DNS que bloqueia dominios de anuncio e rastreamento (as listas ficam no servidor e se atualizam sozinhas).
$dnsBloqueador = 'dns.adguard-dns.com'
# Servidor de hora por IP (time1.google.com). O DNS privado exige relogio certo para validar o
# certificado; se o relogio zerar por falta de energia, a hora precisa ser obtida sem depender de DNS.
$servidorDeHora = '216.239.35.0'

# Loja do fabricante e atualizadores: ficam sempre em segundo plano e podem instalar apps sozinhos.
$pacotesFabricante = 'com.android.fungo', 'com.uv.droid.uota', 'com.uv.droid.uotaback', 'com.adups.fota'

# Nao recompilar em "speed": apps enormes ou que ja usam perfil de uso (speed-profile).
$naoCompilar = 'com.google.android.gms', 'com.android.vending', 'com.android.chrome',
               'com.google.android.youtube.tv', 'com.wbd.stream'

$projectivy = 'com.spocky.projengmenu'

function Sh([string]$cmd) { & adb -s $alvo shell $cmd }
function DnsPrivadoValidou { ((Sh 'dumpsys connectivity') -join ' ') -match 'ValidatedPrivateDnsAddresses: \[[^\]]+\]' }

# --- 1. Conexao e trava de seguranca: so continua se for mesmo o projetor ---
& adb connect $alvo | Out-Null
$estado = (& adb devices) | Where-Object { $_ -like "$alvo*" }
if ($estado -match 'unauthorized') {
  Write-Host 'O projetor pediu autorizacao: olhe a tela dele, marque "Sempre permitir" e confirme. Depois rode de novo.' -ForegroundColor Yellow
  exit 1
}
if ($estado -notmatch '\sdevice$') {
  Write-Host "Nao consegui conectar em $alvo. Confira o IP e se a Depuracao USB esta ligada no projetor." -ForegroundColor Red
  exit 1
}
$hardware = (Sh 'getprop ro.hardware') -join ''
$modelo = (Sh 'getprop ro.product.model') -join ''
if ($hardware.Trim() -ne 'sun50iw12p1' -or $modelo.Trim() -notlike 'HY320*') {
  Write-Host "ABORTADO: $alvo nao e o HY320 Mini (hardware='$hardware', modelo='$modelo')." -ForegroundColor Red
  exit 1
}
Write-Host "Projetor confirmado: $modelo ($hardware) em $alvo"

# --- 2. Backup do estado atual (so na primeira execucao, para preservar o original) ---
if (-not (Test-Path $pastaBackup)) {
  New-Item -ItemType Directory -Path $pastaBackup | Out-Null
  foreach ($ns in 'global', 'secure', 'system') {
    Sh "settings list $ns" | Out-File -Encoding utf8 (Join-Path $pastaBackup "settings-$ns.txt")
  }
  Sh 'pm list packages -d' | Out-File -Encoding utf8 (Join-Path $pastaBackup 'pacotes-desativados-original.txt')
  Sh 'pm list packages -e' | Out-File -Encoding utf8 (Join-Path $pastaBackup 'pacotes-ativos-original.txt')
  Sh 'dumpsys package dexopt' | Out-File -Encoding utf8 (Join-Path $pastaBackup 'dexopt-original.txt')
  Write-Host "Backup do estado original salvo em $pastaBackup"
}

# --- 3. Ajustes de sistema ---
Sh 'settings put global window_animation_scale 0.5'
Sh 'settings put global transition_animation_scale 0.5'
Sh 'settings put global animator_duration_scale 0.5'
Sh 'cmd wifi set-verbose-logging disabled' | Out-Null
Write-Host 'Animacoes em 0.5x e log verboso de Wi-Fi desligado'

if ($DesligarBluetooth) {
  # O shell deste firmware nao tem BLUETOOTH_ADMIN ("svc bluetooth disable" falha),
  # entao grava-se o estado que o sistema le ao iniciar. Vale a partir do proximo boot.
  # Se o usuario ligar nas Configuracoes, o Android volta a lembrar "ligado".
  Sh 'settings put global bluetooth_on 0'
  Write-Host 'Bluetooth ficara desligado a partir do proximo reinicio'
}

if ($BloquearAnuncios) {
  $modoAntes = ((Sh 'settings get global private_dns_mode') -join '').Trim()
  $servidorAntes = ((Sh 'settings get global private_dns_specifier') -join '').Trim()
  Sh "settings put global ntp_server $servidorDeHora"
  # Se ja esta ativo e validado, nao regrava: no Android 11, gravar a configuracao de DNS privado
  # duas vezes seguidas cancela a validacao em andamento e o sistema nao tenta de novo (fica sem DNS).
  $validou = ($modoAntes -eq 'hostname' -and $servidorAntes -eq $dnsBloqueador -and (DnsPrivadoValidou))
  if (-not $validou) {
    foreach ($tentativa in 1..2) {
      # Desliga, grava o servidor e so entao liga: assim ocorre uma unica validacao.
      Sh 'settings put global private_dns_mode off'
      Start-Sleep -Seconds 3
      Sh "settings put global private_dns_specifier $dnsBloqueador"
      Start-Sleep -Seconds 2
      Sh 'settings put global private_dns_mode hostname'
      # Confere se a conexao criptografada com o DNS validou; algumas redes bloqueiam a porta 853.
      foreach ($n in 1..8) { Start-Sleep -Seconds 2; if (DnsPrivadoValidou) { $validou = $true; break } }
      if ($validou) { break }
    }
  }
  if ($validou) {
    $teste = ((Sh 'ping -c1 -W2 doubleclick.net 2>&1 | head -1') -join '')
    Write-Host "Bloqueio de anuncios ativo ($dnsBloqueador). Teste: $teste"
  } else {
    # Sem DNS o projetor fica sem internet: volta ao DNS da rede (padrao do Android).
    Sh 'settings delete global private_dns_mode' | Out-Null
    Sh 'settings delete global private_dns_specifier' | Out-Null
    Sh 'settings delete global ntp_server' | Out-Null
    Write-Host 'O DNS privado nao validou nesta rede (porta 853 bloqueada?). Bloqueio de anuncios NAO aplicado; DNS voltou ao original.' -ForegroundColor Yellow
  }
}

# --- 4. Desativar pacotes (reversivel: pm enable) ---
$lista = $testesDeFabrica + $Desativar
if ($DesativarFabricante) { $lista += $pacotesFabricante }
$jaDesativados = @(Sh 'pm list packages -d') -replace 'package:', ''
foreach ($pkg in ($lista | Select-Object -Unique)) {
  if ($jaDesativados -contains $pkg) { continue }
  $r = (Sh "pm disable-user --user 0 $pkg") -join ' '
  if ($r -match 'disabled-user') {
    Sh "am force-stop $pkg"
    Add-Content -Encoding utf8 -Path $arquivoDesativados -Value $pkg
    Write-Host "Desativado: $pkg"
  } else {
    Write-Host "Nao foi possivel desativar $pkg (pode nao existir neste firmware)" -ForegroundColor Yellow
  }
}

# --- 5. Projectivy Launcher (opcional) ---
if ($InstalarProjectivy) {
  if (-not ((Sh "pm list packages $projectivy") -join '' -match $projectivy)) {
    # Baixa a versao mais recente direto do repositorio oficial do desenvolvedor.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/spocky/miproja1/releases/latest' -Headers @{ 'User-Agent' = 'otimizar-hy320' }
    $asset = $release.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
    $apk = Join-Path $env:TEMP $asset.name
    Write-Host "Baixando $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $apk -UseBasicParsing
    Write-Host ("Instalando: {0}" -f ((& adb -s $alvo install -r $apk | Select-Object -Last 1) -join ' '))
    Remove-Item $apk -Confirm:$false
  }
  Sh "cmd package set-home-activity $projectivy/.ui.home.MainActivity" | Out-Null
  Write-Host 'Projectivy definido como tela inicial (conclua a tela de boas-vindas no projetor)'
}

# --- 6. Compilar apps para codigo nativo (maior ganho; leva varios minutos) ---
if (-not $PularCompilacao) {
  $pacotes = @(Sh 'pm list packages -e') -replace 'package:', '' | Where-Object { $_ -and $naoCompilar -notcontains $_ } | Sort-Object
  $n = 0
  foreach ($pkg in $pacotes) {
    $n++
    $r = (Sh "cmd package compile -m speed $pkg") -join ' '
    Write-Host ("[{0}/{1}] {2}: {3}" -f $n, $pacotes.Count, $pkg, $r)
  }
  # Apps que ja tem perfil de uso: recompila guiado pelo perfil.
  foreach ($pkg in 'com.google.android.youtube.tv', 'com.wbd.stream', 'com.google.android.gms') {
    Write-Host ("{0}: {1}" -f $pkg, ((Sh "cmd package compile -m speed-profile $pkg") -join ' '))
  }
}

Write-Host 'Concluido. Reinicie o projetor e, depois, desligue a Depuracao USB nas opcoes do desenvolvedor.' -ForegroundColor Green
