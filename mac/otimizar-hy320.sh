#!/bin/bash
# Versao para macOS do otimizar-hy320.ps1.
# Otimiza o projetor HY320 Mini (Allwinner H713, Android 11) via ADB pela rede.
# Tudo aqui e reversivel com: bash restaurar-hy320.sh --ip <ip>
#
# Uso:
#   bash otimizar-hy320.sh --ip 192.168.0.15              # basico: ajustes + testes de fabrica + compila apps
#   bash otimizar-hy320.sh --ip 192.168.0.15 --completo   # basico + as quatro opcoes abaixo
#
# Opcoes (cada uma tem uma contrapartida, por isso sao opcionais):
#   --bloquear-anuncios      usa o DNS privado do Android com o AdGuard DNS, que bloqueia dominios
#                            de anuncio e rastreamento no sistema inteiro, sem instalar app
#                            (nao remove anuncios dentro do YouTube; as consultas de DNS passam pelo AdGuard)
#   --desativar-fabricante   desativa a loja do fabricante e os atualizadores automaticos
#                            (o projetor deixa de receber atualizacoes do fabricante)
#   --desligar-bluetooth     Bluetooth inicia desligado (religue nas Configuracoes quando quiser)
#   --instalar-projectivy    instala o Projectivy Launcher como tela inicial
#                            (mais organizado, mas usa mais memoria que a tela original)
#   --desativar pkg1,pkg2    desativa outros pacotes informados
#   --pular-compilacao       nao recompila os apps (etapa demorada, 10 a 15 minutos)
#   --aceitar-modelo         aceita outro modelo com o mesmo chip (sun50iw12p1), ex.: HY300 Pro.
#                            O roteiro foi testado so no HY320 Mini; prefira o modo basico.
#
# Os nomes no estilo do Windows (-Ip, -Completo, -BloquearAnuncios...) tambem funcionam.

DIR="$(cd "$(dirname "$0")" && pwd)"
PATH="$DIR:$DIR/platform-tools:$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Android/sdk/platform-tools"
export PATH

VERMELHO=$'\033[31m'; AMARELO=$'\033[33m'; VERDE=$'\033[32m'; NORMAL=$'\033[0m'

normaliza() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^-*//; s/-//g'; }

IP=""; ACEITAR=0; COMPLETO=0; BLOQUEAR=0; FABRICANTE=0; BLUETOOTH=0; PROJECTIVY=0; PULAR=0; EXTRAS=""
while [ $# -gt 0 ]; do
  case "$(normaliza "$1")" in
    ip) shift; IP="$1" ;;
    completo) COMPLETO=1 ;;
    bloquearanuncios) BLOQUEAR=1 ;;
    desativarfabricante) FABRICANTE=1 ;;
    desligarbluetooth) BLUETOOTH=1 ;;
    instalarprojectivy) PROJECTIVY=1 ;;
    desativar) shift; EXTRAS="$EXTRAS $(printf '%s' "$1" | tr ',' ' ')" ;;
    pularcompilacao) PULAR=1 ;;
    aceitarmodelo) ACEITAR=1 ;;
    *)
      # Aceita o IP sem o --ip na frente.
      if printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then IP="$1"
      else echo "${VERMELHO}Opcao desconhecida: $1${NORMAL}"; exit 1; fi ;;
  esac
  shift
done

if [ -z "$IP" ]; then
  echo "${AMARELO}Informe o IP do projetor. Exemplo: bash otimizar-hy320.sh --ip 192.168.0.15${NORMAL}"
  echo 'Para descobrir o IP, rode bash encontrar-projetor.sh ou veja em Configuracoes > Rede e Internet no projetor.'
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "${VERMELHO}ADB nao encontrado. Veja o passo 3 do mac/TUTORIAL.md.${NORMAL}"
  exit 1
