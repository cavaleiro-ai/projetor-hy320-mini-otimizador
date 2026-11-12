#!/system/bin/sh
# Mede o tempo de abertura a frio (am start -W, TotalTime) de alguns apps
# com o filtro de compilacao original (verify) e com o otimizado (speed).
# No final todos os apps ficam em speed.
# Leva cerca de 15 minutos; os apps abrem e fecham sozinhos na tela.
# Uso (troque o IP pelo do seu projetor):
#   adb -s 192.168.0.15:5555 push ferramentas/medir-abertura.sh /data/local/tmp/
#   adb -s 192.168.0.15:5555 shell sh /data/local/tmp/medir-abertura.sh
# Cada linha da saida: <pacote> <verify|speed> <TotalTime em ms>
N=5
medir() { # <pkg> <componente> <modo>
  cmd package compile -m $3 -f $1 >/dev/null 2>&1
  am force-stop $1; sleep 2
  am start -W -n $2 >/dev/null 2>&1; sleep 3   # aquecimento, descartado
  i=0
  while [ $i -lt $N ]; do
    am force-stop $1; sleep 3
    t=$(am start -W -n $2 2>&1 | grep TotalTime | sed 's/[^0-9]//g')
    echo "$1 $3 $t"
    sleep 3
    i=$((i+1))
  done
  am force-stop $1
}
while read PKG CMP; do
  [ -z "$PKG" ] && continue
  medir $PKG $CMP verify
  medir $PKG $CMP speed
  echo "$PKG estado $(dumpsys package dexopt | grep -A2 "\[$PKG\]" | grep -o 'status=[a-z-]*')"
done <<EOF
com.android.tv.settings com.android.tv.settings/.MainSettings
com.softwinner.TvdFileManager com.softwinner.TvdFileManager/.MainUI
com.android.gallery3d com.android.gallery3d/.app.GalleryActivity
com.android.music com.android.music/.MusicBrowserActivity
com.chiptrip.install.launcher com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity
EOF
input keyevent KEYCODE_HOME
echo FIM
