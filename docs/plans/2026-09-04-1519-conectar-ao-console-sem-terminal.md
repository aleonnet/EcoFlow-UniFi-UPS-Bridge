# 0.6.0 — conectar ao console sem terminal, e provar o alcance de verdade

status: superado por 2026-09-05-0930-acesso-ao-console-pela-tela.md
data: 2026-09-04
frente: ordem do dono — *"Não vou instalar chave no UDR7, o App tem que ser User friendly
e não para nerds"* — e a cobrança anterior sobre o número de série digitado à mão
plano anterior (executado): `2026-09-04-1140-handoff-0-5-0-o-servico-manda-no-river.md`

## 1. O problema, em uma frase

Para a proteção funcionar, o serviço precisa entrar no console por SSH com chave. Hoje isso
exige que uma pessoa abra um terminal, gere a chave e rode `ssh-copy-id`. O dono recusou, com
razão: **isso não é um app, é uma tarefa de administrador**.

E há um defeito de fundo do mesmo tamanho: hoje o serviço **arma sem nunca ter falado com o
console**. O estado `armado_nao_verificado` existe justamente para denunciar isso. A primeira
vez que o daemon falaria com o UDR7 seria o desligamento real, numa queda de energia.

## 2. Faixa de risco

**Crítico.** Mexe no caminho que desliga um roteador de produção e passa a lidar, num dos
ramos, com a senha do console. Regras desta frente, sem exceção:

- A chave **privada nunca sai** do diretório de estado: nenhuma rota a devolve, nenhum log a
  cita. Cerca própria, refutada.
- A senha do console, quando usada, é **de passagem**: nunca gravada, nunca registrada, nunca
  devolvida. Cerca própria, refutada.
- A identidade do console é confirmada por **impressão digital na tela** antes de qualquer
  comando; identidade divergente é recusa, não aviso.
- Nada nesta frente arma a proteção nem abre a trava de armamento.

## 3. Varredura de impacto (medida em 2026-09-04, comandos no ato)

| Fato | Onde / comando |
|---|---|
| Porta 22 do UDR7 **aberta** a partir do mini | `nc -z -G 3 192.168.1.1 22` → `succeeded` |
| **Nenhuma chave** do serviço existe no mini | `ls ~/.ssh/river-bridge*` → sem correspondência |
| O UDR7 está sem endereço e sem chave na instância | `devices.json` → `{'ssh_host': '', 'ssh_key': '', 'ssh_port': 22, 'ssh_user': 'root'}` |
| O River publica o próprio número de série | `upsc river-office@127.0.0.1` → `device.serial: R631ZBBAWH270046` |
| A tabela de comandos do UDR7 é fechada, com 5 entradas | `plugins/udr7_ssh.py:45-71` |
| O único comando destrutivo é `ubnt-systool poweroff`, e é **[S]** (três fontes secundárias) | mesmo arquivo, `:59-65` |
| O `ssh` roda sem senha por desenho | `protect.py:245-262`: `BatchMode=yes`, `PasswordAuthentication=no`, `IdentitiesOnly=yes`, `StrictHostKeyChecking=yes`, `--` antes do destino |
| A folha do dispositivo é uma só, com variantes | `SshDeviceSheet.swift` (345 linhas); `Udr7SettingsSheet.swift` é um invólucro de 20 |
| As rotas de dispositivo hoje são 5 | `api.py:204-208` |
| `PROBE` existe como dado e **não tem chamador em produção** | `plugins/udr7_ssh.py:79`; confirmado por `grep` no repositório inteiro |
| O selo `usb` do health é **constante** | `state.py:126`: `usb = "nao_observavel"`, nunca muda |

### O caminho do fabricante, pesquisado (fonte secundária declarada)

A busca na base de ajuda da Ubiquiti devolve dois caminhos distintos, e **não consegui abrir as
páginas para citar literalmente** (o site responde 403 a leitura automatizada). Fica declarado
como **[S] secundária**:

- **Ligar o SSH do console:** *Settings → Control Plane → Console → SSH* (bate com o diálogo
  "Enable SSH" que o dono viu, e com o item "Control Plane" que aparece na barra dele).
- **Colar uma chave pública:** a busca indicava *Settings → System → Advanced → Device
  Authentication → SSH Keys*. **MEDIDO NA MÁQUINA DO DONO EM 2026-09-04 (captura): essa tela
  NÃO EXISTE na versão dele.** O "System" do Network 10.6.101 tem apenas Country/Region,
  Language, Time Format, NTP, Side Panel Tabs e Professional Installer — sem "Advanced" e sem
  "Device Authentication". A trilha da busca é de outra versão ou de outro produto.

**Consequência para o desenho:** o ramo de copiar-e-colar **não está disponível** nesta versão.
O único lugar de SSH que a interface dele oferece é o do Control Plane (ligar, com senha) — o
mesmo diálogo "Enable SSH" que ele viu. Portanto **o ramo em que o App instala a chave usando a
senha do console, uma vez, passa a ser o caminho PRINCIPAL**, e não o recurso. O ramo de
copiar-e-colar fica no App como alternativa para quem tiver a tela (versões futuras ou outro
console), nunca como pré-requisito.

