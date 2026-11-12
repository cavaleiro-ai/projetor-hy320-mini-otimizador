# Caso de referência: HY320 Mini

Dados reais de um HY320 Mini otimizado com este fluxo em novembro de 2026. Use como exemplo do que esperar e de como classificar pacotes; outros lotes do "HY320" usam placas e firmwares diferentes, então confirme cada item no aparelho em mãos.

## Identificação

| Propriedade | Valor |
|---|---|
| `ro.product.model` | `HY320mini` |
| `ro.hardware` | `sun50iw12p1` (Allwinner H713) |
| `ro.board.platform` | `ares` |
| `ro.build.display.id` | `HY320mini_Android11_202506182038` |
| `ro.build.fingerprint` | `ADT-3/adt3/adt3:11/...` (identidade emprestada de outro aparelho) |
| `ro.company.name` / `ro.company.pcbname` | `ChipTrip` / `Fungo` |
| Wi-Fi / Bluetooth | Seekwave |
| CPU | 4 núcleos, 672 a 1320 MHz, espaço de usuário 32 bits |
| RAM | 954 MB, zram de 858 MB, `ro.config.low_ram=true` |
| Armazenamento | 12 GB em `/data` |
| Tela | 1280x720 |
| Controle remoto | infravermelho (nenhum dispositivo Bluetooth pareado) |
| Tela inicial de fábrica | `com.chiptrip.install.launcher/com.dymt.tvlauncher.activity.HomeActivity` |

Outras variantes vendidas como HY320 (placa HTC/Magcubic, Wi-Fi AIC8800, ou a versão certificada com Android 13) têm pacotes diferentes. Os scripts deste repositório abortam se `ro.hardware` não for `sun50iw12p1` ou o modelo não começar com `HY320`.

## Pacotes

### Desativados sem perguntar (testes de fábrica)

| Pacote | O que é |
|---|---|
| `com.softwinner.dragonbox` | teste de fábrica da Allwinner, acionado por pendrive |
| `com.softwinner.agingdragonbox` | teste de burn-in |
| `com.softwinner.dragonatt` | teste de reinício em laço |

A pilha de impressão (`com.android.printspooler`, `com.android.bips`, `com.android.printservice.recommendation`) também foi desativada: o spooler subia em todo boot e não tem uso em um projetor.

### Desativados com autorização do usuário

| Pacote | O que é | Memória | Contrapartida |
|---|---|---|---|
| `com.android.fungo` | loja de apps do fabricante; inicia no boot; pode instalar apps sem perguntar e pede microfone e câmera | 16 MB | perde a loja (a Play Store continua) |
| `com.uv.droid.uota` | atualizador com permissão de instalar apps silenciosamente | 14 MB | apps pré-instalados que dependem dele deixam de se atualizar |
| `com.uv.droid.uotaback` | par do anterior | 13 MB | idem |
| `com.adups.fota` | atualização de firmware; só acorda no boot | 0 em repouso | sem atualizações de firmware |

### Mantidos (não desativar)

| Pacote | Por que fica |
|---|---|
| `com.cptp.console` (`:sensor`) | sensor e correção de keystone |
| `com.softwinner.awtvinputservice` / `com.softwinner.vis` | entrada HDMI |
| `com.chiptrip.assist` | serviço de acessibilidade que filtra teclas do controle |
| `com.softwinner.tv.factorymenu` | menu de fábrica, recebe o aviso de boot |
| `com.chiptrip.install.launcher` | tela inicial original, fica como reserva |
| `com.cptp.zoomview`, `com.softwinner.tvvolume`, `com.softwinner.awsource` | zoom, volume e seleção de fonte |
| `com.google.android.gms`, `com.android.inputmethod.latin` | serviços Google e teclado |

Apps de streaming e IPTV pré-instalados não estavam rodando em segundo plano e foram deixados como estavam: usar ou remover é decisão do usuário.

## Apps de streaming na Play Store do aparelho