fi
if [ $COMPLETO -eq 1 ]; then BLOQUEAR=1; FABRICANTE=1; BLUETOOTH=1; PROJECTIVY=1; fi

ALVO="$IP:5555"
PASTA_BACKUP="$DIR/backup"
ARQ_DESATIVADOS="$PASTA_BACKUP/desativados-por-otimizacao.txt"

# Sem uso em um projetor: testes de fabrica da Allwinner (so servem na linha de producao)
# e a pilha de impressao do Android (o spooler sobe em todo boot).
TESTES_DE_FABRICA="com.softwinner.dragonbox com.softwinner.agingdragonbox com.softwinner.dragonatt
com.android.printspooler com.android.bips com.android.printservice.recommendation"

# DNS que bloqueia dominios de anuncio e rastreamento (as listas ficam no servidor e se atualizam sozinhas).
DNS_BLOQUEADOR='dns.adguard-dns.com'
# Servidor de hora por IP (time1.google.com). O DNS privado exige relogio certo para validar o
# certificado; se o relogio zerar por falta de energia, a hora precisa ser obtida sem depender de DNS.
SERVIDOR_DE_HORA='216.239.35.0'

# Loja do fabricante e atualizadores: ficam sempre em segundo plano e podem instalar apps sozinhos.
PACOTES_FABRICANTE="com.android.fungo com.uv.droid.uota com.uv.droid.uotaback com.adups.fota"

# Nao recompilar em "speed": apps enormes ou que ja usam perfil de uso (speed-profile).
NAO_COMPILAR="com.google.android.gms
com.android.vending
com.android.chrome
com.google.android.youtube.tv
com.wbd.stream"

PROJECTIVY_PKG='com.spocky.projengmenu'

sh_() { adb -s "$ALVO" shell "$1" </dev/null | tr -d '\r'; }
dns_privado_validou() { sh_ 'dumpsys connectivity' | grep -Eq 'ValidatedPrivateDnsAddresses: \[[^]]+\]'; }

# --- 1. Conexao e trava de seguranca: so continua se for mesmo o projetor ---
adb connect "$ALVO" >/dev/null 2>&1
estado=$(adb devices | tr -d '\r' | awk -v a="$ALVO" '$1==a{print $2}')
if [ "$estado" = "unauthorized" ]; then
  echo "${AMARELO}O projetor pediu autorizacao: olhe a tela dele, marque \"Sempre permitir\" e confirme. Depois rode de novo.${NORMAL}"
  exit 1
fi
if [ "$estado" != "device" ]; then
  echo "${VERMELHO}Nao consegui conectar em $ALVO. Confira o IP e se a Depuracao USB esta ligada no projetor.${NORMAL}"
  exit 1
fi
hardware=$(sh_ 'getprop ro.hardware' | tr -d '\n')
modelo=$(sh_ 'getprop ro.product.model' | tr -d '\n')
case "$modelo" in HY320*) eh_hy320=1 ;; *) eh_hy320=0 ;; esac
if [ "$hardware" != "sun50iw12p1" ]; then
  echo "${VERMELHO}ABORTADO: $ALVO nao e o HY320 Mini (hardware='$hardware', modelo='$modelo').${NORMAL}"
  exit 1
fi
if [ $eh_hy320 -eq 0 ]; then
  if [ $ACEITAR -eq 0 ]; then
    echo "${VERMELHO}ABORTADO: $ALVO nao e o HY320 Mini (hardware='$hardware', modelo='$modelo').${NORMAL}"
    echo "O chip e o mesmo do HY320 Mini. Para continuar mesmo assim, rode de novo com --aceitar-modelo"
    echo "(de preferencia no modo basico, sem --completo)."
    exit 1
  fi
  echo "${AMARELO}Aviso: modelo $modelo, nao testado. Continuando por causa do --aceitar-modelo.${NORMAL}"
fi
echo "Projetor confirmado: $modelo ($hardware) em $ALVO"

