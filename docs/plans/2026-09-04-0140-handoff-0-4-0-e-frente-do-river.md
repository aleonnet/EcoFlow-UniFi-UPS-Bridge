# Handoff — 0.4.0 publicada e a frente do River aberta

status: superado por 2026-09-04-1140-handoff-0-5-0-o-servico-manda-no-river.md
data: 2026-09-04 (madrugada)
supera: `2026-09-03-1413-handoff-0-3-3-folhas-na-janela.md`

## 1. Estado medido

`git log --oneline d0d787e..HEAD` no ato: onze commits. Árvore limpa. Versão declarada
**0.4.0** nos seis arquivos, conferida por `tools/release.sh --check`.

| Portão | Resultado |
|---|---|
| `tools/gate.sh` | 61 cenas verdes; **S15 vermelha** — é o defeito B17 já declarado (o desenho do logo é regerado com a cor da tela e diverge entre execuções). Nada foi regerado para "passar" |
| `.venv/bin/pytest` | 298 |
| `cd macos/RiverBridge && swift test` | 58 |

## 2. O que a 0.4.0 entrega

Os vinte defeitos que a leitura integral do código achou, listados um a um no `CHANGELOG.md`,
seção `[0.4.0]`. Em uma frase: a tela parou de afirmar o que o serviço não disse, o vigia
parou de morrer por defeito de um dispositivo, e os números da configuração passaram a ser os
números de verdade.

Cercas novas no gate, todas refutadas (o mutante reprova): S4y, S4z, S4aa, S4ab, S4ac, S4ad,
S4ae, S4af e S21.

## 3. O River 3 Plus, medido

O aparelho chegou em 2026-09-03 à noite e está ligado ao Mac mini. Tudo o que foi medido está
em `../decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md`. O essencial:

- Pelo cabo (perfil de no-break) vêm carga, autonomia, tensão, situação e capacidade. **Não**
  vem potência: o aparelho não a expõe, e a fonte disso é o próprio driver do NUT no GitHub.
- A **porta serial do mesmo cabo** (`/dev/cu.usbmodem102`) entrega potência total, entrada e
  carga por tomada — e funciona **ao mesmo tempo** que o NUT lê o perfil de no-break.
- O aplicativo da EcoFlow mata leitores de no-break pelo nome do processo, com poder de root.
- Ele também sabe ler de um servidor NUT remoto: apontado para o nosso, os dois convivem.

## 4. O que está no Mac mini agora

Instalado à mão nesta madrugada, **fora do instalador** (vira parte dele na frente seguinte):

| Item | Onde |
|---|---|
| Configuração do NUT para o River | `/opt/homebrew/etc/nut/{ups,upsd,nut}.conf`, aparelho `river-office` |
| Conta de leitura para o app da EcoFlow | `/opt/homebrew/etc/nut/upsd.users`, usuário `powermanager` |
| Leitor e servidor sob o launchd do usuário | `~/Library/LaunchAgents/com.river.nut-{driver,upsd}.plist` |
| Interruptor do cabo | `tools/river-cabo.sh` (no repositório; cópia em `/tmp` no mini) |

**Limite conhecido:** agentes de usuário só rodam com alguém logado, e o login automático está
desligado no mini. Enquanto a frente seguinte não move isso para serviço do sistema, um
reinício sem login deixa o River sem leitura.

## 4b. O que mudou depois deste handoff nascer (madrugada de 2026-09-04)

| Fato | Detalhe |
|---|---|
| **0.4.0 e 0.4.1 publicadas** | a 0.4.1 conserta três defeitos que a 2.ª rodada da revisão fria achou; quem instalar deve ir direto nela |
| Leitura de potência pela serial | no serviço, na tela e no contrato; provada no mini com o código novo (68,5 W, por tomada) |
| Instalador cuida do NUT | fase nova: configuração escrita só se faltar, dois serviços do SISTEMA com nome próprio (`river-bridge-ups`/`river-bridge-upsd`), cena S9k no portão |
| Revisão fria | duas rodadas, oito bloqueadores no total, todos corrigidos com cerca; o diário está nos commits |

**O que só o dono pode fazer, e por quê:** instalar no Mac mini pede a senha de administrador,
que eu não digito. O comando é o de sempre:

```
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash
```

**Estado do mini nesta madrugada:** o Mac reiniciou às 01h17 e ninguém logou, então os
programas de leitura (registrados como do usuário) não subiram e o River ficou sem vigia por
uma hora. Religuei-os desprendidos da sessão às 02h20 — funciona agora, **não sobrevive a um
reinício**. É exatamente isso que a fase nova do instalador conserta, ao registrar a leitura
como serviço do sistema.

## 5. Próximo passo

A frente do River, com os doze itens no `../BACKLOG_20260901.md` (B30–B41): o botão de liberar
e retomar o cabo, a leitura de potência pela serial dentro do serviço, o instalador cuidando do
NUT com nome próprio de processo, a paridade com o aplicativo deles, e — só com o dono
acordado e com trava dupla — ligar/desligar tomadas e desligar o próprio River.

## 6. Ler primeiro, ao retomar

1. Este arquivo.
2. `../decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md` — o que o aparelho faz.
3. `../BACKLOG_20260901.md`, seção de 2026-09-04 — o que falta, com origem.
4. `../reference/api-local.md` — o contrato vivo entre serviço e app.

## 7. Prompt para colar na sessão seguinte

```
Retome o River Bridge. Leia docs/plans/2026-09-04-0140-handoff-0-4-0-e-frente-do-river.md,
depois docs/decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md e a seção de
2026-09-04 do docs/BACKLOG_20260901.md. Confirme o estado no ato (git log, gate, pytest,
swift test) e comece a frente do River pelos itens B30, B31 e B32.
```
