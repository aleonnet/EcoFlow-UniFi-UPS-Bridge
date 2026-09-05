"""E2E Fase 3'-EXP: full daemon (poll loop + API thread) with the protection policy.

Real subprocess, real TCP, real token file, real `ssh-keygen -F` — and a STUB in place
of `ssh` (`RUB_SSH_BINARY`), so nothing ever leaves this machine:
  (a) rehearsal against the simulator -> DRYRUN with would_block=fonte_nao_real;
  (b) arming against the simulator is refused (409 fonte_nao_real), stub never runs;
  (c) mirror case: an in-process upsd that LOOKS real (usbhid-ups, registered serial)
      -> arming succeeds, the outage fires the stub exactly once with the expected
      argv -> SENT; power back -> REARMED;
  (d) while armed: protection keys and restart are refused; disarm is accepted and
      removes armed.json.
Defence in depth even if the stub were ignored: UDR7_SSH_HOST=192.0.2.1 (TEST-NET-1,
RFC 5737, never routable) and the known_hosts entry is a fabricated key.
"""

import hashlib
import json
import os
import pathlib
import socket
import socketserver
import stat
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

import pytest

from conftest import ambiente_do_daemon

REPO = pathlib.Path(__file__).parents[2]
SIMULATOR = REPO / "tools" / "fake-nut-ups"
REAL_SERIAL = "R3P-TEST"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


# --- an upsd that looks real (NOT the shipped simulator, by design) --------------------
class RealLookingUpsd:
    """Publishes usbhid-ups/2.8.4 with a registered serial; phase switchable by the test."""

    def __init__(self, ups: str = "river-office") -> None:
        self.ups = ups
        self.phase = "OL"
        outer = self

        class Handler(socketserver.StreamRequestHandler):
            def handle(self) -> None:
                while True:
                    raw = self.rfile.readline()
                    if not raw:
                        return
                    parts = raw.decode("utf-8", "replace").split()
                    if not parts:
                        continue
                    cmd = parts[0].upper()
                    if cmd == "LOGOUT":
                        self.wfile.write(b"OK Goodbye\n"); return
                    if cmd in ("USERNAME", "PASSWORD"):
                        self.wfile.write(b"OK\n"); continue
                    if cmd == "LIST" and len(parts) >= 3 and parts[1].upper() == "VAR":
                        vars_ = outer.vars()
                        out = [f"BEGIN LIST VAR {outer.ups}"]
                        out += [f'VAR {outer.ups} {k} "{v}"' for k, v in vars_.items()]
                        out.append(f"END LIST VAR {outer.ups}")
                        self.wfile.write(("\n".join(out) + "\n").encode()); continue
                    self.wfile.write(b"ERR UNKNOWN-COMMAND\n")

        class Server(socketserver.ThreadingTCPServer):
            allow_reuse_address = True
            daemon_threads = True

        self.server = Server(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.1},
                                       daemon=True)

    def vars(self) -> dict[str, str]:
        base = {
            "device.mfr": "EcoFlow", "device.model": "RIVER 3 Plus", "device.serial": REAL_SERIAL,
            "driver.name": "usbhid-ups", "driver.version": "2.8.4", "battery.charge.low": "10",
            "ups.load": "12", "output.voltage": "230.0", "ups.realpower": "45",
        }
        if self.phase == "OL":
            return {**base, "ups.status": "OL CHRG", "battery.charge": "80", "battery.runtime": "3200"}
        return {**base, "ups.status": "OB DISCHRG", "battery.charge": "8", "battery.runtime": "320"}

    def start(self):
        self.thread.start(); return self

    def stop(self):
        self.server.shutdown(); self.server.server_close()


# --- stack ----------------------------------------------------------------------------
def write_stub(tmp_path: pathlib.Path, log_path: pathlib.Path) -> pathlib.Path:
    stub = tmp_path / "ssh-stub"
    stub.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "assert os.path.realpath(sys.argv[0]) == os.path.realpath(__file__), sys.argv[0]\n"
        f"with open({str(log_path)!r}, 'a', encoding='utf-8') as fh:\n"
        "    fh.write(json.dumps(sys.argv) + '\\n')\n"
        "sys.exit(0)\n"
    )
    stub.chmod(0o755)
    return stub


