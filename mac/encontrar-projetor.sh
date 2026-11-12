#!/bin/bash
# Versao para macOS do encontrar-projetor.ps1.
# Procura na rede local aparelhos Android com a Depuracao USB (ADB) ligada, na porta 5555.
# So verifica essa porta, em redes domesticas /24. Use apenas na sua propria rede.
#
# Uso:
#   bash encontrar-projetor.sh                      # procura na rede em que este Mac esta
#   bash encontrar-projetor.sh --rede 192.168.0     # procura em outra faixa (pode repetir --rede)

DIR="$(cd "$(dirname "$0")" && pwd)"

# Procura o adb: na pasta dos scripts, na subpasta platform-tools (download direto do Google),
# no Homebrew e no SDK do Android Studio.
PATH="$DIR:$DIR/platform-tools:$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Android/sdk/platform-tools"
export PATH

VERMELHO=$'\033[31m'; AMARELO=$'\033[33m'; VERDE=$'\033[32m'; NORMAL=$'\033[0m'

# Aceita --rede, -Rede, -rede etc.
normaliza() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^-*//; s/-//g'; }

REDES=()
while [ $# -gt 0 ]; do
  case "$(normaliza "$1")" in
    rede) shift; REDES+=("${1%.}") ;;
    *) echo "${VERMELHO}Opcao desconhecida: $1${NORMAL}"; exit 1 ;;
  esac
  shift
done

if ! command -v adb >/dev/null 2>&1; then
  echo "${VERMELHO}ADB nao encontrado. Veja o passo 3 do mac/TUTORIAL.md.${NORMAL}"
  exit 1
fi

if [ ${#REDES[@]} -eq 0 ]; then
  # Rede da interface que tem a rota padrao (a que sai para a internet).
  iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  ip=""
  [ -n "$iface" ] && ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
  if [ -z "$ip" ]; then
    for i in en0 en1 en2; do ip=$(ipconfig getifaddr "$i" 2>/dev/null) && [ -n "$ip" ] && break; done
  fi
  if [ -z "$ip" ]; then
    echo "${VERMELHO}Nao consegui descobrir a rede deste Mac. Informe a faixa: bash encontrar-projetor.sh --rede 192.168.0${NORMAL}"
    exit 1
  fi
  REDES=("${ip%.*}")
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/achados"

for prefixo in "${REDES[@]}"; do
  echo "Procurando em $prefixo.1-254 ..."
  for i in $(seq 1 254); do
    ( nc -z -G 2 -w 2 "$prefixo.$i" 5555 >/dev/null 2>&1 && echo "$prefixo.$i" >> "$tmp/achados" ) &
  done
  wait
done

achados=$(sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n "$tmp/achados")

if [ -z "$achados" ]; then
  echo "${AMARELO}Nenhum aparelho com a depuracao ligada foi encontrado.${NORMAL}"
  echo 'Confira: o projetor esta ligado e no Wi-Fi? A "Depuracao USB" esta ativada nas opcoes do desenvolvedor?'
  echo 'No macOS 15 ou mais novo, o Terminal precisa de permissao de "Rede Local" (veja Problemas comuns).'
  echo 'Se o Mac e o projetor estao em faixas diferentes, informe a faixa: bash encontrar-projetor.sh --rede 192.168.0'
  exit 1
fi

for ip in $achados; do
  alvo="$ip:5555"
  adb connect "$alvo" >/dev/null 2>&1
  sleep 0.8
  estado=$(adb devices | tr -d '\r' | awk -v a="$alvo" '$1==a{print $2}')
  if [ "$estado" = "unauthorized" ]; then
    echo "${AMARELO}$ip  ->  aguardando autorizacao: aceite o aviso na tela do aparelho e rode de novo${NORMAL}"
  elif [ "$estado" = "device" ]; then
    modelo=$(adb -s "$alvo" shell 'getprop ro.product.model' | tr -d '\r\n')
    hardware=$(adb -s "$alvo" shell 'getprop ro.hardware' | tr -d '\r\n')
    case "$modelo" in HY320*) eh_hy320=1 ;; *) eh_hy320=0 ;; esac
    if [ "$hardware" = "sun50iw12p1" ] && [ $eh_hy320 -eq 1 ]; then
      echo "${VERDE}$ip  ->  $modelo ($hardware)  <== este e o projetor${NORMAL}"
      echo "      Proximo passo: bash otimizar-hy320.sh --ip $ip"
    elif [ "$hardware" = "sun50iw12p1" ]; then
      echo "${AMARELO}$ip  ->  $modelo ($hardware)  mesmo chip do HY320 Mini, modelo nao testado${NORMAL}"
      echo "      Se for o seu projetor: bash otimizar-hy320.sh --ip $ip --aceitar-modelo"
    else
      echo "$ip  ->  $modelo ($hardware)  (outro aparelho; nao e o HY320 Mini)"
    fi
  else
    echo "$ip  ->  porta aberta, mas sem resposta do ADB"
  fi
done