A Play Store instalada é a variante de Android TV (versão 35.2.19, marcador `[8]`); o aparelho declara `android.software.leanback`, mas não é certificado.

| App | Pacote | Resultado |
|---|---|---|
| YouTube | `com.google.android.youtube.tv` | instalado pela Play Store |
| HBO Max | `com.wbd.stream` | instalado pela Play Store |
| Prime Video (TV) | `com.amazon.amazonvideo.livingroom` | instalou na segunda tentativa; a primeira falhou com uma parte do download travada |
| Paramount+ (internacional) | `com.cbs.ca` | instalou; abre com preços em reais |
| Paramount+ (pacote de outra região) | `com.cbs.ott` | "Este item não está disponível em seu país" |
| Netflix (TV e celular) | `com.netflix.ninja`, `com.netflix.mediaclient` | "Seu dispositivo não é compatível com esta versão" |
| Disney+ | `com.disney.disneyplus` | "Seu dispositivo não é compatível com esta versão" |
| Prime Video e Paramount+ (celular) | `com.amazon.avod.thirdpartyclient`, `com.cbs.app` | "Seu dispositivo não é compatível com esta versão" |

O aparelho tem os plugins de DRM Widevine e PlayReady (`/vendor/lib/mediadrm/libwvdrmengine.so`, serviço carregado sob demanda); o nível do Widevine (L1 ou L3) não foi medido. A recusa da Netflix vem da falta de certificação Play Protect, não da ausência de DRM; a ajuda oficial da Netflix não oferece APK para aparelhos não certificados. O Disney+ 26.20.0 tem `minSdkVersion=32` (Android 12L) e o aparelho é API 30: `INSTALL_FAILED_OLDER_SDK`.

Netflix pela loja do fabricante (2026-11-11): a loja `com.android.fungo` (atividade `com.chihihx.store.ui.activity.MainActivity`) pede aceite de política de privacidade e lista "7.120_NetFlix" (62,8 MB) na tela inicial. Instalou `com.netflix.mediaclient` 7.120.6 build 63 (versionCode 35594, `minSdkVersion=21`, APK universal com bibliotecas `armeabi-v7a`) em cerca de 18 s, sem instalar mais nada. Assinatura válida, certificado `CN=PPD Builder, O="Netflix, Inc."`, SHA-256 `363863596ea99241eb71b1a985553aa604de3ea3c5f0c546742390e682164e6b`, o mesmo de um signatário da versão 9.91.0. Abre em `SignupNativeTabletActivity` sem erro; login e reprodução não testados. O app usa janela protegida (captura de tela sai vazia) e não registra receptor de boot. A busca por "disney" na loja não retorna nada. O teclado da busca é próprio da loja e não aceita `input text`; é preciso navegar tecla por tecla.

Teste com APKs avulsos trazidos pelo usuário (2026-11-11): `Netflix.apk` (`com.netflix.mediaclient` 9.91.0, `minSdkVersion=28`, assinado em nome da Netflix, com selo de origem da Play Store) era só a parte base (`requiredSplitTypes="base__abi,base__density"`, nenhuma biblioteca nativa). Instalou no Android 11, mas fechou ao abrir com `Unable to instantiate application ... NullPointerException`; foi desinstalado. `Disney+.apk` foi recusado pelo SDK mínimo.

Prime Video e Paramount+ abriram até a tela de login com o DNS privado ativo; a reprodução com conta logada não foi testada. Compilação em `speed`: 33 s e 130 s. Os dois registram receptor de boot, mas não ficam em segundo plano.

## Medições

