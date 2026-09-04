"""Minimal NUT (upsd) client — read-only subset of the protocol.

Protocol reference: https://networkupstools.org/docs/developer-guide.chunked/ar01s09.html
(line-oriented over TCP 3493; `LIST VAR <ups>` / `GET VAR <ups> <name>`).
Stdlib only, blocking sockets with timeout; reconnection is the caller's job.
"""

from __future__ import annotations

import socket

from .protect import log_json   # linha de log em JSON (protect.py não importa nada nosso)


class NutError(Exception):
    """Protocol or transport error talking to upsd (house exit code 10)."""


def parse_list_var(lines: list[str], ups: str) -> dict[str, str]:
    """Parse the payload lines of a LIST VAR response into {var: value}."""
    out: dict[str, str] = {}
    prefix = f"VAR {ups} "
    for line in lines:
        if not line.startswith(prefix):
            continue
        rest = line[len(prefix):]
        name, _, raw = rest.partition(" ")
        out[name] = raw.strip().strip('"')
    return out


class NutClient:
    def __init__(self, host: str, port: int, timeout: float = 5.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self._sock: socket.socket | None = None
        self._file = None

    def connect(self) -> None:
        try:
            self._sock = socket.create_connection((self.host, self.port), self.timeout)
            self._sock.settimeout(self.timeout)
            self._file = self._sock.makefile("r", encoding="utf-8", newline="\n")
        except OSError as exc:
            raise NutError(f"conexão com upsd {self.host}:{self.port} falhou: {exc}") from exc

    def close(self) -> None:
        for closer in (self._file, self._sock):
            try:
                if closer is not None:
                    closer.close()
            except OSError as exc:
                # Fechar não pode falhar o ciclo, mas some sem registro ninguém
                # descobre um descritor vazando.
                log_json("WARN", "nut_close_failed", reason=str(exc)[:200])
        self._file = None
        self._sock = None

    def __enter__(self) -> "NutClient":
        self.connect()
        return self

    def __exit__(self, *_exc) -> None:
        self.close()

    def _send(self, command: str) -> None:
        if self._sock is None:
            raise NutError("cliente não conectado")
        try:
            self._sock.sendall((command + "\n").encode("utf-8"))
        except OSError as exc:
            raise NutError(f"envio falhou: {exc}") from exc

    def _readline(self) -> str:
        if self._file is None:
            raise NutError("cliente não conectado")
        try:
            line = self._file.readline()
        except OSError as exc:
            raise NutError(f"leitura falhou: {exc}") from exc
        if line == "":
            raise NutError("conexão encerrada pelo upsd")
        return line.rstrip("\n")

    def list_vars(self, ups: str) -> dict[str, str]:
        """`LIST VAR <ups>` -> {variable: value}. Raises NutError on ERR."""
        self._send(f"LIST VAR {ups}")
        lines: list[str] = []
        while True:
            line = self._readline()
            if line.startswith("ERR "):
                raise NutError(f"upsd respondeu: {line}")
            if line.startswith(f"BEGIN LIST VAR {ups}"):
                continue
            if line.startswith(f"END LIST VAR {ups}"):
                break
            lines.append(line)
        return parse_list_var(lines, ups)
