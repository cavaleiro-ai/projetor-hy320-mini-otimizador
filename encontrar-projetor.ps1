# Procura na rede local aparelhos Android com a Depuracao USB (ADB) ligada, na porta 5555.
# So verifica essa porta, em redes domesticas /24. Use apenas na sua propria rede.
#
# Uso:
#   .\encontrar-projetor.ps1                  # procura nas redes em que este PC esta
#   .\encontrar-projetor.ps1 -Rede 192.168.0  # procura em outra faixa (ex.: PC no cabo, projetor no Wi-Fi)
param(
  [string[]]$Rede = @()
)

# Permite usar um adb.exe copiado para a pasta dos scripts (o PowerShell nao procura na pasta atual).
$env:Path = "$PSScriptRoot;$env:Path"
# ADB recem-instalado pelo winget ainda nao esta no PATH deste terminal: procura na pasta dele.
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $adbWinget = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter 'Google.PlatformTools*' -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'platform-tools' } | Where-Object { Test-Path (Join-Path $_ 'adb.exe') } | Select-Object -First 1
  if ($adbWinget) { $env:Path = "$adbWinget;$env:Path" }
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Write-Host 'ADB nao encontrado. Instale com: winget install Google.PlatformTools (e abra um novo PowerShell).' -ForegroundColor Red
  exit 1
}

if (-not $Rede) {
  # Redes do proprio PC que tem gateway (ignora adaptadores virtuais sem saida).
  $comGateway = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }
  $Rede = @($comGateway | ForEach-Object { ($_.IPv4Address.IPAddress -split '\.')[0..2] -join '.' } | Select-Object -Unique)
}

$achados = @()
foreach ($prefixo in $Rede) {
  Write-Host "Procurando em $prefixo.1-254 ..."
  $tentativas = foreach ($i in 1..254) {
    $cliente = New-Object System.Net.Sockets.TcpClient
    [pscustomobject]@{ Ip = "$prefixo.$i"; Cliente = $cliente; Tarefa = $cliente.ConnectAsync("$prefixo.$i", 5555) }
  }
  Start-Sleep -Milliseconds 2500
  foreach ($t in $tentativas) {
    if ($t.Tarefa.Status -eq 'RanToCompletion' -and $t.Cliente.Connected) { $achados += $t.Ip }
    $t.Cliente.Close()
  }
}

if (-not $achados) {
  Write-Host 'Nenhum aparelho com a depuracao ligada foi encontrado.' -ForegroundColor Yellow
  Write-Host 'Confira: o projetor esta ligado e no Wi-Fi? A "Depuracao USB" esta ativada nas opcoes do desenvolvedor?'
  Write-Host 'Se o PC e o projetor estao em faixas diferentes, informe a faixa: .\encontrar-projetor.ps1 -Rede 192.168.0'
  exit 1
}

foreach ($ip in $achados) {
  $alvo = "${ip}:5555"
  & adb connect $alvo | Out-Null
  Start-Sleep -Milliseconds 800
  $estado = (& adb devices) | Where-Object { $_ -like "$alvo*" }
  if ($estado -match 'unauthorized') {
    Write-Host "$ip  ->  aguardando autorizacao: aceite o aviso na tela do aparelho e rode de novo" -ForegroundColor Yellow
  } elseif ($estado -match '\sdevice$') {
    $modelo = ((& adb -s $alvo shell 'getprop ro.product.model') -join '').Trim()
    $hardware = ((& adb -s $alvo shell 'getprop ro.hardware') -join '').Trim()
    if ($hardware -eq 'sun50iw12p1' -and $modelo -like 'HY320*') {
      Write-Host "$ip  ->  $modelo ($hardware)  <== este e o projetor" -ForegroundColor Green
      Write-Host "      Proximo passo: .\otimizar-hy320.ps1 -Ip $ip"
    } else {
      Write-Host "$ip  ->  $modelo ($hardware)  (outro aparelho; nao e o HY320 Mini)"
    }
  } else {
    Write-Host "$ip  ->  porta aberta, mas sem resposta do ADB"
  }
}
