---
status: aceito
---

# Runbook — "Computador ou servidor via SSH" (tipo `ssh_host`, 0.3.0) — 2026-09-03

Um dispositivo deste tipo é uma **ação de desligamento nomeada**: numa queda confirmada, com a
bateria do River cruzando o limiar da instância (acima do corte físico), o serviço faz SSH na
máquina e roda **um comando da lista fechada**. Nasce em ensaio; arma em 3 passos, como o UDR7.

## 1. A lista fechada de comandos (`shutdown_command`)

`shutdown -h now` · `sudo -n shutdown -h now` · `/sbin/shutdown -h now` ·
`sudo -n /sbin/shutdown -h now` · `poweroff` · `sudo -n poweroff` · `systemctl poweroff` ·
`sudo -n systemctl poweroff`. Cada um tem a fonte (man page) em
`src/river_unifi_bridge/plugins/ssh_host.py`. `sudo -n` porque a sessão roda com
`BatchMode=yes`: não há prompt de senha. Texto livre é recusado (400 `validacao`).

## 2. Preparar a máquina alvo (uma vez por instância)

1. No Mac mini, como o usuário do serviço, uma chave **por instância**:
   `ssh-keygen -t ed25519 -f ~/.ssh/river-bridge-<id> -N ""` (o `<id>` aparece na folha e em
   `GET /v1/devices`, por exemplo `sshhost_3fa9c1d2`).
2. Na máquina alvo, a pública em `~/.ssh/authorized_keys` do usuário escolhido.
3. Se o comando escolhido leva `sudo -n`, na máquina alvo (`visudo`), **só aquele comando**:
   `<usuario> ALL=(root) NOPASSWD: /sbin/shutdown -h now`
4. Semear o `known_hosts` da instância, no Mac mini:
   `ssh-keyscan -p <porta> <host> >> "~/Library/Application Support/river-unifi-bridge/<id>_known_hosts"`
5. Provar o alcance sem desligar nada:
   `ssh -i ~/.ssh/river-bridge-<id> -o BatchMode=yes -o UserKnownHostsFile="…/<id>_known_hosts" <usuario>@<host> true` → `echo $?` = 0.
   Com `sudo -n`: `… sudo -n true` também tem de dar 0.

## 3. Adicionar no app

Ajustes → Dispositivos protegidos → **Adicionar dispositivo…** → "Computador ou servidor via
SSH" → nome, endereço, porta, usuário, caminho absoluto da chave, comando (seletor), limiares →
**Adicionar**. A linha nova aparece desligada e em ensaio. Ligue o interruptor: em ensaio, o
serviço registra `SSH_HOST_SHUTDOWN_DRYRUN` numa queda em vez de enviar.

## 4. Armar (3 passos, só o dono)

Iguais aos do UDR7 (a trava `UDR7_ARM_ALLOWED` é **global**): trava aberta + reinício;
"Desligar modo ensaio…" na folha da instância; trava fechada + reinício. Armar exige leitura
corrente do River registrado (Ajustes → River) e fonte não sintética; com duas instâncias, cada
uma arma e desarma sozinha — desarmar uma não pede nada da outra.

## 5. Estados que a folha e o cartão de Saúde mostram

`Desligada`, `Modo ensaio`, `Armada` (até a 0.8.7 o selo dizia "Armada — alcance não
verificado", tradução ao pé da letra do nome do estado e falsa: o alcance é provado pelo
"Testar conexão"; emenda de 2026-09-06, 0.9.0), `Desligamento enviado`,
`Bloqueada — …` (fonte não aceita, corte do River não configurado, limiar ≤ corte+1,
configuração incompleta, chave SSH ausente/insegura, máquina fora do `known_hosts`,
calibrando, armamento ausente, configuração mudou após armar), `Aguardando energia voltar`.

## 6. Remover

Rodapé da folha → **Remover dispositivo…** → confirmar. Armada, o serviço recusa (409): desarme
antes. A remoção apaga `<id>_armed.json` e `<id>_runtime.json` e **mantém** `<id>_known_hosts`
(aviso `known_hosts_kept` no log); a chave em `~/.ssh` e a pública na máquina alvo são suas.
