# 0.6.0 — o acesso ao console pela tela, e a proteção que só arma com alcance provado

status: proposto
data: 2026-09-05
supera: 2026-09-04-1519-conectar-ao-console-sem-terminal.md
frente: ordem do dono — *"o App tem que ser User friendly e não para nerds"*, *"somente não
vou criar chave ssh"*, e a bancada de 2026-09-04 que provou o caminho

## 1. O que mudou desde o plano anterior (tudo medido, no ato)

| Fato | Como foi medido | Consequência |
|---|---|---|
| A API oficial do console **não desliga** o aparelho | o próprio console: `Invalid $.action value 'XXX' (valid values: 'RESTART')` | o SSH continua sendo o caminho; a chave de API sai do desenho |
| A tela de colar chave **não existe** nesta versão | captura do Network 10.6.101: "System" sem "Advanced"/"Device Authentication" | o App instala a chave usando a senha do console, uma vez |
| O `ssh` divide `UserKnownHostsFile` por espaços | `ssh -o UserKnownHostsFile=<caminho com espaços>` → *"No ED25519 host key is known"*; com aspas no valor → passa | **defeito de produção**: o desligamento nunca teria funcionado em macOS. Corrigido em `protect.ssh_argv` e cercado |
| `ssh-keyscan` não trata `--` como fim de opções | com `--`: 1 linha (só RSA); sem: 3 (rsa, ecdsa, ed25519) | a identidade do console tem de ser lida sem `--`; endereço com `-` é recusado explicitamente |
| O caminho da chave **não cabe** num campo de configuração | `KEY_PATH_PATTERN = /[^\s~]+` recusa espaços, e o estado mora em "Application Support" | a chave do serviço é **caminho derivado** (`<id>_key`), como `known_hosts`; nunca campo digitado |
| O caminho inteiro funciona | bancada no mini: `probe /sbin/ubnt-systool`, `model UniFi Dream Router 7`, `firmware 5.1.31` | o desenho está provado antes de virar tela |
| `PROBE` existe como dado e **nunca é chamado** | `grep` no repositório | é o que esta frente passa a usar |

## 2. Faixa de risco

**Crítico.** Um dos ramos lida com a senha do console, e o resultado libera o armamento da
proteção que desliga um roteador de produção. Regras, sem exceção:

- A chave **privada** nunca sai: nenhuma rota a devolve, nenhum log a cita.
- A senha é **de passagem**: entra pelo terminal do `ssh` (nunca por argumento, que é visível
  em `ps`), não é gravada, não é registrada, não volta na resposta.
- Identidade de console divergente é **recusa**, não substituição.
- Nada aqui abre a trava de armamento: ela continua só no arquivo.

## 3. Decisões

| # | Decisão | Motivo |
|---|---|---|
| D1 | A chave do serviço vive em `<estado>/<id>_key` (0600), **caminho derivado**, ao lado de `<id>_known_hosts`. O campo `ssh_key` continua existindo para quem trouxer a própria chave. | Medido: o padrão do campo recusa espaços, e o estado do macOS tem espaços no caminho. |
| D2 | Quatro rotas novas, todas por instância e todas fora do laço de eventos: **preparar** (cria a chave e lê a identidade), **instalar** (usa a senha uma vez), **testar** (os três comandos de leitura) e **esquecer** (apaga chave e identidade). | O App precisa de cada passo separado para explicar o que está acontecendo. |
| D3 | O resultado do teste mora em `<estado>/<id>_acesso.json` (0600) com data, modelo e firmware. | É o que sustenta o portão novo, e o que a tela mostra. |
| D4 | **Armar passa a exigir alcance provado nos últimos 30 dias.** Sem isso, 409 `alcance_nao_verificado`. O estado `armado_nao_verificado` deixa de existir. | Era o único portão que faltava: o que prova que o comando destrutivo tem para onde ir. |
| D5 | A tela do dispositivo ganha o grupo **"Acesso ao console"**: impressão digital para conferir, botão de preparar/instalar (com campo de senha), botão de testar, e o resultado em português. A linha de armamento fica desabilitada, com a razão escrita, enquanto o teste não passar. | É o pedido do dono, e é o que torna o portão utilizável. |
| D6 | **Aviso de garantia** ao salvar um dispositivo por SSH, uma frase, com a fonte sendo o próprio fabricante. | Nós pedimos ao usuário que habilite SSH; ele tem de saber o que isso custa. |
| D7 | Versão **0.6.0**. | Rotas novas e portão novo no armamento. |