## 4. Decisões (minhas; medidas ou pesquisadas)

| # | Decisão | Motivo |
|---|---|---|
| D1 | **O serviço passa a criar a chave dedicada sozinho** (`ssh-keygen -t ed25519 -N ""`), em `<estado>/<id>_key`, 0600, e a devolve **só a pública**. | Tirar do dono a tarefa que é da máquina. Sem frase secreta porque o serviço age sozinho de madrugada. |
| D2 | **Caminho principal: o App instala a chave.** Uma folha pede a senha do console, o serviço a usa **uma vez** para acrescentar a chave em `authorized_keys` e a descarta. Nunca gravada, nunca registrada, nunca devolvida. | Medido na máquina do dono: a interface dele **não tem** tela de colar chave. Sem isto, não existe fluxo sem terminal. |
| D3 | **Alternativa: copiar e colar.** A tela oferece a chave pública com botão Copiar, para quem tiver a tela de chaves no console. Nunca é pré-requisito. | Não custa nada e cobre versões que tenham o campo. |
| D4 | **A identidade do console é registrada e confirmada.** O serviço lê a chave de host (`ssh-keyscan`), grava em `<id>_known_hosts` e mostra a **impressão digital** na tela. Se já houver uma diferente, é **recusa** (`identidade_divergente`), nunca substituição silenciosa. | Trocar chave de host sem avisar é o passo que um ataque de intermediário precisa. |
| D5 | **"Testar conexão" roda os três comandos de leitura** (`command -v ubnt-systool`, `ubnt-device-info model`, `ubnt-device-info firmware`) e devolve o que respondeu, em português. | Fecha o defeito de armar sem nunca ter falado com o console. |
| D6 | **Armar passa a exigir alcance verificado.** O resultado do teste (com data) mora em `<id>_runtime.json`; sem ele, o PUT que arma recusa com `alcance_nao_verificado`. O estado `armado_nao_verificado` deixa de ser possível. | O portão que faltava: o único que provava que o comando destrutivo tem para onde ir. |
| D7 | **O número de série do River ganha "usar o que está conectado agora"**: um toque grava o que o aparelho publicou. A cerca continua — o ato é do dono, deliberado e registrado. | Digitar 16 caracteres à mão é a parte estúpida da cerca, não a cerca. |
| D8 | **O selo `usb` do health passa a medir algo**: "lendo pelo cabo" quando a leitura corrente vem do driver real do no-break; "sem dados" antes da primeira; "falha" quando o NUT falhou. | Um selo constante é ruído; ele tem resposta disponível hoje. |
| D9 | **As dicas de Ajustes viram ⓘ tocável** (botão com explicação em balão), em vez de só passar o ponteiro. | O `.help` do macOS não existe no toque; o App vai ganhar versão móvel. |
| D10 | **Aviso de garantia ao salvar aparelho por SSH**, uma frase, sem letra miúda. | O próprio fabricante avisa que habilitar SSH pode anular a garantia; pedimos exatamente isso ao usuário. |
| D11 | Versão **0.6.0** (rotas novas, portão novo no armamento). | SemVer pré-1.0 já adotado. |

## 5. Mudanças por arquivo

### 5.1 Daemon

- `src/river_unifi_bridge/ssh_acesso.py` (**novo**, só biblioteca padrão):
  - `garantir_chave(caminho)` → cria o par se faltar (`ssh-keygen`), devolve **a pública e a
    impressão digital**; nunca a privada.
  - `identidade_do_host(host, porta)` → `ssh-keyscan`, devolve as linhas e a impressão digital.
  - `gravar_identidade(caminho, linhas)` → recusa quando já existe identidade **diferente**.
  - `instalar_chave_com_senha(host, porta, usuario, senha, publica)` → um `ssh` sob pseudo
    terminal (`pty`, biblioteca padrão) que digita a senha uma vez e acrescenta a chave em
    `authorized_keys`. A senha só existe como variável local; nenhum log a toca.
  - `testar_alcance(pc, known_hosts, comandos)` → roda os comandos de leitura com o **mesmo**
    `ssh_argv` da proteção, devolve saída e código.
- `src/river_unifi_bridge/protect.py`: `ProtectionPolicy` ganha `alcance_verificado_em`
  (persistido em `<id>_runtime.json`); o portão novo entra na ordem dos portões, antes do
  armamento; `status()` deixa de emitir `armado_nao_verificado`.
- `src/river_unifi_bridge/plugins/ssh_motor.py`: `authorize_update` recusa armar sem alcance
  verificado (`alcance_nao_verificado`).
- `src/river_unifi_bridge/api.py`: quatro rotas novas, todas por instância:
  `POST /v1/devices/{id}/chave`, `POST /v1/devices/{id}/identidade`,
  `POST /v1/devices/{id}/testar`, `POST /v1/devices/{id}/instalar-chave`.
  Todas fora do laço de eventos (`asyncio.to_thread`), como as do River na 0.5.0.
