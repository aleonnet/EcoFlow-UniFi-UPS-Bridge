# Runbook — conectar o console pelo App, e pôr o Home Assistant para ler

status: aceito
data: 2026-09-05
supera: 2026-09-03-1710-runbook-protecao-udr7-por-instancia.md

## 1. Conectar o console pelo App (0.6.0)

O que mudou: **você não cria chave, não abre terminal e não digita comando.** O serviço cria a
chave dele, confere a identidade do aparelho e instala a chave usando a senha do console uma
única vez.

Antes de começar, no console UniFi: *Settings → UDR7 → Control Plane → Console → **SSH*** ligado,
com uma senha definida (é só sua; o App a usa uma vez e não a guarda).

| # | O que fazer no App | O que tem de aparecer |
|---|---|---|
| 1 | Ajustes → Dispositivos protegidos → **UDR7** | a folha do dispositivo abre |
| 2 | Em "Console e chave", preencher **Console (host)** = `192.168.1.1` e **Usuário SSH** = `root`; Salvar | sem erro; a folha continua aberta |
| 3 | Em "Acesso ao console", digitar a **senha do console** e tocar **Conectar…** | duas impressões digitais na tela (a do console e a da chave do serviço) e, em seguida, **"Conexão provada: UniFi Dream Router 7 · 5.1.31"** em verde |
| 4 | Tocar **Testar conexão** de novo, a qualquer momento | a mesma linha verde, com o que o console respondeu agora |
| 5 | Olhar o grupo **Armamento** | o botão de sair do modo ensaio deixa de estar bloqueado por falta de conexão |

**Se o passo 3 falhar**, a tela diz o motivo em português:

- *"O aparelho recusou a senha"* → a senha do console está diferente da que você digitou.
- *"Este aparelho está se apresentando com uma identidade diferente da registrada"* → o console
  foi trocado ou reinstalado. **Confira a impressão digital** antes de aceitar; se você não
  mexeu no aparelho, pare e investigue.
- *"O console não respondeu"* → endereço errado, SSH desligado, ou a chave ainda não foi aceita.

**O que fica registrado:** a chave em `<estado>/udr7_key` (0600), a identidade em
`<estado>/udr7_known_hosts`, e a prova em `<estado>/udr7_acesso.json` com data, modelo e
firmware. A prova vale **30 dias** — depois disso, armar pede um teste novo.

## 2. Armar a proteção

São três passos, e eles não mudaram desde a 0.3.0 — a trava `UDR7_ARM_ALLOWED` no arquivo do
serviço (`$PREFIX/etc/bridge.env`) com reinício, desligar o modo ensaio na folha do
dispositivo, e fechar a trava com outro reinício. **O que mudou é que agora existe um quarto
requisito, e ele é automático:** sem a conexão provada, o serviço recusa armar com
`alcance_nao_verificado`.

## 3. Pôr o Home Assistant para ler o River

O Home Assistant tem integração **nativa** de NUT: ele lê do servidor que a nossa ponte mantém
no ar. O que ele recebe é o essencial do no-break — carga, autonomia, tensão, situação.

**O que falta hoje, medido em 2026-09-04:** o servidor escuta apenas na própria máquina
(`LISTEN 127.0.0.1 3493` em `upsd.conf`, confirmado com `lsof`), então a máquina virtual do
Home Assistant **não o alcança**. Enquanto a versão seguinte não automatiza isso, o caminho é:

| # | Onde | O que fazer |
|---|---|---|
| 1 | no Mac mini, em `/opt/homebrew/etc/nut/upsd.conf` | trocar `LISTEN 127.0.0.1 3493` por `LISTEN 0.0.0.0 3493` |
| 2 | no Mac mini | reiniciar o serviço da ponte (ele é quem mantém o servidor do no-break no ar) |
| 3 | no Home Assistant | Ajustes → Dispositivos e serviços → **Adicionar integração** → **Network UPS Tools (NUT)** |
| 4 | na tela da integração | endereço: o IP do Mac mini; porta `3493`; usuário `powermanager`; senha `river-local` (a conta de leitura que o instalador cria — ela **não** manda no aparelho) |
| 5 | conferir | aparecem sensores de carga, autonomia, tensão e situação do River |

**O que o Home Assistant NÃO recebe por aqui, e por quê:** os watts por tomada. O perfil de
no-break do River não os publica — nós os lemos pela porta serial do mesmo cabo, e o protocolo
do NUT não os carrega hoje. Existe caminho medido para resolver isso (o driver `dummy-ups`
serve variáveis de um arquivo que nós escreveríamos, com os nomes padrão `ups.realpower` e
`outlet.n.realpower`), e ele é frente própria.

**Conta de leitura, não de comando:** `powermanager` é `upsmon secondary` de propósito — o
Home Assistant acompanha o no-break e **não** consegue mandar o River desligar. A conta que
manda (`riverbridge`) tem senha própria, guardada em arquivo 0600, e não sai da máquina.
