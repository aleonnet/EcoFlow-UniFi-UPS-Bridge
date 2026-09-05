# Runbook — conectar o console pelo App, e pôr o Home Assistant para ler

status: superado por 2026-09-05-1327-runbook-o-home-assistant-com-tudo.md
data: 2026-09-05
supera: 2026-09-03-1710-runbook-protecao-udr7-por-instancia.md
nota: a seção 1 (conectar o console pela tela) continua valendo; o que mudou é a
parte do Home Assistant, reescrita no runbook novo depois de a ponte virar driver
do NUT.

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

**Versão do Home Assistant conferida na fonte:** a série corrente é a **2026.9**, publicada em
2026-09-02 ([notas da versão](https://www.home-assistant.io/blog/2026/09/02/release-20269/)).
Os passos abaixo são os da documentação oficial da integração, citados literalmente.

**Estado medido em 2026-09-05, a partir do Mac mini:** o Home Assistant **está no ar**, em
`http://haos.home.arpa/home/overview` (HTTP 200; o nome resolve para `192.168.1.15`; a porta é
a **80**, não a 8123 — a instalação do dono usa nome próprio e porta padrão). A máquina virtual
aparece em `VBoxManage list runningvms` como `HomeAssistant`.

*(Correção registrada: numa primeira medição eu disse que a VM estava parada. Estava errado —
eu havia chamado o `VBoxManage` fora do PATH e sondado a porta 8123.)*

O que continua **não validado por mim ponta a ponta**: a integração lendo do nosso servidor,
porque ela depende da mudança da seção 3.1, que é ato do dono na configuração do NUT.

### 3.1 O que precisa mudar do nosso lado (e por quê, com fonte)

O servidor do no-break escuta hoje só na própria máquina — medido: `LISTEN 127.0.0.1 3493` em
`upsd.conf`, e `lsof` mostrando `upsd … 127.0.0.1:3493 (LISTEN)`. A máquina virtual é outra
máquina na rede, então ela não alcança.

A documentação do NUT sobre essa linha
([`upsd.conf`](https://networkupstools.org/docs/man/upsd.conf.html)):

> *"Bind a listening port to the interface specified by its Internet address or name."*
> *"The default is to bind to `127.0.0.1` if no `LISTEN` addresses are specified…"*
> *"You should not rely exclusively on this for security, as it can be subverted on many systems."*
> *"This parameter will only be read at startup. You'll need to restart (rather than merely reload) `upsd` to apply any changes made here."*

Ou seja: trocar a linha **e reiniciar** — recarregar não basta, e a linha sozinha não é
segurança (a conta de leitura é que limita o que o Home Assistant pode fazer).

| # | Onde | O que fazer |
|---|---|---|
| 1 | `/opt/homebrew/etc/nut/upsd.conf` | `LISTEN 127.0.0.1 3493` → `LISTEN 0.0.0.0 3493` |
| 2 | no Mac mini | reiniciar o serviço da ponte (é ele que mantém o servidor do no-break no ar, e o `upsd` **precisa reiniciar**, não recarregar) |

### 3.2 O que fazer no Home Assistant (documentação oficial, citada)

Da [página da integração](https://www.home-assistant.io/integrations/nut/):

> *"Go to **Settings > Devices & services**"* e o botão *"**Add Integration**"* no canto
> inferior direito; escolher *"**Network UPS Tools (NUT)**"*.

Na instalação do dono, a interface abre em `http://haos.home.arpa/` (medido).

Os campos que ele pede, como a página os descreve:

- **Host** — *"The IP address or hostname of your NUT server"* → o endereço do Mac mini na
  rede (o Home Assistant é outra máquina; `127.0.0.1` ali apontaria para ele mesmo).
- **Port** — *"The network port of your NUT server. The NUT server's default port is '3493'"*.
- **Username** — *"The username to sign in to your NUT server. The username is optional"* →
  `powermanager`.
- **Password** — *"The password to sign in to your NUT server. The password is optional"* →
  `river-local`.

E uma frase que importa para nós:

> *"The username and password configured for the device must be granted `instcmds`
> permissions on the NUT server to use buttons and switches."*

Como a nossa conta de leitura **não** tem `instcmds` (ela é `upsmon secondary`), o Home
Assistant vai **acompanhar** o River e não vai conseguir mandar nada nele. É de propósito.

### 3.3 O que o Home Assistant NÃO recebe por aqui

Os watts por tomada e qualquer ordem. O perfil de no-break do River não publica potência — nós
a lemos pela porta serial do mesmo cabo —, e o leitor de fábrica não oferece comando nenhum
para o servidor repassar.

**Correção registrada em 2026-09-05:** eu havia escrito aqui que o caminho para resolver isso
era o driver de mentira do NUT (`dummy-ups`). Ele resolve metade: serve variáveis de um arquivo,
e **não** carrega comando. A documentação do NUT é literal — *"Instant commands are not yet
supported in Dummy Mode"*. O caminho que resolve inteiro é a ponte virar ela mesma um driver do
NUT, e ele está planejado em
[`plans/2026-09-05-1139-o-river-bridge-vira-driver-do-nut.md`](../plans/2026-09-05-1139-o-river-bridge-vira-driver-do-nut.md)
(versão 0.7.0), que também troca a conta de leitura por uma conta própria do Home Assistant.

**Conta de leitura, não de comando:** `powermanager` é `upsmon secondary` de propósito — o
Home Assistant acompanha o no-break e **não** consegue mandar o River desligar. A conta que
manda (`riverbridge`) tem senha própria, guardada em arquivo 0600, e não sai da máquina.