# --- 2. Backup do estado atual (so na primeira execucao, para preservar o original) ---
if [ ! -d "$PASTA_BACKUP" ]; then
  mkdir -p "$PASTA_BACKUP"
  for ns in global secure system; do
    sh_ "settings list $ns" > "$PASTA_BACKUP/settings-$ns.txt"
  done
  sh_ 'pm list packages -d' > "$PASTA_BACKUP/pacotes-desativados-original.txt"
  sh_ 'pm list packages -e' > "$PASTA_BACKUP/pacotes-ativos-original.txt"
  sh_ 'dumpsys package dexopt' > "$PASTA_BACKUP/dexopt-original.txt"
  # Tela inicial original, para o restaurar voltar exatamente a ela.
  sh_ 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME' |
    grep '/' | tail -1 > "$PASTA_BACKUP/tela-inicial-original.txt"
  echo "Backup do estado original salvo em $PASTA_BACKUP"
fi

# --- 3. Ajustes de sistema ---
sh_ 'settings put global window_animation_scale 0.5'
sh_ 'settings put global transition_animation_scale 0.5'
sh_ 'settings put global animator_duration_scale 0.5'
sh_ 'cmd wifi set-verbose-logging disabled' >/dev/null
echo 'Animacoes em 0.5x e log verboso de Wi-Fi desligado'

if [ $BLUETOOTH -eq 1 ]; then
  # O shell deste firmware nao tem BLUETOOTH_ADMIN ("svc bluetooth disable" falha),
  # entao grava-se o estado que o sistema le ao iniciar. Vale a partir do proximo boot.
  sh_ 'settings put global bluetooth_on 0'
  echo 'Bluetooth ficara desligado a partir do proximo reinicio'
fi

if [ $BLOQUEAR -eq 1 ]; then
  modo_antes=$(sh_ 'settings get global private_dns_mode' | tr -d '\n')
  servidor_antes=$(sh_ 'settings get global private_dns_specifier' | tr -d '\n')
  sh_ "settings put global ntp_server $SERVIDOR_DE_HORA"
  # Se ja esta ativo e validado, nao regrava: no Android 11, gravar a configuracao de DNS privado
  # duas vezes seguidas cancela a validacao em andamento e o sistema nao tenta de novo (fica sem DNS).
  validou=0
  if [ "$modo_antes" = "hostname" ] && [ "$servidor_antes" = "$DNS_BLOQUEADOR" ] && dns_privado_validou; then
    validou=1
  fi
  if [ $validou -eq 0 ]; then
    for _ in 1 2; do
      # Desliga, grava o servidor e so entao liga: assim ocorre uma unica validacao.
      sh_ 'settings put global private_dns_mode off'
      sleep 3
      sh_ "settings put global private_dns_specifier $DNS_BLOQUEADOR"
      sleep 2
      sh_ 'settings put global private_dns_mode hostname'
      # Confere se a conexao criptografada com o DNS validou; algumas redes bloqueiam a porta 853.
      for n in 1 2 3 4 5 6 7 8; do
        sleep 2
        if dns_privado_validou; then validou=1; break; fi
      done
      [ $validou -eq 1 ] && break
    done
  fi
  if [ $validou -eq 1 ]; then
    teste=$(sh_ 'ping -c1 -W2 doubleclick.net 2>&1 | head -1' | tr -d '\n')
    echo "Bloqueio de anuncios ativo ($DNS_BLOQUEADOR). Teste: $teste"
  else
    # Sem DNS o projetor fica sem internet: volta ao DNS da rede (padrao do Android).
    sh_ 'settings delete global private_dns_mode' >/dev/null
    sh_ 'settings delete global private_dns_specifier' >/dev/null
    sh_ 'settings delete global ntp_server' >/dev/null
    echo "${AMARELO}O DNS privado nao validou nesta rede (porta 853 bloqueada?). Bloqueio de anuncios NAO aplicado; DNS voltou ao original.${NORMAL}"
  fi