## 4. Mudanças por arquivo

### Daemon
- `ssh_acesso.py` (**já escrito**, 11 testes verdes): `garantir_chave`, `identidade_do_host`,
  `gravar_identidade`, `instalar_chave_com_senha`, `testar_alcance`.
- `protect.py`: aspas no `UserKnownHostsFile` (**feito**, cercado); `status()` sem
  `armado_nao_verificado`.
- `plugins/ssh_motor.py`: `state_paths` ganha `key_path` e `acesso_path`; `build` aponta
  `udr7_ssh_key` para a chave gerida quando ela existe; `authorize_update` recusa armar sem
  alcance provado.
- `api.py`: `POST /v1/devices/{id}/acesso/{preparar|instalar|testar|esquecer}`.
- `state.py`: o selo `usb` passa a medir (lendo pelo cabo / sem dados / falha).

### App
- `SshDeviceSheet.swift`: grupo "Acesso ao console" e armamento condicionado.
- `SettingsView.swift`: botão "usar o River conectado agora" no número de série; dicas em ⓘ.
- `ProtectionRefusal.swift`: `alcance_nao_verificado`, `identidade_divergente`,
  `senha_recusada`, `chave_ausente`.
- `APIClient.swift`, `Models.swift`: as quatro chamadas e o retorno do teste.

### Instalador e documentos
- `uninstall.sh`: `<id>_key`, `<id>_key.pub` e `<id>_acesso.json` na lista.
- `docs/reference/api-local.md`, runbook do UDR7 reescrito para a tela, CHANGELOG, versão.

## 5. Cercas novas (cada uma com o defeito plantado que a reprova)

| Cena | O mutante quebra |
|---|---|
| S4ay | a chave privada aparecendo em qualquer resposta das quatro rotas ou no log |
| S4az | a senha do console sendo gravada, registrada ou devolvida |
| S4ba | identidade divergente sendo substituída em vez de recusada |
| S4bb | armar sem alcance provado |
| S4bc | o teste usando um `ssh` diferente do que desliga |
| S4bd | o `--` voltando ao `ssh-keyscan` (só a chave RSA seria gravada) |
| S4be | o `UserKnownHostsFile` sem aspas (**já no lugar**) |
| Swift | a linha de armamento habilitada sem teste passado |

## 6. Ordem de commits

| # | Commit |
|---|---|
| C1 | `ssh_acesso.py` + testes + a correção das aspas (feito, a commitar) |
| C2 | caminhos derivados, `<id>_acesso.json`, portão do alcance |
| C3 | as quatro rotas + contrato |
| C4 | selo `usb` de verdade |
| C5 | App: grupo "Acesso ao console", armamento condicionado |
| C6 | App: número de série num toque, dicas em ⓘ, aviso de garantia |
| C7 | documentos, versão 0.6.0, release |
| C8 | **bancada do dono**: roteiro em bullets, com resultado esperado |

Revisão fria sobre o diff depois de C3 e depois de C6.

## 7. Fora de escopo

- Executar o desligamento real (ato com o dono presente).
- Abrir a API do serviço para a rede (**frente seguinte, já decidida pelo dono**).
- Alimentar o NUT com os nossos números (`dummy-ups`) — frente própria, pesquisada.
