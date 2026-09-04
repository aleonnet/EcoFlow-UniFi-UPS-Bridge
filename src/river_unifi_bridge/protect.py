"""Fase 3'-EXP — UDR7 protection policy (graceful SSH poweroff of the console).

Experimental phase, separate from the primary path (spec §2.5). Design and every
number/source: plan "piped-seeking-toast v5.1" and docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md.

Property M1 (verifiable): the daemon only runs `ssh … poweroff` when, in the same
tick, ALL gates pass — source outside the synthetic-driver denylist, NUT endpoint on
loopback, serial equal to the owner's registered serial, armed.json pinning the whole
protection config, dedicated known_hosts entry, cutoff/threshold configured with the
threshold above the cutoff, key file 0600 owned by us, not calibrating, no SENT
pending a restore, and dry-run off. Anything else is BLOCKED (or DRYRUN in rehearsal).

Threading: decisions happen under the policy lock; the spawn happens OUTSIDE any lock;
the result is committed under the lock again. The API thread calls
`on_config_applied` after releasing the ConfigHolder lock (never nested).

Test seams: `_RUNNER`, `_KEYGEN_RUNNER`, `_WOL_SENDER` are resolved at call time so a
conftest can replace them; `RUB_SSH_BINARY` points the ssh binary (E2E stub) and is
exposed in the health detail and pinned at arming time.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import tempfile
import threading
import time
from dataclasses import asdict, dataclass, fields

# --- constants (sources/marks in the runbook) -------------------------------------
SSH_BINARY = os.environ.get("RUB_SSH_BINARY", "/usr/bin/ssh")
SSH_KEYGEN = "/usr/bin/ssh-keygen"
SSH_CONNECT_TIMEOUT_SECONDS = 15   # ANALOGIA upsmon HOSTSYNC (PESQUISA_PARAMETROS:102)
SUBPROCESS_TIMEOUT_SECONDS = 20    # 15 + FINALDELAY 5 (same analogy); also retry spacing
KEYGEN_TIMEOUT_SECONDS = 5         # PROVISÓRIO-SEM-FONTE
RUNTIME_SANITY_SECONDS = 86400     # PROVISÓRIO-SEM-FONTE (24 h; 40 h quirk guard)
HALT_SECONDS = 30                  # PROVISÓRIO-SEM-FONTE (console halt time in margin estimate)
WOL_PORT = 9                       # [S] Wikipedia WoL: "port 0, 7 or 9" — choice: 9
WOL_BROADCAST = "255.255.255.255"  # limited broadcast (INFERIDO from the same source)
LOOPBACK_HOSTS = frozenset({"127.0.0.1", "::1"})   # literal; `localhost` is refused

# Denylist of simulation drivers: ours + NUT's own (dummy-ups, clone, clone-outlet —
# https://networkupstools.org/docs/man/dummy-ups.html, .../clone.html).
_SYNTHETIC_DRIVERS = ("fake-nut-ups", "dummy-ups", "dummy", "clone", "clone-outlet")
_SYNTHETIC_SUBSTRINGS = ("fake", "sim", "dummy")

# Events (persisted in history, shown in the timeline)
EV_DRYRUN = "UDR7_SHUTDOWN_DRYRUN"
EV_SENT = "UDR7_SHUTDOWN_SENT"
EV_FAILED = "UDR7_SHUTDOWN_FAILED"
EV_BLOCKED = "UDR7_SHUTDOWN_BLOCKED"
EV_REARMED = "UDR7_PROTECTION_REARMED"
EV_BLIND = "UDR7_PROTECTION_BLIND"
EV_ARMED = "UDR7_ARMED"
EV_DISARMED = "UDR7_DISARMED"
EV_WOL_SENT = "UDR7_WOL_SENT"
EV_WOL_DRYRUN = "UDR7_WOL_DRYRUN"
# O vocabulário FECHADO que a política publica em `state`. Existe porque o app
# desenha um selo por estado (`SshEngineText.badge`): um estado novo aqui, sem
# selo lá, aparece como dispositivo SEM observação nenhuma — bloqueado e mudo. É
# publicado em /v1/device-types justamente para o app poder conferir.
PORTOES = (
    "fonte_nao_real", "fonte_nao_local", "corte_nao_configurado",
    "limiar_nao_configurado", "limiar_abaixo_do_corte", "config_incompleta",
    "chave_insegura", "host_desconhecido", "calibrando", "armamento_ausente",
    "config_trocada", "aguardando_restauracao",
)
ESTADOS = ("desabilitado",) + PORTOES + ("dry_run", "armado_nao_verificado", "enviado")


def _rotulo_da_fonte(first_fail: str | None, source_detail: str | None,
                     ja_observou: bool) -> str | None:
    """Como a leitura do UPS foi julgada — para o health e para o payload do evento.

    `sintetica` = veio do simulador; `nao_verificada` = a cerca de fonte reprovou;
    `ok` = algum tick já rodou e a fonte não foi o motivo; `None` = nunca olhei.
    Mesmo comportamento de antes, escrito de um jeito que se lê.
    """
    if source_detail == "telemetria_sintetica":
        return "sintetica"
    if first_fail == "fonte_nao_real":
        return "nao_verificada"
    return "ok" if ja_observou else None


# --- seams (resolved at call time; conftest replaces them in unit tests) ------------
_RUNNER = subprocess.run
_KEYGEN_RUNNER = subprocess.run


def log_json(level: str, event: str, **payload) -> None:
    record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "level": level, "event": event}
    record.update(payload)
    print(json.dumps(record, ensure_ascii=False), flush=True)


# --- source fence -------------------------------------------------------------------
def _is_synthetic_driver(name: str | None, version: str | None) -> bool:
    n = (name or "").strip().casefold()
    v = (version or "").strip().casefold()
    if n in _SYNTHETIC_DRIVERS:
        return True
    return any(s in n or s in v for s in _SYNTHETIC_SUBSTRINGS)


def source_verdict(
    driver_name: str | None, driver_version: str | None,
    serial: str | None, expected_serial: str,
) -> str | None:
    """None when the source passes; otherwise the detail token (fail-closed)."""
    if not driver_name or not driver_version:
        return "fonte_nao_verificada"
    if _is_synthetic_driver(driver_name, driver_version):
        return "telemetria_sintetica"
    if not expected_serial:
        return "serial_nao_registrado"
    if serial != expected_serial:
        return "serial_divergente"
    return None


def _is_loopback(host: str) -> bool:
    return host in LOOPBACK_HOSTS


# --- configuration snapshot (single runtime source of truth) ----------------------
# Defaults dos campos de uma INSTÂNCIA (os mesmos da allowlist do .env para o UDR7,
# config.py: porta 22 = ssh_config(5); 6 s = ANALOGIA apcupsd; 3 = PROVISÓRIO).
# Fonte única: devices.py (FieldSpec) e from_instance leem daqui.
INSTANCE_FIELD_DEFAULTS: dict[str, object] = {
    "ssh_host": "", "ssh_port": 22, "ssh_user": "root", "ssh_key": "",
    "shutdown_percent": 0, "discharge_seconds_per_pct": 0, "runtime_minutes": 0,
    "min_outage_seconds": 0, "confirm_seconds": 6, "retry_max": 3, "wol_mac": "",
}
_PIN_EXCLUDED = ("protect_udr7", "protect_dry_run", "udr7_arm_allowed", "udr7_name")


@dataclass(frozen=True)
class ProtectionConfig:
    protect_udr7: bool
    protect_dry_run: bool
    udr7_arm_allowed: bool
    udr7_ssh_host: str
    udr7_ssh_port: int
    udr7_ssh_user: str
    udr7_ssh_key: str
    udr7_expected_serial: str
    udr7_cutoff_percent: int
    udr7_shutdown_percent: int
    udr7_discharge_seconds_per_pct: int
    udr7_runtime_minutes: int
    udr7_min_outage_seconds: int
    udr7_confirm_seconds: int
    udr7_retry_max: int
    udr7_wol_mac: str
    udr7_name: str
    nut_host: str
    nut_port: int
    nut_ups: str
    ssh_binary: str
    # O comando que a política manda ao aparelho. Vazio = o `shutdown_command` do
    # construtor da política (o tipo UDR7 passa a sua tabela). Está no dataclass —
    # e portanto nos PINOS do armamento — para que trocar o comando de uma
    # instância armada vire `config_trocada`, nunca um envio diferente do pinado.
    shutdown_command: str = ""

    # Os campos `udr7_*` são os nomes INTERNOS do motor ("os campos ssh do
    # dispositivo"), herdados do primeiro aparelho. Desde 2026-09-03 o motor serve
    # N instâncias (`from_instance`); renomear os campos quebraria as âncoras do
    # gate (S4d/S4k/S4o) e os pinos gravados em cada `<id>_armed.json`.
    _ENGINE_OWNED = ("ssh_binary", "shutdown_command")

    @classmethod
    def from_cfg(cls, cfg) -> "ProtectionConfig":
        """A instância legada: todos os campos vêm do BridgeConfig plano."""
        values = {f.name: getattr(cfg, f.name) for f in fields(cls) if f.name not in cls._ENGINE_OWNED}
        return cls(ssh_binary=SSH_BINARY, **values)

    @classmethod
    def from_instance(cls, inst, cfg, *, shutdown_command: str = "") -> "ProtectionConfig":
        """Uma instância de dispositivo (devices.json) + o núcleo (BridgeConfig).

        `inst` expõe `enabled`, `dry_run`, `name` e `fields` (dict). Série esperada
        e corte físico NÃO são da instância: são do River, lidos do núcleo para
        toda instância (D16) — sem isso um host SSH ficaria bloqueado para sempre
        em `fonte_nao_real`/`corte_nao_configurado`.
        """
        f = inst.fields
        d = INSTANCE_FIELD_DEFAULTS
        return cls(
            protect_udr7=bool(inst.enabled),
            protect_dry_run=bool(inst.dry_run),
            udr7_arm_allowed=cfg.udr7_arm_allowed,
            udr7_ssh_host=f.get("ssh_host", d["ssh_host"]),
            udr7_ssh_port=int(f.get("ssh_port", d["ssh_port"])),
            udr7_ssh_user=f.get("ssh_user", d["ssh_user"]),
            udr7_ssh_key=f.get("ssh_key", d["ssh_key"]),
            udr7_expected_serial=cfg.udr7_expected_serial,
            udr7_cutoff_percent=cfg.udr7_cutoff_percent,
            udr7_shutdown_percent=int(f.get("shutdown_percent", d["shutdown_percent"])),
            udr7_discharge_seconds_per_pct=int(f.get("discharge_seconds_per_pct", d["discharge_seconds_per_pct"])),
            udr7_runtime_minutes=int(f.get("runtime_minutes", d["runtime_minutes"])),
            udr7_min_outage_seconds=int(f.get("min_outage_seconds", d["min_outage_seconds"])),
            udr7_confirm_seconds=int(f.get("confirm_seconds", d["confirm_seconds"])),
            udr7_retry_max=int(f.get("retry_max", d["retry_max"])),
            udr7_wol_mac=f.get("wol_mac", d["wol_mac"]),
            udr7_name=inst.name,
            nut_host=cfg.nut_host,
            nut_port=cfg.nut_port,
            nut_ups=cfg.nut_ups,
            ssh_binary=SSH_BINARY,
            shutdown_command=shutdown_command,
        )

    @property
    def armed(self) -> bool:
        return self.protect_udr7 and not self.protect_dry_run

    def pins(self) -> dict:
        """Everything that must not change while armed (predicate and lock excluded)."""
        return {k: v for k, v in asdict(self).items() if k not in _PIN_EXCLUDED}


class ConfigHolder:
    """Atomic reference to the current ProtectionConfig (own private lock)."""

    def __init__(self, pc: ProtectionConfig) -> None:
        self._lock = threading.Lock()
        self._pc = pc

    def get(self) -> ProtectionConfig:
        with self._lock:
            return self._pc

    def replace(self, pc: ProtectionConfig) -> ProtectionConfig:
        with self._lock:
            old, self._pc = self._pc, pc
            return old


# --- ssh -------------------------------------------------------------------------
def ssh_argv(pc: ProtectionConfig, known_hosts_path: str, command: str) -> list[str]:
    """Isolated ssh invocation: no user/system config, no agent, no forwarding, no
    proxy, strict host key against our dedicated known_hosts, `--` before the
    destination so no configured value can ever be parsed as an option."""
    return [
        pc.ssh_binary, "-n", "-T", "-F", "/dev/null",
        "-o", "BatchMode=yes",
        "-o", f"ConnectTimeout={SSH_CONNECT_TIMEOUT_SECONDS}",
        "-o", "IdentitiesOnly=yes",
        "-o", "PasswordAuthentication=no",
        "-o", "KbdInteractiveAuthentication=no",
        "-o", "StrictHostKeyChecking=yes",
        "-o", f"UserKnownHostsFile={known_hosts_path}",
        "-o", "GlobalKnownHostsFile=/dev/null",
        "-o", "ProxyCommand=none",
        "-o", "PermitLocalCommand=no",
        "-o", "ControlMaster=no",
        "-o", "ControlPath=none",
        "-o", "ForwardAgent=no",
        "-o", "ClearAllForwardings=yes",
        "-o", "LogLevel=ERROR",
        "-i", pc.udr7_ssh_key,
        "-p", str(pc.udr7_ssh_port),
        "--",
        f"{pc.udr7_ssh_user}@{pc.udr7_ssh_host}",
        command,
    ]


def known_host_ok(host: str, port: int, path: str, *, runner=None) -> bool:
    """Pre-check that our dedicated known_hosts has an entry for host[:port].
    Any non-zero rc (including 255 = file missing) means unknown — fail closed.
    The real fence is StrictHostKeyChecking=yes in the ssh call itself."""
    target = host if port == 22 else f"[{host}]:{port}"
    try:
        result = (runner or _KEYGEN_RUNNER)(
            [SSH_KEYGEN, "-F", target, "-f", path],
            capture_output=True, timeout=KEYGEN_TIMEOUT_SECONDS, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return getattr(result, "returncode", 1) == 0


def key_file_status(path: str) -> str | None:
    """None when the private key is usable; otherwise the gate token."""
    if not path:
        return "config_incompleta"
    try:
        st = os.stat(path)
    except OSError:
        return "chave_insegura"
    if st.st_uid != os.getuid() or (st.st_mode & 0o077) != 0:
        return "chave_insegura"
    return None


# --- Wake-on-LAN (stdlib only; H14 — no source confirms UniFi consoles honour it) ----
def send_magic_packet(mac: str) -> None:
    raw = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    payload = b"\xff" * 6 + raw * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(payload, (WOL_BROADCAST, WOL_PORT))


_WOL_SENDER = send_magic_packet


# --- actions ---------------------------------------------------------------------
@dataclass
class ProtectionAction:
    event: str
    payload: dict


def _emit(actions: list[ProtectionAction], shared, history, log=log_json) -> None:
    """Fan an action out to log, SharedState and HistoryStore (used by service and api)."""
    for action in actions:
        log("WARN", action.event, **action.payload)
        if shared is not None:
            shared.add_event(action.event, action.payload)
        if history is not None:
            detail = action.payload.get("detail") or action.payload.get("host")
            history.record_event(action.event, detail, device=action.payload.get("device"))


def _write_private_json(path: str, data: dict) -> None:
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".udr7-tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, sort_keys=True)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError as exc:
            log_json("WARN", "state_tmp_unlink_failed", path=tmp, reason=str(exc)[:200])
        raise


def _read_private_json(path: str) -> dict | None:
    try:
        st = os.stat(path)
    except OSError:
        return None
    if st.st_uid != os.getuid() or (st.st_mode & 0o077) != 0:
        return None   # do not trust a file we could not have written
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


# --- policy ----------------------------------------------------------------------
class ProtectionPolicy:
    def __init__(
        self,
        holder: ConfigHolder,
        *,
        clock=time.monotonic,
        runner=None,
        keygen_runner=None,
        wol_sender=None,
        known_hosts_path: str,
        armed_path: str,
        runtime_path: str,
        # Sem default: o comando é do APARELHO, e a tabela verificada vive no
        # plugin dele (plugins/udr7_ssh.py, plugins/ssh_host.py). Um default aqui
        # era o motor escolhendo o que mandar para uma máquina que não conhece.
        shutdown_command: str,
        default_name: str = "UDR7",
    ) -> None:
        # O QUE se manda ao aparelho vem do PLUGIN dele; esta classe é o
        # transporte (monta o ssh isolado e executa). O default existe só para
        # não quebrar quem constrói a política direto — o plugin do UDR7 passa
        # o comando da sua própria tabela, com fonte verificada. Um comando
        # PINADO na ProtectionConfig (`shutdown_command`) tem precedência.
        self._shutdown_command = shutdown_command
        self._default_name = default_name
        self._holder = holder
        self._clock = clock
        self._runner = runner
        self._keygen_runner = keygen_runner
        self._wol_sender = wol_sender
        self._known_hosts_path = known_hosts_path
        self._armed_path = armed_path
        self._runtime_path = runtime_path
        self._lock = threading.Lock()
        # per-outage state
        self._outage = False
        self._outage_since: float | None = None
        self._attempts = 0
        self._latched = False
        self._cond_since: float | None = None
        self._last_attempt_at: float | None = None
        self._blind_emitted = False
        self._sent_this_outage = False
        self._dryrun_this_outage = False
        # cross-tick state
        self._sent_pending_restore: bool | None = None   # lazily loaded from runtime file
        self._known_host_cache: tuple | None = None
        self._last_state: str | None = None
        self._pending_transition: tuple[str | None, str] | None = None
        self._last_event: str | None = None
        self._last_event_at: str | None = None
        self._last_first_fail: str | None = None
        self._last_source_detail: str | None = None
        self._last_missing_key: str | None = None
        self._last_snapshot_bits: dict = {}

    # -- helpers ------------------------------------------------------------
    def _now_iso(self) -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%S%z")

    def _note(self, event: str) -> None:
        self._last_event = event
        self._last_event_at = self._now_iso()

    def _load_runtime(self) -> None:
        if self._sent_pending_restore is None:
            data = _read_private_json(self._runtime_path) or {}
            self._sent_pending_restore = bool(data.get("sent_pending_restore", False))

    def _save_runtime(self) -> None:
        """Grava a lembrança de "já enviei nesta queda"; falhar aqui não trava a proteção.

        Só existem dois chamadores, e os dois são pontos de COMMIT: a restauração
        (que zera a queda) e o envio (que emite o evento). Com disco cheio, a
        gravação levantava e derrubava o processo; com a rede do laço aparando,
        derrubaria a instância num estado travado, em silêncio. O estado em
        memória vale do mesmo jeito e o arquivo é reescrito no próximo commit.
        """
        try:
            _write_private_json(
                self._runtime_path,
                {"sent_pending_restore": bool(self._sent_pending_restore),
                 "updated_at": self._now_iso()},
            )
        except OSError as exc:
            log_json("WARN", "runtime_write_failed",
                     path=self._runtime_path, reason=str(exc)[:200])

    def _known_host(self, pc: ProtectionConfig) -> bool:
        path = self._known_hosts_path
        try:
            st = os.stat(path)
            sig = (pc.udr7_ssh_host, pc.udr7_ssh_port, st.st_mtime_ns, st.st_size)
        except OSError:
            sig = (pc.udr7_ssh_host, pc.udr7_ssh_port, None, None)
            if self._known_host_cache and self._known_host_cache[0] == sig:
                return False
            self._known_host_cache = (sig, False)   # absent file: memorised as unknown
            return False
        if self._known_host_cache and self._known_host_cache[0] == sig:
            return self._known_host_cache[1]
        ok = known_host_ok(pc.udr7_ssh_host, pc.udr7_ssh_port, path, runner=self._keygen_runner)
        self._known_host_cache = (sig, ok)
        return ok

    def _armed_file_state(self, pc: ProtectionConfig) -> str | None:
        data = _read_private_json(self._armed_path)
        if data is None:
            return "armamento_ausente"
        if data.get("pins") != pc.pins():
            return "config_trocada"
        return None

    def _first_fail(self, pc: ProtectionConfig, snap) -> tuple[str | None, str | None, str | None]:
        """(gate, source_detail, missing_key) in precedence order."""
        detail = source_verdict(
            getattr(snap, "driver_name", None), getattr(snap, "driver_version", None),
            getattr(snap, "serial", None), pc.udr7_expected_serial,
        )
        if detail is not None:
            return "fonte_nao_real", detail, None
        if not _is_loopback(pc.nut_host):
            return "fonte_nao_local", None, None
        if pc.udr7_cutoff_percent <= 0:
            return "corte_nao_configurado", None, None
        if pc.udr7_shutdown_percent <= 0:
            return "limiar_nao_configurado", None, None
        if pc.udr7_shutdown_percent <= pc.udr7_cutoff_percent + 1:
            return "limiar_abaixo_do_corte", None, None
        for key_name, value in (
            ("UDR7_SSH_HOST", pc.udr7_ssh_host),
            ("UDR7_SSH_USER", pc.udr7_ssh_user),
            ("UDR7_SSH_KEY", pc.udr7_ssh_key),
        ):
            if not value:
                return "config_incompleta", None, key_name
        key_state = key_file_status(pc.udr7_ssh_key)
        if key_state is not None:
            return key_state, None, ("UDR7_SSH_KEY" if key_state == "config_incompleta" else None)
        if not self._known_host(pc):
            return "host_desconhecido", None, None
        if snap is not None and "CALIBRATING" in getattr(snap, "states", []):
            return "calibrando", None, None
        if pc.armed:
            # armed.json only exists after the arming transition; in rehearsal these
            # two gates would only hide the more useful `dry_run` state.
            armed_state = self._armed_file_state(pc)
            if armed_state is not None:
                return armed_state, None, None
        self._load_runtime()
        if self._sent_pending_restore:
            return "aguardando_restauracao", None, None
        return None, None, None

    def _battery_condition(self, pc: ProtectionConfig, snap) -> bool:
        charge = getattr(snap, "charge_percent", None)
        if charge is not None and charge <= pc.udr7_shutdown_percent:
            return True
        runtime = getattr(snap, "runtime_seconds", None)
        if (
            pc.udr7_runtime_minutes > 0
            and runtime is not None
            and runtime <= RUNTIME_SANITY_SECONDS
            and runtime <= pc.udr7_runtime_minutes * 60
        ):
            return True
        return False

    def _margin_estimate(self, pc: ProtectionConfig) -> int | None:
        if pc.udr7_discharge_seconds_per_pct <= 0:
            return None
        return (pc.udr7_shutdown_percent - pc.udr7_cutoff_percent) * pc.udr7_discharge_seconds_per_pct

    def _warnings(self, pc: ProtectionConfig, snap) -> list[str]:
        out: list[str] = []
        if pc.udr7_arm_allowed:
            out.append("lock_open")
        if pc.armed:
            if snap is not None and getattr(snap, "charge_percent", None) is None:
                out.append("charge_missing")
            margin = self._margin_estimate(pc)
            if margin is None:
                out.append("margin_unknown")
            elif margin < pc.udr7_confirm_seconds + pc.udr7_retry_max * SUBPROCESS_TIMEOUT_SECONDS + HALT_SECONDS:
                out.append("margin_short")
        return out

    def _state_for(self, pc: ProtectionConfig, first_fail: str | None) -> str:
        if not pc.protect_udr7:
            return "desabilitado"
        if first_fail == "aguardando_restauracao" and self._sent_this_outage:
            return "enviado"   # this process sent it; the gate only guards a restart mid-outage
        if first_fail is not None:
            return first_fail
        if pc.protect_dry_run:
            return "dry_run"
        if self._latched and self._sent_this_outage:
            return "enviado"
        return "armado_nao_verificado"

    def _track_state(self, new_state: str) -> None:
        if new_state != self._last_state:
            self._pending_transition = (self._last_state, new_state)
            self._last_state = new_state

    def _reset_outage(self) -> None:
        self._outage = False
        self._outage_since = None
        self._attempts = 0
        self._latched = False
        self._cond_since = None
        self._last_attempt_at = None
        self._blind_emitted = False
        self._sent_this_outage = False
        self._dryrun_this_outage = False

    # -- public -------------------------------------------------------------
    def observe(self, snap, tracker_events: list[str]) -> list[ProtectionAction]:
        pc = self._holder.get()   # once per tick, outside the policy lock
        now = self._clock()
        actions: list[ProtectionAction] = []
        fire_real = False
        argv: list[str] = []
        base_payload: dict = {}
        wol_mac: str | None = None

        with self._lock:
            self._load_runtime()
            if "POWER_LOSS" in tracker_events and not self._outage:
                self._reset_outage()
                self._outage = True
                self._outage_since = now
            restored = "POWER_RESTORED" in tracker_events or (
                snap.state == "ONLINE" and self._sent_pending_restore
            )
            if restored:
                if self._sent_pending_restore:
                    self._sent_pending_restore = False
                    self._save_runtime()
                if self._outage and (self._latched or self._attempts > 0):
                    actions.append(ProtectionAction(EV_REARMED, {"host": pc.udr7_ssh_host}))
                    self._note(EV_REARMED)
                fired = self._sent_this_outage or (pc.protect_dry_run and self._dryrun_this_outage)
                if self._outage and fired and pc.udr7_wol_mac:
                    if pc.protect_dry_run:
                        actions.append(ProtectionAction(
                            EV_WOL_DRYRUN,
                            {"mac": pc.udr7_wol_mac, "port": WOL_PORT, "detail": "ensaio"}))
                    else:
                        wol_mac = pc.udr7_wol_mac
                        actions.append(ProtectionAction(
                            EV_WOL_SENT, {"mac": pc.udr7_wol_mac, "port": WOL_PORT}))
                    self._note(actions[-1].event)
                if self._outage:
                    self._reset_outage()

            first_fail, source_detail, missing_key = self._first_fail(pc, snap)
            self._last_first_fail, self._last_source_detail, self._last_missing_key = (
                first_fail, source_detail, missing_key)
            self._last_snapshot_bits = {
                "charge": getattr(snap, "charge_percent", None),
                "charge_low": getattr(snap, "battery_charge_low_percent", None),
                "state": snap.state,
                "warnings": self._warnings(pc, snap),
            }
            self._track_state(self._state_for(pc, first_fail))

            eligible = (
                pc.protect_udr7
                and self._outage
                and snap.state == "ON_BATTERY"
                and "CALIBRATING" not in snap.states
                and self._outage_since is not None
                and now - self._outage_since >= pc.udr7_min_outage_seconds
                and not self._latched
                and (self._last_attempt_at is None
                     or now - self._last_attempt_at >= SUBPROCESS_TIMEOUT_SECONDS)
            )
            if eligible:
                if self._battery_condition(pc, snap):
                    if self._cond_since is None:
                        self._cond_since = now
                    confirmed = now - self._cond_since >= pc.udr7_confirm_seconds
                else:
                    self._cond_since = None
                    confirmed = False
                if confirmed:
                    base_payload = {
                        "host": pc.udr7_ssh_host,
                        "source": _rotulo_da_fonte(first_fail, source_detail, True),
                        "source_detail": source_detail,
                        "attempt": self._attempts + 1,
                        "threshold": pc.udr7_shutdown_percent,
                        "charge": getattr(snap, "charge_percent", None),
                    }
                    if pc.protect_dry_run:
                        self._latched = True
                        self._dryrun_this_outage = True
                        actions.append(ProtectionAction(
                            EV_DRYRUN, {**base_payload, "would_block": first_fail,
                                        "detail": first_fail or "ok"}))
                        self._note(EV_DRYRUN)
                    elif first_fail is not None:
                        self._latched = True
                        actions.append(ProtectionAction(
                            EV_BLOCKED, {**base_payload, "detail": first_fail}))
                        self._note(EV_BLOCKED)
                    elif self._attempts >= pc.udr7_retry_max:  # tentativas esgotadas
                        # `retry_max` é o NÚMERO de tentativas, e este é o único
                        # lugar que o conta. Com 3, saem 3 envios e o 4.º tick
                        # bloqueia; com 0, nenhum envio sai — e o ensaio, que é
                        # julgado antes, continua avisando o que faria.
                        self._latched = True
                        actions.append(ProtectionAction(
                            EV_BLOCKED, {**base_payload, "attempt": self._attempts,
                                         "detail": "tentativas_esgotadas"}))
                        self._note(EV_BLOCKED)
                    else:
                        self._attempts += 1
                        self._last_attempt_at = now
                        argv = ssh_argv(pc, self._known_hosts_path, pc.shutdown_command or self._shutdown_command)
                        fire_real = True
            elif not self._outage:
                self._cond_since = None

        if wol_mac is not None:
            # Outside the lock; the only place a magic packet ever leaves the process.
            try:
                (self._wol_sender or _WOL_SENDER)(wol_mac)
            except (OSError, AssertionError) as exc:
                log_json("WARN", "udr7_wol_failed", mac=wol_mac, reason=str(exc)[:200])

        if not fire_real:
            return actions

        # Spawn OUTSIDE any lock (may take up to SUBPROCESS_TIMEOUT_SECONDS).
        rc: int | None = None
        error = ""
        try:
            result = (self._runner or _RUNNER)(
                argv, capture_output=True, timeout=SUBPROCESS_TIMEOUT_SECONDS, check=False,
            )
            rc = getattr(result, "returncode", None)
            stderr = getattr(result, "stderr", b"") or b""
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", "replace")
            error = stderr.strip()[:200]
        except subprocess.TimeoutExpired:
            error = "timeout"
        except (OSError, subprocess.SubprocessError, AssertionError) as exc:
            error = str(exc)[:200]

        with self._lock:
            if rc == 0:
                self._latched = True
                self._sent_this_outage = True
                self._sent_pending_restore = True
                self._save_runtime()
                actions.append(ProtectionAction(EV_SENT, {**base_payload, "detail": "enviado"}))
                self._note(EV_SENT)
            else:
                detail = "host_key_mudou" if "HOST IDENTIFICATION HAS CHANGED" in error.upper() else (
                    "host_desconhecido" if "HOST KEY VERIFICATION FAILED" in error.upper() else
                    ("timeout" if error == "timeout" else f"rc={rc}"))
                actions.append(ProtectionAction(
                    EV_FAILED, {**base_payload, "detail": detail, "error": error}))
                self._note(EV_FAILED)
            self._track_state(self._state_for(pc, self._last_first_fail))
        return actions

    def observe_failure(self, tracker_events: list[str]) -> list[ProtectionAction]:
        pc = self._holder.get()
        with self._lock:
            if "COMM_LOST" in tracker_events and self._outage and not self._blind_emitted:
                self._blind_emitted = True
                self._note(EV_BLIND)
                return [ProtectionAction(
                    EV_BLIND, {"host": pc.udr7_ssh_host, "detail": "comm_lost_em_queda"})]
        return []

    def on_config_applied(self, old: ProtectionConfig, new: ProtectionConfig) -> list[ProtectionAction]:
        actions: list[ProtectionAction] = []
        with self._lock:
            if not old.armed and new.armed:
                _write_private_json(
                    self._armed_path, {"pins": new.pins(), "armed_at": self._now_iso()})
                actions.append(ProtectionAction(EV_ARMED, {"host": new.udr7_ssh_host,
                                                            "detail": "armado"}))
                self._note(EV_ARMED)
            elif old.armed and not new.armed:
                try:
                    os.unlink(self._armed_path)
                except FileNotFoundError:
                    pass                      # já não estava lá: desarmado é desarmado
                except OSError as exc:
                    # DESARMAR NUNCA FALHA (cerca S4l): o botão de parada é do dono.
                    # O arquivo órfão é inócuo — só é lido com a proteção ligada e
                    # é sobrescrito no próximo armamento.
                    log_json("WARN", "armed_file_unlink_failed",
                             path=self._armed_path, reason=str(exc)[:200])
                actions.append(ProtectionAction(EV_DISARMED, {"host": new.udr7_ssh_host,
                                                               "detail": "desarmado"}))
                self._note(EV_DISARMED)
            self._known_host_cache = None   # host/port may have changed
        return actions

    def status(self) -> dict:
        """Pure view for /v1/health (no spawn, no writes)."""
        pc = self._holder.get()
        with self._lock:
            bits = self._last_snapshot_bits
            # Antes do 1.º tick não há estado medido. O fallback tem de dizer a
            # verdade: uma instância LIGADA e sem ensaio está armada e ainda não
            # verificada — dizer "dry_run" aí seria afirmar ensaio para quem pode
            # desligar o aparelho de verdade.
            state = self._last_state or (
                "desabilitado" if not pc.protect_udr7
                else "dry_run" if pc.protect_dry_run
                else "armado_nao_verificado"
            )
            return {
                "state": state,
                # O nome que o usuário deu ao dispositivo. Vazio (PUT "") grava vazio
                # a quente; o fallback mora AQUI, num lugar só, e não no app.
                "name": pc.udr7_name or self._default_name,
                "dry_run": pc.protect_dry_run,
                "enabled": pc.protect_udr7,
                "source": _rotulo_da_fonte(
                    self._last_first_fail, self._last_source_detail,
                    self._last_first_fail is not None or bool(self._last_state)),
                "source_detail": self._last_source_detail,
                "missing_key": self._last_missing_key,
                "cutoff": pc.udr7_cutoff_percent,
                "threshold": pc.udr7_shutdown_percent,
                "charge_low": bits.get("charge_low"),
                "margin_estimate_s": self._margin_estimate(pc),
                "warnings": bits.get("warnings", self._warnings(pc, None)),
                "ssh_host": pc.udr7_ssh_host,
                "ssh_binary": pc.ssh_binary,
                "last_event": self._last_event,
                "last_event_at": self._last_event_at,
                "outage": self._outage,
                "attempts": self._attempts,
                "sent_pending_restore": bool(self._sent_pending_restore),
            }

    def drain_transition(self) -> tuple[str | None, str] | None:
        with self._lock:
            t, self._pending_transition = self._pending_transition, None
            return t