fi

# --- 4. Desativar pacotes (reversivel: pm enable) ---
lista="$TESTES_DE_FABRICA $EXTRAS"
[ $FABRICANTE -eq 1 ] && lista="$lista $PACOTES_FABRICANTE"
ja_desativados=$(sh_ 'pm list packages -d' | sed 's/^package://')
for pkg in $(printf '%s\n' $lista | awk 'NF && !visto[$0]++'); do
  if printf '%s\n' "$ja_desativados" | grep -qxF "$pkg"; then continue; fi
  r=$(sh_ "pm disable-user --user 0 $pkg 2>&1" | tr '\n' ' ')
  case "$r" in
    *disabled-user*)
      sh_ "am force-stop $pkg"
      echo "$pkg" >> "$ARQ_DESATIVADOS"
      echo "Desativado: $pkg" ;;
    *)
      echo "${AMARELO}Nao foi possivel desativar $pkg (pode nao existir neste firmware)${NORMAL}" ;;
  esac
done

# --- 5. Projectivy Launcher (opcional) ---
projectivy_instalado() { sh_ "pm list packages $PROJECTIVY_PKG" | grep -q "$PROJECTIVY_PKG"; }
if [ $PROJECTIVY -eq 1 ]; then
  if ! projectivy_instalado; then
    # Baixa a versao mais recente direto do repositorio oficial do desenvolvedor.
    json=$(curl -fsSL -H 'User-Agent: otimizar-hy320' 'https://api.github.com/repos/spocky/miproja1/releases/latest')
    url=$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.apk"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')
    if [ -z "$url" ]; then
      echo "${AMARELO}Nao consegui encontrar o APK do Projectivy no GitHub. Pulando esta etapa.${NORMAL}"
    else
      nome=$(basename "$url")
      apk="$DIR/$nome"
      echo "Baixando $nome..."
      if curl -fSL --retry 2 -o "$apk" "$url"; then
        echo "Instalando: $(adb -s "$ALVO" install -r "$apk" </dev/null 2>&1 | tr -d '\r' | tail -1)"
      else
        echo "${AMARELO}Falha ao baixar o Projectivy. Confira o espaco livre no Mac e a internet, e rode de novo.${NORMAL}"
      fi
      rm -f "$apk"
    fi
  fi
  # So troca a tela inicial se o Projectivy estiver mesmo instalado.
  if projectivy_instalado; then
    sh_ "cmd package set-home-activity $PROJECTIVY_PKG/.ui.home.MainActivity" >/dev/null
    echo 'Projectivy definido como tela inicial (conclua a tela de boas-vindas no projetor)'
  else
    echo "${AMARELO}Projectivy nao instalado; a tela inicial original foi mantida.${NORMAL}"
  fi
fi

# --- 6. Compilar apps para codigo nativo (maior ganho; leva varios minutos) ---
if [ $PULAR -eq 0 ]; then
  pacotes=$(sh_ 'pm list packages -e' | sed 's/^package://' | grep -v '^$' | grep -vxF "$NAO_COMPILAR" | sort)
  total=$(printf '%s\n' "$pacotes" | grep -c .)
  n=0
  for pkg in $pacotes; do
    n=$((n + 1))
    r=$(sh_ "cmd package compile -m speed $pkg" | tr '\n' ' ')
    echo "[$n/$total] $pkg: $r"
  done
  # Apps que ja tem perfil de uso: recompila guiado pelo perfil.
  for pkg in com.google.android.youtube.tv com.wbd.stream com.google.android.gms; do
    echo "$pkg: $(sh_ "cmd package compile -m speed-profile $pkg" | tr '\n' ' ')"
  done
fi

echo "${VERDE}Concluido. Reinicie o projetor e, depois, desligue a Depuracao USB nas opcoes do desenvolvedor.${NORMAL}"