| Item | Antes | Depois | Condição |
|---|---|---|---|
| Entradas compiladas em `speed` | 6 | 89 | `dumpsys package dexopt`; passou a 93 depois de instalar os apps de streaming e rodar o script de novo |
| Abertura a frio de 5 apps (`am start -W`, `TotalTime`, mediana de 5) | 431 a 789 ms em `verify` | 409 a 773 ms em `speed` | 2% a 8% menos; medido com `ferramentas/medir-abertura.sh`, dados em `docs/medicao-abertura.txt` |
| Entradas em `verify` (interpretado) | 89 | 6 | as 6 restantes são Play Store, Chrome e pacotes desativados |
| Compilação | | 106 de 106 com `Success` | levou pouco mais de 10 minutos |
| Processos do fabricante sempre ativos | 44 MB | 0 | loja + dois atualizadores |
| Bluetooth | 25 MB | 0 | desligado no boot |
| Processos de app após o boot | | 13 | 32 são iniciados; o resto é encerrado em segundos |
| Tela inicial | 42 MB (original) | 87 MB (Projectivy) | o Projectivy usa mais memória |
| Animações | 1.0x | 0.5x | |
| Log verboso de Wi-Fi | ligado | desligado | gravava a cada 3 s |

O dono do aparelho relatou uma melhora de velocidade percebida de 235% no uso. Trate esse número como relato, não como medição: o cronômetro da abertura de apps mostra um ganho bem menor, porque não captura transições (metade do tempo), memória livre nem a ausência dos serviços do fabricante. Ao falar de resultados com outra pessoa, separe sempre o que foi medido do que foi percebido.

Os totais de memória do sistema não são comparáveis entre "antes" e "depois" porque os apps abertos eram diferentes em cada medição; por isso a tabela usa valores por processo.

## Investigação de lentidão proposital

- CPU alcança a frequência máxima (1320 MHz); `time_in_state` mostra uso normal das faixas.
- Limitador térmico em 0 de 5; temperatura de 60 a 67 °C com ponto de corte em 80 °C.
- Nenhuma propriedade de sistema com contador de uso ou prazo.
- `pm.dexopt.downgrade_after_inactive_days=10` é padrão do Android e só age com armazenamento cheio.
- Rede: 66 Mbps reais em transferência, apesar do "link speed" de 5 Mbps mostrado em repouso.

Conclusão: sem evidência de degradação proposital. O código dos apps do fabricante não foi analisado.

## O que não foi resolvido

- Thread do kernel `sugov` (regulador `schedutil`) consumindo de 20% a 24% de um núcleo, inclusive durante reprodução de vídeo. A CPU troca de frequência cerca de 50 vezes por segundo (`stats/total_trans`), com `rate_limit_us=10000`. O arquivo `scaling_governor` pertence a `system` e `rate_limit_us` a `root`: sem root não há como ajustar.
- O firmware traz um serviço com privilégio de root ativo desde o boot e SELinux em modo permissivo. Não foi usado nem alterado; não há como removê-lo sem modificar a partição de sistema. O aparelho não deve ser usado com contas importantes.

## Particularidades deste firmware

- DNS privado (`dns.adguard-dns.com`) valida nesta rede e ficou estável em 3 minutos de consultas. De 32 endereços de anúncio e rastreamento testados, 23 foram bloqueados (9/9 redes de anúncio de apps, 6/7 anúncios Google, 5/8 anúncios em sites, 3/8 rastreadores); passaram, por exemplo, `googlesyndication.com` (sem subdomínio), `appsflyer.com`, `app.adjust.com` e `graph.facebook.com`. YouTube, Max e Netflix seguem liberados. Valores originais de `private_dns_mode`, `private_dns_specifier` e `ntp_server`: ausentes (`null`).
- Durante reprodução no YouTube: app 40% de CPU, `surfaceflinger` 33%, `sugov` 24%, decodificador 13%. Sem pressão de memória e sem varreduras de Wi-Fi em segundo plano.
- `svc bluetooth disable` falha e o shell não tem `BLUETOOTH_ADMIN`; use `settings put global bluetooth_on 0` e reinicie.
- `adb_enabled=1` persiste: a depuração volta sozinha após reiniciar, na porta 5555.
- A captura de tela (`screencap`) funciona normalmente.
