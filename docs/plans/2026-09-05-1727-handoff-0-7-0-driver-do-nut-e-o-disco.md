# Handoff — 0.7.0 publicada: a ponte virou driver do NUT, e o disco existe

status: superado por 2026-09-05-2330-handoff-0-8-2-o-leitor-recusado-pelo-nut.md
data: 2026-09-05
supera: 2026-09-04-1140-handoff-0-5-0-o-servico-manda-no-river.md

**Primeiro arquivo a abrir ao retomar.** Tudo abaixo foi medido no ato, com o
comando ao lado.

## 1. Estado, medido agora

| O quê | Medida |
|---|---|
| Ramo | `main`, árvore limpa, **0 commits não enviados** (`git status -sb`) |
| Topo | `d863d72` |
| Release | **v0.7.0**, publicada 2026-09-05T20:19Z, com `River-Bridge.dmg` (48.426.732 B), `River-Bridge.app.zip`, o código-fonte e o `SHA256SUMS` (`gh release view`) |
| Versão | consistente nos 6 arquivos e no CHANGELOG (`tools/release.sh --check`) |
| Suíte Python | **496 passaram** (`pytest tests`) |
| Suíte Swift | **78 passaram** (`swift test`) |
| Portão | **128 cenas verdes**; 1 vermelha: **S15** (o desenho da abertura depende da tela de quem roda — declarada como B17 no backlog) |
| Mac mini (192.168.1.13, alcançável por SSH sem senha) | App **ausente**, serviço **não registrado**, estado do sistema **ausente**, **`nut` NÃO instalado** |

## 2. O que a 0.7.0 entrega

**A ponte virou um driver do NUT.** Ela publica um aparelho `river-bridge` com
tudo o que sabe do River — bateria, autonomia, situação, potência total, **watts
por tomada**, frequência, temperatura — e um aparelho por dispositivo protegido,
com as ordens de desligar e reiniciar. É o que faz o Home Assistant receber o
mesmo que o aplicativo mostra.

**Duas correções de rumo minhas**, registradas para não voltarem:

1. O driver de mentira do NUT (`dummy-ups`) **não carrega comando** — a
   documentação é literal ("Instant commands are not yet supported in Dummy
   Mode"). Eu o havia proposto como se resolvesse tudo.
2. O Home Assistant **não cria botão de painel** para comando qualquer: botão só
   para tomada comandável; o resto vira **ação de dispositivo**. E a lista de
   nomes que ele entende é **fechada** — nome nosso seria invisível lá.

**O disco de instalação existe**, com LEIA-ME dentro, e o App tem a tela Serviço
que registra o daemon e o remove por completo.

## 3. Onde o estado real mora

| Assunto | Arquivo |
|---|---|
| O plano desta frente, com as decisões e as duas rodadas de banca | `docs/plans/2026-09-05-1139-o-river-bridge-vira-driver-do-nut.md` |
| Como pôr o Home Assistant no ar, e o roteiro de bancada | `docs/guides/2026-09-05-1327-runbook-o-home-assistant-com-tudo.md` |
| O disco arrastável (plano) | `docs/plans/2026-09-05-1730-instalar-arrastando-o-app.md` |
| O que mudou, versão a versão | `CHANGELOG.md`, seção `[0.7.0]` |
| As cercas | `tools/gate.sh` — S31–S56 são desta frente |

## 4. As três travas de arquivo (nenhuma se abre pela tela)

| Chave | O que ela solta | Padrão |
|---|---|---|
| `UDR7_ARM_ALLOWED` | armar a proteção | fechada |
| `RIVER_POWEROFF_ALLOWED` | desligar o próprio River | fechada |
| `DEVICE_CMD_ALLOWED` | mandar num dispositivo à mão (tela ou Home Assistant) | fechada |

Fechadas, a ordem **nem é anunciada** ao Home Assistant.

## 5. O que NÃO foi verificado

- **Nada foi provado contra o `upsd` de verdade nem contra o Home Assistant.** O
  protocolo está provado por 22 testes contra um servidor de mentira que fala o
  protocolo verdadeiro.
- **Nenhuma tela foi lida em imagem.** A ferramenta de captura recusa fotografar
  janela sem foco, e nas sessões de 2026-09-05 o foco voltava para o editor. As
  telas compilam e passam nos testes; a aparência não foi conferida — inclusive
  as quinze mudanças de 1 pt da entrada na grade de espaçamento.
- **A assinatura é ad-hoc.** O macOS pede "Abrir Assim Mesmo" na primeira
  abertura. O conserto de raiz é um certificado **Developer ID Application** (o
  dono tem conta paga; falta só criar o certificado) e credencial do
  `notarytool` — nenhum dos dois existe nesta máquina, medido.

## 6. O próximo passo concreto

Instalar a 0.7.0 no Mac mini pelo disco e percorrer o roteiro de bancada do
runbook (§6). **O `brew install nut` vem primeiro** — a máquina está sem ele.

```bash
brew install nut
curl -fL -o ~/Downloads/River-Bridge.dmg \
  https://github.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/releases/latest/download/River-Bridge.dmg
open ~/Downloads/River-Bridge.dmg
```

Depois: arrastar → abrir → **Ajustes › Serviço › Instalar o serviço** → aprovar
em Ajustes do Sistema › Geral › Itens de Início de Sessão.

## 7. O que ficou em aberto

| # | O quê |
|---|---|
| A | Assinar com Developer ID e notarizar — tira o diálogo do Gatekeeper. Depende de o dono criar o certificado. |
| B | Ler as telas em imagem (a captura precisa de foco; não deu nesta sessão). |
| C | O empréstimo automático do cabo nasce **desligado**: a detecção foi corrigida mas nunca foi provada com o aplicativo do fabricante aberto e fechado. |
| D | Provar contra o `upsd` de verdade: `upsc river-bridge@127.0.0.1` e `upscmd -l`. |
| E | S15/B17 — a cena do logo depende da tela de quem roda o portão. |
