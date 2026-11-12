# Caso de referência: HY320 com firmware HTC

Segunda variante do HY320 otimizada com este fluxo, em novembro de 2026. Mesmo chip (Allwinner H713) e mesma família de firmware do [HY320 Mini](hy320-mini.md), mas outro fabricante de placa: a tela inicial, a loja e os atualizadores têm outros nomes de pacote. Os scripts reconhecem este firmware como perfil `htc`.

## Identificação

| Propriedade | Valor |
|---|---|
| `ro.product.model` | `HY320` (sem "mini") |
| `ro.hardware` | `sun50iw12p1` (Allwinner H713) |
| `ro.board.platform` | `ares` |
| `ro.product.manufacturer` | `askey` (emprestado do ADT-3) |
| `ro.build.display.id` | `UI_Veng.projector.20240716.162721` |
| `ro.build.fingerprint` | `ADT-3/adt3/adt3:11/RP1A.201005.006/eng.projector.20240716.162721:user/release-keys` |
| CPU / ABI | espaço de usuário 32 bits: `ro.product.cpu.abilist=armeabi-v7a,armeabi` |
| RAM | 954 MB, `ro.config.low_ram=true`, `dalvik.vm.heapsize=256m` |
| Armazenamento | 8 GB no total; `/data` com 3,8 GB e só 1,3 GB livres de fábrica |
| Tela | o sistema desenha em 1920x1080 a 60 Hz, densidade 320 |
| SELinux | permissivo |
| Tela inicial de fábrica | `com.htc.htclauncherhighenglishd08/com.htc.activity.HomeActivity` |
| Protetor de tela | `com.htc.htclauncherhighenglishd08/com.htc.screensaver.ScreenSaverService` (faz parte da tela inicial) |

Ao escolher um APK para instalar por ADB, use a variante `armeabi-v7a` ou `universal`: a `arm64-v8a` não instala.

## Pacotes

### Desativados sem perguntar (testes de fábrica)

Os mesmos três testes da Allwinner do HY320 Mini, a pilha de impressão e mais dois testes deste fabricante:

| Pacote | O que é |
|---|---|
| `com.hotack.hotackfeaturestest` | teste de funções da linha de produção |
| `com.htc.hyk_test` | teste de fábrica |

### Desativados com autorização do usuário (`-DesativarFabricante`)

| Pacote | O que é | Memória em repouso |
|---|---|---|
| `com.htc.storeos` | loja de apps do fabricante | 22 MB |
| `com.htc.htcotaupdate` | atualizador do fabricante | 22 MB |
| `android.rockchip.update.service` | atualizador (nome de Rockchip em placa Allwinner) | sob demanda |
| `com.softwinner.update` | atualizador da Allwinner | sob demanda |
| `com.mobisystems.office` | OfficeSuite pré-instalado, aberto em segundo plano | 17 MB |

### Mantidos (não desativar)

| Pacote | Por que fica |
|---|---|
| `com.htc.htcsettings` | menu de imagem do projetor (keystone, foco, fonte) |
| `com.htc.closedialog` | diálogo de desligar |
| `com.htc.htclauncherhighenglishd08` | tela inicial original, fica como reserva |
| `com.hotack.writesn` | grava o número de série |
| `com.softwinner.awtvinputservice`, `com.softwinner.awsource`, `com.softwinner.awlivetv`, `com.softwinner.vis` | entrada HDMI e seleção de fonte |
| `com.softwinner.tvvolume`, `com.softwinner.miracastReceiver` | volume e espelhamento |

## Particularidades deste firmware

- **O protetor de tela recarrega a tela inicial antiga.** Depois de trocar para o Projectivy, o protetor de tela da HTC continuava ligado e, ao entrar, carregava a tela inicial original inteira (132 a 160 MB). O `otimizar-hy320.ps1` com `-InstalarProjectivy` desliga o protetor de tela quando ele pertence à tela inicial de fábrica, e o `restaurar-hy320.ps1` religa.
- **Pouco armazenamento.** Com 1,3 GB livres, compilar todos os apps em `speed` pode encher o `/data`. O script passa a usar `speed-profile` abaixo de 1,5 GB livres e para de compilar abaixo de 500 MB.
- **Vídeo.** O decodificador de hardware toca VP9 em 1920x1080 a 60 fps (testado no YouTube para TV e no SmartTube) e recebe até 3840x2160. O decodificador AV1 (`allwinner.decoder.av1`) registra vários `UnsupportedIndex` no log.
- **YouTube ReVanced/ReX limitado a 240p.** As versões modificadas do YouTube de celular (`app.rvx.android.youtube`, `app.rex.android.youtube`) só ofereciam 240p, usavam o decodificador AV1 e abriam sozinhas no boot (cerca de 94 MB). Não é limite do aparelho: o YouTube para TV e o SmartTube tocam 1080p60 na mesma rede.
- **Rede.** Wi-Fi 6 em 5 GHz, link de 216 a 540 Mbps com sinal de -42 dBm.

## Medições

| Item | Valor |
|---|---|
| Tela inicial original (HTC) | 132 MB em uso; 160 MB depois de acordar do protetor de tela |
| Projectivy logo após o boot | 306 MB durante a tela de boas-vindas (carregando ícones); medir de novo depois de concluí-la |
| Loja + atualizador + OfficeSuite | 61 MB, que deixam de rodar |
| Memória disponível (`MemAvailable`) | 410 MB antes; 363 MB depois de reiniciar, ainda na tela de boas-vindas do Projectivy |
| Entradas compiladas antes | 6 em `speed`, 12 em `speed-profile`, 83 em `verify` |

A comparação de memória antes e depois não é conclusiva, pelo mesmo motivo do caso HY320 Mini: os apps abertos eram diferentes em cada medição.
