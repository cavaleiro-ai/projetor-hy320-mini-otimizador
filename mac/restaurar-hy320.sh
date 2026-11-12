#!/bin/bash
# Versao para macOS do restaurar-hy320.ps1.
# Desfaz o que o otimizar-hy320 fez no projetor HY320 Mini.
#
# Uso:
#   bash restaurar-hy320.sh --ip 192.168.0.15                        # reativa pacotes e volta os ajustes ao original
#   bash restaurar-hy320.sh --ip 192.168.0.15 --remover-projectivy   # tambem desinstala o Projectivy Launcher
#   bash restaurar-hy320.sh --ip 192.168.0.15 --reset-compilacao     # tambem descarta a compilacao nativa dos apps

DIR="$(cd "$(dirname "$0")" && pwd)"
PATH="$DIR:$DIR/platform-tools:$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Android/sdk/platform-tools"
export PATH

VERMELHO=$'\033[31m'; AMARELO=$'\033[33m'; VERDE=$'\033[32m'; NORMAL=$'\033[0m'

normaliza() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^-*//; s/-//g'; }

IP=""; RESET=0; REMOVER=0
while [ $# -gt 0 ]; do
  case "$(normaliza "$1")" in
    ip) shift; IP="$1" ;;
    resetcompilacao) RESET=1 ;;
    removerprojectivy) REMOVER=1 ;;
    *)
      if printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then IP="$1"
      else echo "${VERMELHO}Opcao desconhecida: $1${NORMAL}"; exit 1; fi ;;
  esac
  shift
done

if [ -z "$IP" ]; then
  echo "${AMARELO}Informe o IP do projetor. Exemplo: bash restaurar-hy320.sh --ip 192.168.0.15${NORMAL}"
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "${VERMELHO}ADB nao encontrado. Veja o passo 3 do mac/TUTORIAL.md.${NORMAL}"
  exit 1
fi

ALVO="$IP:5555"
ARQ_DESATIVADOS="$DIR/backup/desativados-por-otimizacao.txt"

sh_() { adb -s "$ALVO" shell "$1" </dev/null | tr -d '\r'; }

adb connect "$ALVO" >/dev/null 2>&1
hardware=$(sh_ 'getprop ro.hardware' | tr -d '\n')
if [ "$hardware" != "sun50iw12p1" ]; then
  echo "${VERMELHO}ABORTADO: $ALVO nao e o HY320 Mini (hardware='$hardware').${NORMAL}"
  exit 1
fi

# Valores originais de fabrica do firmware HY320mini_Android11_202506182038.
sh_ 'settings put global window_animation_scale 1.0'
sh_ 'settings put global transition_animation_scale 1.0'
sh_ 'settings delete global animator_duration_scale' >/dev/null
sh_ 'cmd wifi set-verbose-logging enabled' >/dev/null
sh_ 'settings put global bluetooth_on 1'
echo 'Ajustes de animacao, log de Wi-Fi e Bluetooth (vale no proximo boot) restaurados'

# Bloqueio de anuncios: volta ao DNS da rede e ao servidor de hora padrao.
sh_ 'settings delete global private_dns_mode' >/dev/null
sh_ 'settings delete global private_dns_specifier' >/dev/null
sh_ 'settings delete global ntp_server' >/dev/null
echo 'DNS privado (bloqueio de anuncios) removido'

# Volta a tela inicial original do fabricante.
# Usa a tela inicial salva no backup; sem backup, usa a do firmware do HY320 Mini.
tela_inicial='com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity'
if [ -s "$DIR/backup/tela-inicial-original.txt" ]; then
  salva=$(sed $'1s/^\xEF\xBB\xBF//' "$DIR/backup/tela-inicial-original.txt" | tr -d '\r' | head -1)
  case "$salva" in */*) [ "${salva%%/*}" != "com.spocky.projengmenu" ] && tela_inicial="$salva" ;; esac
fi
sh_ "cmd package set-home-activity $tela_inicial" >/dev/null
echo 'Tela inicial original restaurada'
if [ $REMOVER -eq 1 ]; then
  echo "Removendo Projectivy: $(sh_ 'pm uninstall com.spocky.projengmenu' | tr '\n' ' ')"
fi

if [ -f "$ARQ_DESATIVADOS" ]; then
  # Remove BOM e quebras de linha do Windows, caso o backup tenha sido criado pelo script .ps1.
  pacotes=$(sed $'1s/^\xEF\xBB\xBF//' "$ARQ_DESATIVADOS" | tr -d '\r' | awk 'NF && !visto[$0]++')
  for pkg in $pacotes; do
    echo "Reativando $pkg: $(sh_ "pm enable $pkg" | tr '\n' ' ')"
  done
  rm -f "$ARQ_DESATIVADOS"
fi

if [ $RESET -eq 1 ]; then
  echo 'Descartando compilacao nativa (pode demorar)...'
  sh_ 'cmd package compile --reset -a' | tail -1
fi

echo "${VERDE}Concluido. Reinicie o projetor.${NORMAL}"