def seed_known_hosts(tmp_path: pathlib.Path, state_dir: pathlib.Path) -> None:
    subprocess.run(["/usr/bin/ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                    "-f", str(tmp_path / "hostkey")], check=True)
    pub = (tmp_path / "hostkey.pub").read_text().strip()
    state_dir.mkdir(mode=0o700, exist_ok=True)
    kh = state_dir / "udr7_known_hosts"
    kh.write_text(f"192.0.2.1 {pub}\n")
    kh.chmod(0o600)


def seed_alcance(state_dir: pathlib.Path, instance_id: str = "udr7") -> None:
    """A prova de alcance que a tela grava ao passar em "Testar conexão".

    Desde a 0.6.0 armar exige que o serviço TENHA falado com o console — sem
    isso, o primeiro contato real seria o desligamento, numa queda de energia.
    Aqui ela é semeada como um usuário faria; quem exercita a ausência é a cerca.
    """
    arquivo = state_dir / f"{instance_id}_acesso.json"
    arquivo.write_text(json.dumps({"verificado_em": time.time(),
                                   "modelo": "UniFi Dream Router 7",
                                   "firmware": "5.1.31"}))
    arquivo.chmod(0o600)


def base_env(tmp_path, nut_port, api_port, *, expected_serial, dry_run="1", arm_allowed="1") -> str:
    key = tmp_path / "river-bridge-udr7"
    key.write_text("PRIVATE KEY (fake, never used: the ssh binary is a stub)\n")
    key.chmod(0o600)
    return (
        "RIVER_NAME=river-office\nNUT_HOST=127.0.0.1\n"
        f"NUT_PORT={nut_port}\nNUT_UPS=river-office\n"
        f"UI_API_PORT={api_port}\nPOLL_INTERVAL_SECONDS=1\nPOWER_LOSS_DELAY_SECONDS=1\n"
        "PROTECT_UDR7=1\n"
        f"PROTECT_DRY_RUN={dry_run}\nUDR7_ARM_ALLOWED={arm_allowed}\n"
        "UDR7_SSH_HOST=192.0.2.1\nUDR7_SSH_PORT=22\nUDR7_SSH_USER=root\n"
        f"UDR7_SSH_KEY={key}\nUDR7_EXPECTED_SERIAL={expected_serial}\n"
        "UDR7_CUTOFF_PERCENT=10\nUDR7_SHUTDOWN_PERCENT=20\n"
        "UDR7_MIN_OUTAGE_SECONDS=0\nUDR7_CONFIRM_SECONDS=0\n"
    )


def start_daemon(tmp_path, env_text, api_port, stub, stub_log):
    state_dir = tmp_path / "state"
    seed_known_hosts(tmp_path, state_dir)
    seed_alcance(state_dir)
    env_file = tmp_path / "bridge.env"
    env_file.write_text(env_text, encoding="utf-8")
    env_file.chmod(0o600)
    daemon = subprocess.Popen(
        [sys.executable, "-m", "river_unifi_bridge.service", "--env", str(env_file)],
        cwd=str(REPO),
        env=ambiente_do_daemon(tmp_path, RUB_STATE_DIR=str(state_dir),
                               RUB_SSH_BINARY=str(stub), RUB_STUB_LOG=str(stub_log)),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", api_port), 0.2).close(); break
        except OSError:
            time.sleep(0.1)
    else:
        daemon.kill()
        pytest.fail("API não abriu a porta em 10 s")
    token = (state_dir / "ui-api.token").read_text().strip()
    return daemon, token, state_dir, env_file


class Api:
    def __init__(self, port, token):
        self.port, self.token = port, token

    def _req(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}", data=data, method=method,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else None)   # 204: sem corpo
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def get(self, path):
        return self._req("GET", path)

    def put(self, body):
        return self._req("PUT", "/v1/config", body)

    def post(self, path, body=None):
        return self._req("POST", path, body)

    def put_path(self, path, body):
        return self._req("PUT", path, body)

    def delete(self, path):
        return self._req("DELETE", path)

    def wait(self, predicate, timeout=15, path="/v1/health"):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            _, last = self.get(path)
            if predicate(last):
                return last
            time.sleep(0.3)
        pytest.fail(f"condição não atingida em {timeout}s; último: {json.dumps(last)[:400]}")

    def event_types(self):
        _, body = self.get("/v1/events/log?limit=200")
        return [r["type"] for r in body["rows"]]


def stop(*procs):
    for p in procs:
        try:
            p.terminate(); p.wait(timeout=5)
        except Exception:
            p.kill()


# --- (a) + (b): the shipped simulator can never arm or fire ---------------------------
def test_e2e_simulator_dryrun_and_arming_refused(tmp_path):
    nut_port, api_port = free_port(), free_port()
    stub_log = tmp_path / "stub.log"
    stub = write_stub(tmp_path, stub_log)
    sim = subprocess.Popen([sys.executable, str(SIMULATOR), "--port", str(nut_port),
                            "--scenario", "low-battery"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        daemon, token, state_dir, env_file = start_daemon(
            tmp_path, base_env(tmp_path, nut_port, api_port, expected_serial="NAO-E-O-SIM"),
            api_port, stub, stub_log)
        try:
            api = Api(api_port, token)
            # Migração no 1.º boot (2026-09-03): a loja nasce 0600 com a instância udr7,
            # e o boot NÃO reescreve o .env nem os arquivos de estado udr7_* (hashes).
            env_sha = hashlib.sha256(env_file.read_bytes()).hexdigest()
            kh_sha = hashlib.sha256((state_dir / "udr7_known_hosts").read_bytes()).hexdigest()
            # (a) rehearsal: exactly one DRYRUN per outage, blocked by the source gate
            health = api.wait(lambda h: h["udr7_detail"] and h["udr7_detail"]["last_event"] == "UDR7_SHUTDOWN_DRYRUN")
            store = json.loads((state_dir / "devices.json").read_text())
            assert [d["id"] for d in store["devices"]] == ["udr7"]
            assert store["devices"][0]["fields"]["ssh_host"] == "192.0.2.1"
            assert stat.S_IMODE(os.stat(state_dir / "devices.json").st_mode) == 0o600
            assert hashlib.sha256(env_file.read_bytes()).hexdigest() == env_sha
            assert hashlib.sha256((state_dir / "udr7_known_hosts").read_bytes()).hexdigest() == kh_sha
            assert health["plugins"][0]["type"] == "udr7_ssh"
            assert health["udr7"] == "fonte_nao_real"
            d = health["udr7_detail"]
            assert d["dry_run"] is True and d["source"] == "sintetica"
            assert d["source_detail"] == "telemetria_sintetica"
            assert d["ssh_binary"] == str(stub)
            time.sleep(2.5)
            types = api.event_types()
            assert types.count("UDR7_SHUTDOWN_DRYRUN") == 1
            _, log = api.get("/v1/events/log?types=UDR7_SHUTDOWN_DRYRUN")
            assert log["rows"][0]["detail"] == "fonte_nao_real"
            assert health["unifi"] == "sem_caminho_nativo_documentado"
            # (b) arming against the simulator is refused; nothing written, stub never ran
            status, body = api.put({"PROTECT_DRY_RUN": "0"})
            assert status == 409 and body["motivo"] == "fonte_nao_real"
            assert "PROTECT_DRY_RUN=1" in env_file.read_text()
            assert not (state_dir / "udr7_armed.json").exists()
            assert not stub_log.exists()
            status, body = api.put({"UDR7_ARM_ALLOWED": "0"})
            assert status == 400 and body["motivo"] == "chave_somente_arquivo"
        finally:
            stop(daemon)
    finally:
        stop(sim)


# --- (c) + (d): the mirror case fires the stub exactly once ---------------------------
def test_e2e_real_looking_source_arms_fires_stub_once_and_disarms(tmp_path):
    upsd = RealLookingUpsd().start()
    api_port = free_port()
    stub_log = tmp_path / "stub.log"
    stub = write_stub(tmp_path, stub_log)
    try:
        daemon, token, state_dir, env_file = start_daemon(
            tmp_path, base_env(tmp_path, upsd.port, api_port, expected_serial=REAL_SERIAL),
            api_port, stub, stub_log)
        try:
            api = Api(api_port, token)
            health = api.wait(lambda h: h["has_snapshot"] and h["nut"] == "ok" and h["udr7_detail"])
            # Fence before arming: the binary the daemon would run IS the stub. Abort otherwise.
            assert health["udr7_detail"]["ssh_binary"] == str(stub), "recusando armar: ssh não é o stub"
            assert health["udr7"] == "dry_run"
            # (c) arm through the real PUT flow
            status, body = api.put({"PROTECT_DRY_RUN": "0"})
            assert status == 200, body
            armed = json.loads((state_dir / "udr7_armed.json").read_text())
            assert armed["pins"]["ssh_binary"] == str(stub)
            assert armed["pins"]["udr7_expected_serial"] == REAL_SERIAL
            assert stat.S_IMODE(os.stat(state_dir / "udr7_armed.json").st_mode) == 0o600
            api.wait(lambda h: h["udr7"] == "armado_nao_verificado")
            assert "UDR7_ARMED" in api.event_types()
            # outage -> exactly one stub invocation with the isolated argv
            upsd.phase = "OB"
            api.wait(lambda h: h["udr7_detail"]["last_event"] == "UDR7_SHUTDOWN_SENT", timeout=20)
            time.sleep(2.5)
            calls = [json.loads(l) for l in stub_log.read_text().splitlines()]
            assert len(calls) == 1, calls
            argv = calls[0]
            assert argv[-1] == "ubnt-systool poweroff" and argv[-2] == "root@192.0.2.1" and argv[-3] == "--"
            assert "StrictHostKeyChecking=yes" in argv and "ProxyCommand=none" in argv
            assert f'UserKnownHostsFile="{state_dir / "udr7_known_hosts"}"' in argv
            assert api.event_types().count("UDR7_SHUTDOWN_SENT") == 1
            assert api.get("/v1/health")[1]["udr7"] == "enviado"
            # (d) while armed: frozen keys and restart are refused
            status, body = api.put({"UDR7_SSH_HOST": "192.0.2.9"})
            assert status == 409 and body["motivo"] == "armado"
            status, body = api.post("/v1/service/restart")
            assert status == 409 and body["motivo"] == "armado"
            # power back -> REARMED; a second SENT would need a new confirmed outage
            upsd.phase = "OL"
            api.wait(lambda h: h["udr7_detail"]["last_event"] == "UDR7_PROTECTION_REARMED", timeout=20)
            assert json.loads((state_dir / "udr7_runtime.json").read_text())["sent_pending_restore"] is False
            # disarm is always accepted, removes armed.json, emits DISARMED
            status, body = api.put({"PROTECT_DRY_RUN": "1"})
            assert status == 200, body
            assert not (state_dir / "udr7_armed.json").exists()
            assert "UDR7_DISARMED" in api.event_types()
            assert "PROTECT_DRY_RUN=1" in env_file.read_text()
            assert len(stub_log.read_text().splitlines()) == 1
            status, _ = api.post("/v1/service/restart")
            assert status == 202
        finally:
            stop(daemon)
    finally:
        upsd.stop()


# --- (e) instâncias (2026-09-03): um host SSH criado pela API arma e dispara o stub ------
def test_e2e_ssh_host_instance_arms_and_fires_stub_once(tmp_path):
    """Duas instâncias na mesma queda: o UDR7 em ENSAIO (DRYRUN, nada sai) e um host
    SSH ARMADO pela API (o stub roda UMA vez, com o argv desse host e o known_hosts
    dessa instância). Depois: remover armado é recusado; desarmar e remover, aceito."""
    upsd = RealLookingUpsd().start()
    api_port = free_port()
    stub_log = tmp_path / "stub.log"
    stub = write_stub(tmp_path, stub_log)
    try:
        daemon, token, state_dir, env_file = start_daemon(
            tmp_path, base_env(tmp_path, upsd.port, api_port, expected_serial=REAL_SERIAL),
            api_port, stub, stub_log)
        try:
            api = Api(api_port, token)
            api.wait(lambda h: h["has_snapshot"] and h["nut"] == "ok" and h["udr7"] == "dry_run")
            key = tmp_path / "river-bridge-udr7"        # chave falsa: o ssh é o stub
            status, body = api.post("/v1/devices", {
                "type": "ssh_host", "name": "NAS da sala",
                "fields": {"ssh_host": "192.0.2.5", "ssh_user": "admin", "ssh_key": str(key),
                           "shutdown_percent": 20, "min_outage_seconds": 0, "confirm_seconds": 0,
                           "shutdown_command": "shutdown -h now"}})
            assert status == 201, body
            dev = body["device"]["id"]
            # known_hosts DESTA instância, com a mesma chave fabricada da bancada
            pub = (tmp_path / "hostkey.pub").read_text().strip()
            kh = state_dir / f"{dev}_known_hosts"
            kh.write_text(f"192.0.2.5 {pub}\n"); kh.chmod(0o600)
            seed_alcance(state_dir, dev)          # a prova que a tela grava
            health = api.wait(lambda h: len(h["plugins"]) == 2)
            assert health["plugins"][1]["type"] == "ssh_host"
            assert health["plugins"][1]["detail"]["ssh_binary"] == str(stub), "recusando armar: ssh não é o stub"
            # arma pela API de instâncias: trava aberta (.env), fonte real, serial do núcleo
            status, body = api.put_path(f"/v1/devices/{dev}", {"enabled": True, "dry_run": False})
            assert status == 200, body
            armed = json.loads((state_dir / f"{dev}_armed.json").read_text())
            assert armed["pins"]["shutdown_command"] == "shutdown -h now"
            assert armed["pins"]["udr7_expected_serial"] == REAL_SERIAL
            api.wait(lambda h: h["plugins"][1]["state"] == "armado_nao_verificado")
            assert "SSH_HOST_ARMED" in api.event_types()
            # a queda: o UDR7 ensaia, o host dispara — o stub roda UMA vez, com o argv do host
            upsd.phase = "OB"
            api.wait(lambda h: h["plugins"][1]["detail"]["last_event"] == "SSH_HOST_SHUTDOWN_SENT", timeout=20)
            api.wait(lambda h: h["udr7_detail"]["last_event"] == "UDR7_SHUTDOWN_DRYRUN", timeout=20)
            time.sleep(2.5)
            calls = [json.loads(l) for l in stub_log.read_text().splitlines()]
            assert len(calls) == 1, calls
            argv = calls[0]
            assert argv[-1] == "shutdown -h now" and argv[-2] == "admin@192.0.2.5" and argv[-3] == "--"
            assert f'UserKnownHostsFile="{kh}"' in argv
            # o histórico sabe de quem é cada evento
            _, log = api.get(f"/v1/events/log?device={dev}")
            assert [r["type"] for r in log["rows"]][:1] == ["SSH_HOST_SHUTDOWN_SENT"]
            assert all(r["device"] == dev for r in log["rows"])
            _, log = api.get("/v1/events/log?device=udr7")
            assert "UDR7_SHUTDOWN_DRYRUN" in [r["type"] for r in log["rows"]]
            # armado: remover é recusado; desarmar e então remover, aceito
            status, body = api.delete(f"/v1/devices/{dev}")
            assert status == 409 and body["motivo"] == "armado"
            upsd.phase = "OL"
            api.wait(lambda h: h["plugins"][1]["detail"]["last_event"] == "SSH_HOST_PROTECTION_REARMED", timeout=20)
            status, body = api.put_path(f"/v1/devices/{dev}", {"dry_run": True})
            assert status == 200 and body["device"]["armed"] is False
            assert not (state_dir / f"{dev}_armed.json").exists()
            status, _ = api.delete(f"/v1/devices/{dev}")
            assert status == 204
            assert kh.exists()                                   # semeado pelo dono: fica
            health = api.wait(lambda h: len(h["plugins"]) == 1)
            assert health["udr7"] == "dry_run"
            store = json.loads((state_dir / "devices.json").read_text())
            assert [d["id"] for d in store["devices"]] == ["udr7"]
            assert len(stub_log.read_text().splitlines()) == 1
        finally:
            stop(daemon)
    finally:
        upsd.stop()
