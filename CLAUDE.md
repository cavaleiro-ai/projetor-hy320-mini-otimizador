# Instruções para o Claude neste repositório

Este repositório deixa o projetor **HY320 Mini** (Allwinner H713, Android 11) mais rápido pela rede Wi‑Fi, com ADB, a partir de um PC com Windows. Responda sempre em português do Brasil, em linguagem simples: quem abre esta pasta costuma ser leigo.

## Por onde começar

- A pessoa pediu para configurar, otimizar ou "fazer tudo" no projetor: use a skill `configurar-projetor` (responde a `/configurar-projetor`). Ela conduz o passo a passo inteiro.
- A pessoa quer analisar, medir ou mexer em algo fora do roteiro, ou o aparelho é outro modelo: use a skill `otimizar-projetor-android` e a referência `.claude/skills/otimizar-projetor-android/references/hy320-mini.md`.
- A pessoa quer desfazer: `.\restaurar-hy320.ps1 -Ip <ip>`.

## Regras que valem sempre

- Use `adb -s <ip>:5555` em todo comando e confirme `ro.hardware` (`sun50iw12p1`) e o modelo (`HY320*`) antes de alterar qualquer coisa. Outros aparelhos Android da rede não são para mexer.
- Faça só mudanças reversíveis: `pm disable-user --user 0` em vez de desinstalar, `settings put` em vez de editar arquivos do sistema. Nunca troque o firmware nem use o serviço de root que vem de fábrica.
- Confira a tela com `screencap` antes de enviar `DPAD_CENTER` ou qualquer tecla que confirme algo.
- Não baixe apps de sites de terceiros e não aceite termos ou políticas de privacidade sem a pessoa autorizar.
- Os scripts `.ps1` são só ASCII de propósito (o PowerShell 5.1 lê arquivos sem BOM como ANSI). Mantenha assim ao editar.
- A pasta `backup/` guarda identificadores do aparelho e nomes de rede. Ela não vai para o Git; não copie o conteúdo dela para arquivos publicados.
- No fim, lembre a pessoa de desligar a Depuração USB.
