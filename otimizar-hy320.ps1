# Otimiza projetores HY320 / HY320 Mini (Allwinner H713, Android 11) via ADB pela rede.
# Tudo aqui e reversivel com .\restaurar-hy320.ps1
#
# Uso:
#   .\otimizar-hy320.ps1 -Ip 192.168.0.15              # basico: ajustes + testes de fabrica + compila apps
#   .\otimizar-hy320.ps1 -Ip 192.168.0.15 -Completo    # basico + as quatro opcoes abaixo
#   .\otimizar-hy320.ps1 -Ip 192.168.0.15 -Simular     # so mostra o que faria, sem alterar nada
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
#   -Simular               confere o aparelho, detecta o firmware e lista o que seria feito, sem alterar nada
#
# Firmwares reconhecidos (a lista de pacotes do fabricante muda de um para outro):
#   chiptrip  HY320mini_Android11_*, tela inicial com.chiptrip.install.launcher
#   htc       UI_Veng.projector.*,   tela inicial com.htc.htclauncherhighenglishd08
# Em firmware desconhecido, so os ajustes genericos sao aplicados.
param(
  [string]$Ip,
  [switch]$Completo,
  [switch]$BloquearAnuncios,
  [switch]$DesativarFabricante,
  [switch]$DesligarBluetooth,
  [switch]$InstalarProjectivy,
  [string[]]$Desativar = @(),
  [switch]$PularCompilacao,
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
$arquivoEstado = Join-Path $pastaBackup 'estado-original.txt'

# Sem uso em um projetor: testes de fabrica da Allwinner (so servem na linha de producao)
# e a pilha de impressao do Android (o spooler sobe em todo boot).
$testesDeFabrica = 'com.softwinner.dragonbox', 'com.softwinner.agingdragonbox', 'com.softwinner.dragonatt',
                   'com.android.printspooler', 'com.android.bips', 'com.android.printservice.recommendation'

# Perfis por firmware. "Marcador" e um pacote que so existe naquele firmware (a tela inicial de fabrica).
#   Testes:      apps de teste da linha de producao daquele fabricante (desativados sempre)
#   Fabricante:  loja, atualizadores e apps pre-instalados que ficam em segundo plano (-DesativarFabricante)
#   TelaInicial: atividade da tela inicial de fabrica (usada pelo restaurar se o backup nao a tiver)
$perfis = @(
  [pscustomobject]@{
    Nome        = 'chiptrip'
    Marcador    = 'com.chiptrip.install.launcher'
    Testes      = @()
    Fabricante  = @('com.android.fungo', 'com.uv.droid.uota', 'com.uv.droid.uotaback', 'com.adups.fota')
    TelaInicial = 'com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity'
  },
  [pscustomobject]@{
    Nome        = 'htc'
    Marcador    = 'com.htc.htclauncherhighenglishd08'
    Testes      = @('com.hotack.hotackfeaturestest', 'com.htc.hyk_test')
    # storeos: loja; htcotaupdate, rockchip.update.service e softwinner.update: atualizadores;
    # mobisystems.office: OfficeSuite pre-instalado que fica aberto em segundo plano.
    Fabricante  = @('com.htc.storeos', 'com.htc.htcotaupdate', 'android.rockchip.update.service',
                    'com.softwinner.update', 'com.mobisystems.office')
    TelaInicial = 'com.htc.htclauncherhighenglishd08/com.htc.activity.HomeActivity'
  }
)

# DNS que bloqueia dominios de anuncio e rastreamento (as listas ficam no servidor e se atualizam sozinhas).
$dnsBloqueador = 'dns.adguard-dns.com'
# Servidor de hora por IP (time1.google.com). O DNS privado exige relogio certo para validar o
# certificado; se o relogio zerar por falta de energia, a hora precisa ser obtida sem depender de DNS.
$servidorDeHora = '216.239.35.0'

# Nao recompilar em "speed": apps enormes ou que ja usam perfil de uso (speed-profile).
$naoCompilar = 'com.google.android.gms', 'com.android.vending', 'com.android.chrome',
               'com.google.android.youtube.tv', 'com.wbd.stream'
$compilarPorPerfil = 'com.google.android.youtube.tv', 'com.wbd.stream', 'com.google.android.gms'

# Compilar tudo em "speed" ocupa centenas de MB. Abaixo deste espaco livre usa "speed-profile",
# e abaixo do minimo para de compilar, para nao encher o armazenamento.
$livreParaSpeedMB = 1500
$livreMinimoMB = 500

$projectivy = 'com.spocky.projengmenu'

function Sh([string]$cmd) { & adb -s $alvo shell $cmd }
function Valor([string]$cmd) { ((Sh $cmd) -join '').Trim() }
function DnsPrivadoValidou { ((Sh 'dumpsys connectivity') -join ' ') -match 'ValidatedPrivateDnsAddresses: \[[^\]]+\]' }
function LivreMB {
  # df -k: Filesystem 1K-blocks Used Available Use% Mounted
  $campos = (Valor 'df -k /data | tail -1') -split '\s+'
  if ($campos.Count -ge 4 -and $campos[3] -match '^\d+$') { [math]::Floor([int64]$campos[3] / 1024) } else { -1 }
}
function TelaInicialAtual { (@(Sh 'cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN') | Select-Object -Last 1).Trim() }

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
$hardware = Valor 'getprop ro.hardware'
$modelo = Valor 'getprop ro.product.model'
if ($hardware -ne 'sun50iw12p1' -or $modelo -notlike 'HY320*') {
  Write-Host "ABORTADO: $alvo nao e um HY320 com Allwinner H713 (hardware='$hardware', modelo='$modelo')." -ForegroundColor Red
  exit 1
}
$firmware = Valor 'getprop ro.build.display.id'
$instalados = @(Sh 'pm list packages') -replace 'package:', '' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$perfil = $perfis | Where-Object { $instalados -contains $_.Marcador } | Select-Object -First 1
Write-Host "Projetor confirmado: $modelo ($hardware) em $alvo"
if ($perfil) {
  Write-Host "Firmware: $firmware (perfil '$($perfil.Nome)')"
} else {
  Write-Host "Firmware: $firmware - nao reconhecido. Serao aplicados so os ajustes genericos; a loja e os" -ForegroundColor Yellow
  Write-Host 'atualizadores do fabricante ficam como estao. Use -Desativar pkg1,pkg2 para desativar pacotes deste firmware.' -ForegroundColor Yellow
}

$lista = @($testesDeFabrica + $Desativar)
if ($perfil) {
  $lista += $perfil.Testes
  if ($DesativarFabricante) { $lista += $perfil.Fabricante }
}
$lista = @($lista | Select-Object -Unique)

if ($Simular) {
  $jaDesativados = @(Sh 'pm list packages -d') -replace 'package:', ''
  Write-Host ''
  Write-Host '--- SIMULACAO: nada sera alterado ---' -ForegroundColor Cyan
  Write-Host "Tela inicial atual: $(TelaInicialAtual)"
  Write-Host "Espaco livre em /data: $(LivreMB) MB"
  Write-Host 'Pacotes que seriam desativados:'
  foreach ($pkg in $lista) {
    $situacao = if ($instalados -notcontains $pkg) { 'nao existe neste firmware' } elseif ($jaDesativados -contains $pkg) { 'ja desativado' } else { 'desativar' }
    Write-Host ("  {0,-45} {1}" -f $pkg, $situacao)
  }
  if (-not $PularCompilacao) {
    $livre = LivreMB
    $modo = if ($livre -ge 0 -and $livre -lt $livreParaSpeedMB) { 'speed-profile (pouco espaco livre)' } else { 'speed' }
    Write-Host "Compilacao: modo $modo"
  }
  exit 0
}

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
# Valores que o restaurar usa para voltar exatamente ao que era (e nao a um padrao de outro firmware).
# Gravado uma vez so; backups de versoes antigas do script ganham o arquivo na proxima execucao.
if (-not (Test-Path $arquivoEstado)) {
  $original = [ordered]@{
    firmware                   = $firmware
    perfil                     = if ($perfil) { $perfil.Nome } else { '' }
    tela_inicial               = TelaInicialAtual
    window_animation_scale     = Valor 'settings get global window_animation_scale'
    transition_animation_scale = Valor 'settings get global transition_animation_scale'
    animator_duration_scale    = Valor 'settings get global animator_duration_scale'
    private_dns_mode           = Valor 'settings get global private_dns_mode'
    private_dns_specifier      = Valor 'settings get global private_dns_specifier'
    ntp_server                 = Valor 'settings get global ntp_server'
    bluetooth_on               = Valor 'settings get global bluetooth_on'
    screensaver_enabled        = Valor 'settings get secure screensaver_enabled'
  }
  $original.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Out-File -Encoding utf8 $arquivoEstado
  Write-Host "Valores originais gravados em $arquivoEstado"
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
  $modoAntes = Valor 'settings get global private_dns_mode'
  $servidorAntes = Valor 'settings get global private_dns_specifier'
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
$jaDesativados = @(Sh 'pm list packages -d') -replace 'package:', ''
foreach ($pkg in $lista) {
  if ($jaDesativados -contains $pkg) { continue }
  if ($instalados -notcontains $pkg) {
    Write-Host "Ignorado: $pkg (nao existe neste firmware)"
    continue
  }
  $r = (Sh "pm disable-user --user 0 $pkg") -join ' '
  if ($r -match 'disabled-user') {
    Sh "am force-stop $pkg"
    Add-Content -Encoding utf8 -Path $arquivoDesativados -Value $pkg
    Write-Host "Desativado: $pkg"
  } else {
    Write-Host "Nao foi possivel desativar ${pkg}: $r" -ForegroundColor Yellow
  }
}

# --- 5. Projectivy Launcher (opcional) ---
if ($InstalarProjectivy) {
  if ($instalados -notcontains $projectivy) {
    # Baixa a versao mais recente direto do repositorio oficial do desenvolvedor.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/spocky/miproja1/releases/latest' -Headers @{ 'User-Agent' = 'otimizar-hy320' }
    $asset = $release.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
    $apk = Join-Path $env:TEMP $asset.name
    Write-Host "Baixando $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $apk -UseBasicParsing
    # O GitHub publica o SHA-256 de cada arquivo da release (campo "digest"): confere antes de instalar.
    $hash = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
    if ($asset.digest -and $asset.digest -ne "sha256:$hash") {
      Remove-Item $apk -Confirm:$false
      Write-Host "ABORTADO: o arquivo baixado nao confere com o SHA-256 publicado no GitHub ($($asset.digest))." -ForegroundColor Red
      exit 1
    }
    if ($asset.digest) { Write-Host "SHA-256 conferido: $hash" } else { Write-Host "O GitHub nao publicou o SHA-256 deste arquivo; baixado: $hash" -ForegroundColor Yellow }
    Write-Host ("Instalando: {0}" -f ((& adb -s $alvo install -r $apk | Select-Object -Last 1) -join ' '))
    Remove-Item $apk -Confirm:$false
  }
  $telaAntes = TelaInicialAtual
  Sh "cmd package set-home-activity $projectivy/.ui.home.MainActivity" | Out-Null
  Write-Host 'Projectivy definido como tela inicial (conclua a tela de boas-vindas no projetor)'

  # Em alguns firmwares (ex.: perfil htc) o protetor de tela pertence a tela inicial de fabrica:
  # quando ele liga, a tela antiga volta a ser carregada (130+ MB) mesmo com o Projectivy em uso.
  $protetor = Valor 'settings get secure screensaver_components'
  $pacoteTelaAntiga = ($telaAntes -split '/')[0]
  if ($perfil) { $pacoteTelaAntiga = ($perfil.TelaInicial -split '/')[0] }
  if ($pacoteTelaAntiga -and $pacoteTelaAntiga -ne $projectivy -and $protetor -like "$pacoteTelaAntiga/*") {
    Sh 'settings put secure screensaver_enabled 0'
    Sh "am force-stop $pacoteTelaAntiga"
    Write-Host 'Protetor de tela desligado: ele fazia parte da tela inicial antiga e a recarregava na memoria'
  }
}

# --- 6. Compilar apps para codigo nativo (maior ganho; leva varios minutos) ---
if (-not $PularCompilacao) {
  $livre = LivreMB
  $modo = 'speed'
  if ($livre -ge 0 -and $livre -lt $livreParaSpeedMB) {
    $modo = 'speed-profile'
    Write-Host "Pouco espaco livre ($livre MB): compilando em speed-profile, que ocupa bem menos que speed." -ForegroundColor Yellow
  }
  $pacotes = @(Sh 'pm list packages -e') -replace 'package:', '' | Where-Object { $_ -and $naoCompilar -notcontains $_ } | Sort-Object
  $n = 0
  foreach ($pkg in $pacotes) {
    $n++
    if ($n % 10 -eq 0) {
      $livre = LivreMB
      if ($livre -ge 0 -and $livre -lt $livreMinimoMB) {
        Write-Host "Compilacao interrompida: so $livre MB livres. Libere espaco e rode de novo com o mesmo comando." -ForegroundColor Yellow
        break
      }
    }
    $r = (Sh "cmd package compile -m $modo $pkg") -join ' '
    Write-Host ("[{0}/{1}] {2}: {3}" -f $n, $pacotes.Count, $pkg, $r)
  }
  # Apps que ja tem perfil de uso: recompila guiado pelo perfil.
  foreach ($pkg in ($compilarPorPerfil | Where-Object { $instalados -contains $_ })) {
    Write-Host ("{0}: {1}" -f $pkg, ((Sh "cmd package compile -m speed-profile $pkg") -join ' '))
  }
  Write-Host "Espaco livre depois da compilacao: $(LivreMB) MB"
}

Write-Host 'Concluido. Reinicie o projetor e, depois, desligue a Depuracao USB nas opcoes do desenvolvedor.' -ForegroundColor Green
