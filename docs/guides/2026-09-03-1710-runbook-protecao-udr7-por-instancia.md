---
status: superado por 2026-09-05-1100-runbook-acesso-ao-console-e-haos.md
---

# Runbook — Proteção do UDR7 como instância (0.3.0) — 2026-09-03

Substitui `../2026-09-01-0817-runbook-protecao-udr7-ssh.md` (era das 17 chaves planas). O
método de **medição** dos limiares (descarga em segundos por 1 %, margem) continua o daquele
documento, seções "medir" (H15/H17); aqui muda **onde** a configuração mora e **como** se arma.

Nada aqui arma a proteção. A instância nasce em **ensaio** e só arma por ato do dono, em 3
passos. A ratificação do desligamento real do console continua **pendente**.

## 1. Onde mora o quê

| O quê | Onde | Quem escreve |
|---|---|---|
| a instância `udr7` (nome, host, porta, usuário, chave, limiares, MAC de religamento, ensaio, ligada) | `~/Library/Application Support/river-unifi-bridge/devices.json` (0600, do usuário do serviço) | o app, por `PUT /v1/devices/udr7` |
| o espelho da instância | `/usr/local/river-unifi-bridge/etc/bridge.env`, bloco 6 (`PROTECT_*`/`UDR7_*`) | o daemon, a cada PUT da instância; **nunca** no boot |
| a trava global de armamento | `UDR7_ARM_ALLOWED` no mesmo `.env` | **só você**, no arquivo (o PUT recusa) |
| série esperada e corte físico do River | `UDR7_EXPECTED_SERIAL`, `UDR7_CUTOFF_PERCENT` no `.env` | o app, em **Ajustes → River** (`PUT /v1/config`) |
| estado da instância | `udr7_known_hosts`, `udr7_armed.json`, `udr7_runtime.json` no mesmo diretório | `known_hosts`: você; os outros: o daemon |

## 2. Preparar (uma vez)

1. Chave SSH dedicada, no Mac mini, como o usuário do serviço:
   `ssh-keygen -t ed25519 -f ~/.ssh/river-bridge-udr7 -N ""` e a pública no console (conta com
   permissão de desligar).
2. Semear o `known_hosts` da instância: `ssh-keyscan -p 22 <ip do console> >> "~/Library/Application Support/river-unifi-bridge/udr7_known_hosts"`.
3. Provar o alcance sem desligar nada: `ssh -i ~/.ssh/river-bridge-udr7 -o BatchMode=yes -o UserKnownHostsFile="…/udr7_known_hosts" root@<ip> true` → `echo $?` = 0.
4. No app, **Ajustes → River**: número de série esperado (`upsc <ups> device.serial`) e corte físico.
5. No app, a folha do UDR7 (Ajustes → Dispositivos protegidos → UDR7): host, porta, usuário,
   caminho absoluto da chave, limiares medidos (runbook anterior, seção "medir").

## 3. Armar (3 passos, só o dono)

1. No `.env`: `UDR7_ARM_ALLOWED=1`; reinicie o serviço (`sudo launchctl kickstart -k system/com.river.unifi-bridge`).
2. No app, na folha do UDR7, **Armamento → Desligar modo ensaio…** e confirme. O serviço só aceita
   com trava aberta, leitura corrente do River registrado (serial) e fonte não sintética; qualquer
   recusa aparece no rodapé da folha.
3. No `.env`: `UDR7_ARM_ALLOWED=0`; reinicie. O estado armado persiste em `udr7_armed.json`.

Enquanto armada, a instância congela seus campos e as chaves do núcleo (`NUT_*`, série, corte):
o app recusa com "Armada: ligue o modo ensaio antes…". Só o **nome** pode mudar.

## 4. Desarmar

Na folha: **Ligar modo ensaio** (ou desligue o interruptor da lista). Sempre aceito, sem trava.
Apaga `udr7_armed.json` e emite `UDR7_DISARMED`.

## 5. Atualizar o serviço com a proteção armada

O instalador **recusa** (código 3, sem reiniciar, sem tocar no plist) enquanto existir
`*_armed.json`. Desarme pelo app, atualize, arme de novo.

## 6. Recuperar

- Console desligado e sem WoL: ligue-o na tomada; a instância volta a `aguardando_restauracao`
  e rearma quando a energia volta (`UDR7_PROTECTION_REARMED`).
- `config_trocada` (bloqueada): a configuração mudou no arquivo depois de armar. Desarme e arme de novo.
- `host_desconhecido`: o `udr7_known_hosts` não tem a chave do console. Repita o passo 2.2.

## 7. Reverter para a 0.2.0

`curl … | bash -s -- --release v0.2.0`. O `.env` está fiel à instância (todo PUT espelhou):
nenhuma cópia manual. Outras instâncias ficam sem proteção até voltar à 0.3.0.
