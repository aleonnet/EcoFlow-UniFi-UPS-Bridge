"""Bearer token for the loopback API (§7A.3).

File 0600 instead of Keychain — registered exception to spec §15 (the daemon
runs headless under launchd where the Keychain may be locked; the token is
local, loopback-only and regenerated at will).

State directory override via RUB_STATE_DIR keeps tests hermetic.
"""

from __future__ import annotations

import os
import secrets

TOKEN_FILENAME = "ui-api.token"


def state_dir() -> str:
    override = os.environ.get("RUB_STATE_DIR")
    if override:
        return override
    return os.path.expanduser("~/Library/Application Support/river-unifi-bridge")


def get_or_create_token(directory: str | None = None) -> str:
    directory = directory or state_dir()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    path = os.path.join(directory, TOKEN_FILENAME)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            token = fh.read().strip()
        if token:
            return token
    token = secrets.token_urlsafe(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token + "\n")
    return token
