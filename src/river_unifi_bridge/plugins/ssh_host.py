"""Computador ou servidor via SSH — o segundo tipo de dispositivo (2026-09-03).

Qualquer máquina Linux/BSD/macOS com chave SSH dedicada: na queda confirmada o
motor comum manda UM comando de desligamento, escolhido de uma LISTA FECHADA.
Não há texto livre: o valor vira o último elemento do argv do `ssh` (depois de
`--`, S4k) e a única superfície que sobraria seria o conteúdo do comando — a
lista a fecha. `sudo -n` porque com `BatchMode=yes` não existe prompt: ou o
sudoers do host libera o comando sem senha, ou o `ssh` volta rc≠0 e o evento é
`SSH_HOST_SHUTDOWN_FAILED`, nunca um prompt pendurado.

Este módulo NÃO tem seam de processo próprio (nada de subprocess/os.system):
todo spawn é o `ssh_argv` + runner de protect.py, coberto pela cerca anti-spawn.
"""

from __future__ import annotations

from ..config import CORE_FROZEN_KEYS
from ..devices import DevicesError
from .base import FieldSpec
from .ssh_motor import SshMotorPlugin
from .udr7_ssh import SSH_FIELDS

# comando → fonte (gramática da casa: [P] primária = a man page do próprio comando).
SHUTDOWN_COMMANDS: dict[str, str] = {
    "shutdown -h now":
        "[P] shutdown(8) do macOS/BSD e do systemd: -h desliga ('halt'/'power-off'); "
        "'now' = imediatamente. É o comando que o próprio apcupsd/NUT (SHUTDOWNCMD) usa",
    "sudo -n shutdown -h now":
        "[P] sudo(8): -n 'non-interactive', nunca pede senha — falha em vez de travar; "
        "exige regra NOPASSWD no sudoers do host para este comando",
    "/sbin/shutdown -h now":
        "[P] shutdown(8): o caminho absoluto evita depender do PATH de um shell remoto "
        "restrito (o mesmo comando, sem resolução de PATH)",
    "sudo -n /sbin/shutdown -h now":
        "[P] sudo(8) -n + shutdown(8) por caminho absoluto: o par mais estrito para uma "
        "regra NOPASSWD que nomeia o binário",
    "poweroff":
        "[P] poweroff(8) do systemd: 'Power off the machine' — equivale a "
        "'systemctl poweroff' quando o systemd é o init",
    "sudo -n poweroff":
        "[P] sudo(8) -n (non-interactive, falha em vez de pedir senha) + poweroff(8) do "
        "systemd; exige regra NOPASSWD para o poweroff no host",
    "systemctl poweroff":
        "[P] systemctl(1): 'poweroff — Shut down and power-off the system'",
    "sudo -n systemctl poweroff":
        "[P] sudo(8) -n (non-interactive) + systemctl(1) poweroff; exige regra NOPASSWD "
        "para o systemctl no host",
}
DEFAULT_SHUTDOWN_COMMAND = "shutdown -h now"

SSH_HOST_FIELDS: tuple[FieldSpec, ...] = SSH_FIELDS + (
    FieldSpec("shutdown_command", "str", DEFAULT_SHUTDOWN_COMMAND,
              enum=tuple(SHUTDOWN_COMMANDS)),
)


class SshHostPlugin(SshMotorPlugin):
    type_id = "ssh_host"
    label_pt = "Computador ou servidor via SSH"
    label_en = "Computer or server over SSH"
    default_name = "Servidor SSH"
    event_prefix = "SSH_HOST_"
    fields = SSH_HOST_FIELDS
    legacy_keys = frozenset()          # tipos novos nunca ganham chave no .env

    @classmethod
    def comandos_de_leitura(cls) -> dict[str, str]:
        """Num host POSIX qualquer não há `ubnt-device-info`: o que prova alcance
        é o mesmo `true` do probe deste tipo, mais o nome da máquina."""
        return {"probe": "true", "model": "uname -sm", "firmware": "uname -r"}
    frozen_keys = CORE_FROZEN_KEYS

    @classmethod
    def shutdown_command_for(cls, instance) -> str:
        value = instance.fields.get("shutdown_command", DEFAULT_SHUTDOWN_COMMAND)
        # Defesa em profundidade: validate_fields já recusa no POST/PUT; aqui é a
        # última porta antes de o comando virar argv — uma loja editada à mão
        # não passa.
        if value not in SHUTDOWN_COMMANDS:
            raise DevicesError(
                f"instância {instance.id}: comando de desligamento fora da lista permitida")
        return value