- `src/river_unifi_bridge/state.py`: `usb` calculado (D8).

### 5.2 App

- `SshDeviceSheet.swift`: grupo novo **"Acesso ao console"** — impressão digital com confirmação,
  "Copiar chave pública" + a trilha da interface do fabricante, "Testar conexão" com resultado em
  português, e "Instalar pela senha do console…" (ramo B) numa folha própria. A linha de
  armamento fica desabilitada enquanto o teste não passar, com a razão escrita.
- `SettingsView.swift`: botão "usar o River conectado agora" (D7); dicas em ⓘ (D9).
- `ProtectionRefusal.swift`: `alcance_nao_verificado`, `identidade_divergente`,
  `senha_recusada`, `chave_nao_instalada`.
- `APIClient.swift` + `Models.swift`: as quatro chamadas novas e seus retornos.

### 5.3 Instalador e documentação

- `scripts/uninstall.sh`: `<id>_key` e `<id>_key.pub` na lista do que sai.
- `docs/reference/api-local.md`: as quatro rotas e as recusas novas.
- Runbook do UDR7: reescrito para o fluxo do App (o do terminal vira apêndice histórico).

## 6. Cercas novas (cada uma com o defeito plantado reprovando)

| Cena | O que o mutante quebra |
|---|---|
| S4ay | A chave **privada** aparecendo em qualquer resposta ou log → o teste varre as respostas das quatro rotas e o log inteiro |
| S4az | A **senha** do console gravada, registrada ou devolvida → idem |
| S4ba | Identidade de host divergente sendo **substituída** em vez de recusada |
| S4bb | Armar **sem** alcance verificado → tem de recusar |
| S4bc | "Testar conexão" usando um `ssh` diferente do da proteção (sem `BatchMode`, sem `--`) |
| S4bd | O selo `usb` voltando a ser constante |
| Swift | A linha de armamento habilitada sem teste passado |

## 7. Aceitação (EARS)

| # | WHEN | THE SYSTEM SHALL | falha quando |
|---|---|---|---|
| 1 | o dono toca "Preparar acesso" numa instância sem chave | criar o par, 0600, e devolver **só** a pública e a impressão digital | a privada aparece em resposta ou log |
| 2 | a mesma ação numa instância que já tem chave | devolver a mesma pública, sem recriar | a chave muda (quebraria o acesso já instalado) |
| 3 | o console apresenta identidade diferente da registrada | recusar com `identidade_divergente`, sem tocar no arquivo | substitui em silêncio |
| 4 | "Testar conexão" com a chave instalada | responder com modelo e firmware lidos do console, e marcar o alcance como verificado | diz "ok" sem saída do aparelho |
| 5 | "Testar conexão" sem a chave instalada | recusar com frase humana dizendo que a chave ainda não foi aceita | erro cru do `ssh` na tela |
| 6 | PUT que arma, sem alcance verificado | 409 `alcance_nao_verificado` | arma |
| 7 | ramo B, senha correta | instalar a chave, apagar a senha da memória, e o teste passar em seguida | senha em log, em disco ou na resposta |
| 8 | ramo B, senha errada | recusar com `senha_recusada`, sem deixar rastro | mensagem crua do `ssh` |
| 9 | "usar o River conectado agora" | gravar o número de série que o aparelho publicou e liberar a cerca de fonte | grava valor vazio ou de outro aparelho |
| 10 | health, com leitura corrente do driver real | `usb` dizer que está lendo pelo cabo | continua constante |

## 8. Ordem de commits

| # | Commit | Prova |
|---|---|---|
| C1 | `ssh_acesso.py` + testes (chave, identidade, teste de alcance) — sem fio ainda | S4ay, S4ba |
| C2 | rotas novas + recusas + contrato | S4az, S4bc |
| C3 | portão do alcance no armamento (`protect.py`, `ssh_motor.py`) | S4bb |
| C4 | selo `usb` de verdade (D8) | S4bd |
| C5 | App: grupo "Acesso ao console", ramo A e ramo B, armamento condicionado | captura + Swift |
| C6 | App: botão do número de série, dicas em ⓘ, aviso de garantia | captura |
| C7 | documentação, runbook novo, versão 0.6.0, CHANGELOG, release | `release.sh --check` |
| C8 | **bancada com o dono**: colar a chave pela interface, testar conexão, ver o modelo e o firmware reais | medições coladas na decisão |

Revisão fria sobre o diff depois de C3 e depois de C6 (teto de 2 rodadas cada).

## 9. Fora de escopo (declarado)

- Executar o desligamento real do UDR7 (continua sendo ato com o dono presente).
- A "superbridge" que alimenta o NUT com os nossos números (frente própria, já pesquisada: o
  driver `dummy-ups` serve variáveis de um arquivo e os nomes padrão `ups.realpower` e
  `outlet.n.realpower` existem).
- Abrir a API do serviço para a rede (frente própria, decidida pelo dono como "B completo").
