# SSH é mesmo o caminho para desligar o UDR7? — pesquisa, 2026-09-01

Pergunta do dono: *"Todos os comandos no UniFi serão via SSH? Pesquise os benchmarks/SOTA
NUT e cases com River 3 Plus e UDR 7 e confirme. Se SSH pode ser contornado ou se é mesmo o
SOTA, também quero a lista de comandos que você usaria."*

**Veredito: SSH é o único caminho documentado para DESLIGAR um console UniFi, e não é
contornável hoje.** Abaixo, cada alternativa que existe e por que cai.

---

## 1. O que o NUT faz nos outros casos (o SOTA do próprio NUT)

O desenho canônico do NUT para desligar uma máquina é **rodar um cliente (`upsmon`) NA
máquina que vai desligar**: o `upsmon` em modo `secondary` conecta no `upsd` do servidor,
recebe o evento de bateria baixa e executa o `SHUTDOWNCMD` localmente. É assim com um NAS,
com um Proxmox, com qualquer Linux.

Esse desenho **não se aplica ao UDR7**, e a razão não é técnica de rede — é que o console não
executa um cliente NUT. Ver §2.

## 2. Por que não dá para rodar o cliente NUT dentro do console

- **Não existe cliente NUT no UniFi OS.** O pedido formal à Ubiquiti está aberto na
  comunidade desde 2020 e o issue equivalente no `unifios-utilities` foi **fechado como "não
  planejado"** (abril de 2023). Não há entrega oficial.
- **O que a comunidade faz para rodar código no console** é o `unifi-common` (sucessor do
  `unifios-utilities`): um serviço systemd que executa scripts de `/data/on_boot.d` a cada
  boot, com alvo declarado em **UniFi OS 4.x**. Para serviços maiores, o caminho é um
  contêiner `systemd-nspawn` com Debian via `debootstrap`.
- **Mas o próprio guia começa com SSH.** A instalação do `unifi-common` é
  `curl … | /bin/bash` **rodado no dispositivo**, e o guia do contêiner abre com "os comandos
  a seguir são todos executados no roteador **via SSH**". Ou seja: mesmo o caminho que
  eliminaria o SSH em regime **precisa de SSH para ser instalado**.
- **Nenhum addon de NUT existe.** Busca de código por `upsmon` no repositório arquivado:
  **0 ocorrências** (medido em 2026-09-01). Os addons existentes são de rede (IPv6 de
  operadora, Tailscale, contêiner, persistência).
- **Risco declarado:** nada disso é suportado pela Ubiquiti, e a persistência entre
  atualizações de firmware é o problema que o próprio projeto existe para resolver — o que
  diz que ele é real.

## 3. Por que a API oficial não resolve

A **UniFi Network API** pública expõe ação em dispositivo adotado com a ação **`RESTART`**.
Não há `POWER_OFF`/`SHUTDOWN` — na interface do aplicativo, os controles de gerenciamento do
dispositivo são "Locate" e "Restart".

Reiniciar não serve para o nosso caso: numa queda de energia o objetivo é **desligar
graciosamente antes de a bateria acabar**, não reiniciar. Um `RESTART` durante a queda
gastaria bateria e devolveria o console ligado.

## 4. O que a comunidade de fato usa (os cases)

O caso mais citado (gist "Graceful shutdown of UDMP via NUT upon power loss") faz exatamente
o que este projeto faz, com duas diferenças que valem citar:

```
SHUTDOWNCMD "/bin/bash -c 'sshpass -p "senha" ssh -o StrictHostKeyChecking=no \
    root@192.168.50.1 "ubnt-systool poweroff" & sleep 3 && /sbin/shutdown -h +0'"
```

- Ele usa **senha em texto claro** (`sshpass`) e **desliga a verificação de host key**
  (`StrictHostKeyChecking=no`). Nós usamos **chave dedicada** e
  `StrictHostKeyChecking=yes` contra um `known_hosts` próprio. Nesse ponto estamos acima do
  case, não abaixo.
- Ele confirma o comando: **`ubnt-systool poweroff`**, e a comunidade registra que é
  preferível ao `poweroff` do Linux por ser mais gracioso com os processos do UniFi OS.

## 5. O River 3 Plus no NUT

- O aparelho fala **USB HID UPS**, o mesmo padrão de APC/CyberPower/Eaton, e é lido pelo
  driver **`usbhid-ups`**.
- **Divergência entre fontes, declarada:** um artigo de 2026-03 afirma um "EcoFlow HID 0.01
  subdriver" já no NUT 2.8.4; a issue #2735 do projeto NUT (aberta em 2024-12) mostra o
  aparelho caindo no subdriver genérico **EXPLORE HID 0.1**, com `libusb_get_interrupt:
  Connection timed out`, e está marcada para a **2.8.6**.
