#!/system/bin/sh
# Mede o bloqueio de anuncios do projetor: tenta resolver enderecos conhecidos de anuncio
# e rastreamento e conta quantos o DNS em uso bloqueia. Depois confere se os enderecos de
# que os apps precisam (YouTube, Netflix, Play Store...) continuam resolvendo.
#
# Uso, a partir do PC:
#   adb -s <ip>:5555 push ferramentas/testar-bloqueio.sh /data/local/tmp/
#   adb -s <ip>:5555 shell sh /data/local/tmp/testar-bloqueio.sh
#   adb -s <ip>:5555 shell sh /data/local/tmp/testar-bloqueio.sh -v    # lista o que passou
#
# Nao altera nada no aparelho. Leva de 1 a 3 minutos.
# "Bloqueado" = o DNS respondeu com endereco nulo (0.0.0.0, 127.x) ou disse que nao existe.

VERBOSO=$1

GOOGLE="doubleclick.net ad.doubleclick.net googleads.g.doubleclick.net pubads.g.doubleclick.net
securepubads.g.doubleclick.net pagead2.googlesyndication.com tpc.googlesyndication.com
googlesyndication.com www.googleadservices.com adservice.google.com www.googletagservices.com
imasdk.googleapis.com s0.2mdn.net"

APPS="unityads.unity3d.com config.unityads.unity3d.com auction.unityads.unity3d.com ms.applovin.com
rt.applovin.com d.applovin.com init.supersonicads.com outcome-ssp.supersonicads.com api.vungle.com
ads30.adcolony.com live.chartboost.com sdkm.w.inmobi.com an.facebook.com setting.rayjump.com
api16-access-sg.pangle.io sf16-fe-tos-sg.i18n-pglstatp.com startappservice.com adtilt.com"

SITES="ib.adnxs.com static.criteo.net bidder.criteo.com cdn.taboola.com trc.taboola.com
widgets.outbrain.com fastlane.rubiconproject.com ads.pubmatic.com u.openx.net aax.amazon-adsystem.com
c.amazon-adsystem.com match.adsrvr.org htlb.casalemedia.com www.smartadserver.com static.media.net
ads.yahoo.com cdn.mgid.com ads.linkedin.com ads.pinterest.com static.ads-twitter.com ads-api.tiktok.com"

POPUPS="popads.net popcash.net propellerads.com exoclick.com juicyads.com adsterra.com clickadu.com
onclickads.net adcash.com monetag.com a-ads.com"

RASTREIO="www.google-analytics.com ssl.google-analytics.com app-measurement.com
firebaselogging-pa.googleapis.com appsflyer.com t.appsflyer.com app.adjust.com api2.branch.io
graph.facebook.com connect.facebook.net pixel.facebook.com analytics.tiktok.com script.hotjar.com
api.mixpanel.com api.segment.io api.amplitude.com bam.nr-data.net www.clarity.ms mc.yandex.ru
bat.bing.com analytics.twitter.com sb.scorecardresearch.com pixel.quantserve.com events.reddit.com"

TV="samsungads.com us.info.lgsmartad.com ngfts.lge.com ads.roku.com device-metrics-us.amazon.com
mads.amazon-adsystem.com data.mistat.xiaomi.com tracking.miui.com api.ad.xiaomi.com ads.youtube.com
bigdata.adups.com adups.com logs.netflix.com ads.hulu.com"

NECESSARIOS="www.youtube.com i.ytimg.com youtubei.googleapis.com s.youtube.com redirector.googlevideo.com
play.google.com android.clients.google.com play.googleapis.com connectivitycheck.gstatic.com
www.gstatic.com fonts.googleapis.com accounts.google.com www.googleapis.com dl.google.com
mtalk.google.com firebaseinstallations.googleapis.com www.google.com www.netflix.com
api-global.netflix.com assets.nflxext.com www.primevideo.com atv-ps.amazon.com api.amazon.com
www.max.com www.hbomax.com www.paramountplus.com www.disneyplus.com globoplay.globo.com www.twitch.tv
open.spotify.com pluto.tv github.com raw.githubusercontent.com api.github.com www.wikipedia.org
www.whatsapp.com www.facebook.com www.instagram.com www.tiktok.com x.com www.amazon.com.br
www.mercadolivre.com.br www.globo.com www.uol.com.br"

# Devolve 0 se o endereco esta bloqueado.
bloqueado() {
  l=$(ping -c 1 -W 1 $1 2>&1 | head -1)
  case "$l" in
    *"(0.0.0.0)"*|*"(127."*|*"(::)"*|*"(::1)"*|*nknown*host*|*"bad address"*) return 0 ;;
    PING*) return 1 ;;
    *) return 0 ;;
  esac
}

if bloqueado www.google.com; then
  echo "ERRO: o projetor nao resolve www.google.com. Sem internet ou DNS fora do ar; teste cancelado."
  exit 1
fi

echo "DNS privado: $(settings get global private_dns_mode) $(settings get global private_dns_specifier)"
echo

TOTAL=0
TOTALB=0
grupo() { # <titulo> <lista>
  n=0; b=0; passou=""
  for d in $2; do
    n=$((n+1))
    if bloqueado $d; then b=$((b+1)); else passou="$passou $d"; fi
  done
  printf '%-34s %3d de %3d bloqueados\n' "$1" $b $n
  if [ -n "$VERBOSO" ] && [ -n "$passou" ]; then echo "    passou:$passou"; fi
  TOTAL=$((TOTAL+n)); TOTALB=$((TOTALB+b))
}

grupo "Anuncios do Google"            "$GOOGLE"
grupo "Anuncios dentro de apps"       "$APPS"
grupo "Anuncios em sites"             "$SITES"
grupo "Pop-ups e anuncios agressivos" "$POPUPS"
grupo "Rastreadores e medicao"        "$RASTREIO"
grupo "TV, streaming e fabricantes"   "$TV"
echo "----------------------------------------------------------"
printf '%-34s %3d de %3d bloqueados (%d%%)\n' "TOTAL" $TOTALB $TOTAL $((TOTALB*100/TOTAL))
echo

n=0; q=0; quebrou=""
for d in $NECESSARIOS; do
  n=$((n+1))
  if bloqueado $d; then q=$((q+1)); quebrou="$quebrou $d"; fi
done
printf '%-34s %3d de %3d funcionando\n' "Enderecos que os apps precisam" $((n-q)) $n
if [ -n "$quebrou" ]; then echo "    BLOQUEADO POR ENGANO:$quebrou"; fi