- **Medição pendente:** qual subdriver o Mac mini está usando de fato. Não medi porque a
  sessão está no MacBook, e o River e o NUT estão no mini. Comando para fechar isso lá:
  `upsc river@127.0.0.1 driver.version.internal driver.version.data`.

---

## 6. A lista de comandos do plugin do UDR7

### 6.1 O que o código executa HOJE (lido em `src/river_unifi_bridge/protect.py`)

| Quando | Comando | Destrutivo? |
|---|---|---|
| Verificação do host antes de agir | `ssh-keygen -F <host> -f <known_hosts>` | não |
| Ao decidir desligar | `ssh … -- root@<host> "ubnt-systool poweroff"` | **SIM** |
| Ao religar (opcional) | magic packet WoL, UDP 9 broadcast | não |

O `ssh` é montado isolado, e cada opção tem uma razão: `-F /dev/null` (ignora config do
usuário e do sistema), `BatchMode=yes` (nunca pergunta nada), `IdentitiesOnly=yes` +
`PasswordAuthentication=no` + `KbdInteractiveAuthentication=no` (só a chave dedicada),
`StrictHostKeyChecking=yes` com `UserKnownHostsFile` próprio e `GlobalKnownHostsFile=/dev/null`,
`ProxyCommand=none`, `PermitLocalCommand=no`, `ControlMaster=no`/`ControlPath=none` (sem
multiplexação), `ForwardAgent=no`, `ClearAllForwardings=yes`, e `--` antes do destino para que
nenhum valor configurado possa ser lido como opção.

### 6.2 O que FALTA — e é a lacuna que o estado `armado_nao_verificado` denuncia

Hoje o daemon arma **sem nunca ter falado com o console**. O estado
`armado_nao_verificado` existe exatamente porque não há prova de alcance. Proponho três
comandos novos, **todos não destrutivos**:

| Nome | Comando | Para quê |
|---|---|---|
| **probe de alcance** | `ssh … -- root@<host> "command -v ubnt-systool"` | prova que o SSH conecta, a chave é aceita e o binário existe (é a hipótese H11a, nunca verificada) |
| **identidade do console** | `ssh … -- root@<host> "ubnt-systool info \| head -20"` ou `uname -a` | registra modelo/versão do UniFi OS no diagnóstico e no log |
| **ensaio de desligamento** | o probe acima, disparado pelo mesmo caminho de decisão do `poweroff` | o "ensaio" atual não toca o console; com isto ele exercita a rota inteira menos o ato final |

Com o probe, `armado_nao_verificado` vira `armado` de verdade, e o botão "Testar conexão" na
folha do dispositivo passa a ter o que chamar.

---

## 7. Conclusão

1. **SSH não é contornável** para desligar o UDR7: a API oficial não desliga, não existe
   cliente NUT no UniFi OS, e o caminho de rodar código no console também começa por SSH.
2. **O que fazemos já é melhor que o case da comunidade** em segurança (chave dedicada e
   verificação estrita de host, contra senha em claro e verificação desligada).
3. **O que falta não é o caminho, é a prova**: nunca conversamos com o console. O probe de
   alcance é a peça que falta, e ela é não destrutiva.

## Fontes

- Cliente NUT no UniFi OS, pedido fechado como não planejado —
  <https://github.com/unifi-utilities/unifios-utilities/issues/528>
- Pedido à Ubiquiti (comunidade) —
  <https://community.ui.com/questions/Please-add-a-NUT-client-to-UDM-Pro-for-graceful-shutdown/15abe09f-0b39-4d73-bbc3-a2e45d48c5ab>
- Case de referência, SSH + `ubnt-systool poweroff` —
  <https://gist.github.com/Freekers/c8e4b75e02bf26e68c4ee6da5a6b2392>
- `unifi-common` (executar código no console; alvo UniFi OS 4.x) —
  <https://github.com/unifi-utilities/unifi-common>
- Contêiner no console, "todos os comandos via SSH" —
  <https://github.com/unifi-utilities/unifi-common-addons>
- API oficial só com `RESTART` —
  <https://community.ui.com/questions/Any-way-to-schedule-reboots-of-APs/7f3fe1ec-7c1a-483c-9701-08cc4c9de499>
- Shutdown/poweroff pedido à Ubiquiti —
  <https://community.ui.com/questions/Shutdown-Poweroff-Option-for-Unifi-Hardware/89a4a4ab-65d2-4489-b89f-639593e9ab5a>
- `ubnt-systool` e seus subcomandos —
  <https://lazyadmin.nl/home-network/unifi-ssh-commands/>
- River 3 Plus no NUT, issue aberta (subdriver EXPLORE, marcada para 2.8.6) —
  <https://github.com/networkupstools/nut/issues/2735>
- River 3 Plus como UPS de primeira classe no Linux (artigo, 2026-03) —
  <https://medium.com/@darshan.rajvi.shah/how-i-turned-a-portable-power-station-into-a-ups-for-my-ugreen-nas-using-a-usb-cable-and-nut-c8731b6c4e8a>
