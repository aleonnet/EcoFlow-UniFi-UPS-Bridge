"""Line-preserving .env editor (§7A.5).

House rule: the owner's comments and numbered blocks are preserved — edits
happen line by line, and an unexpected line aborts instead of guessing.
Atomic write: mkstemp in the SAME directory (os.replace is only atomic
intra-volume), fsync, then replace; previous version kept as .bak.
"""

from __future__ import annotations

import os
import shutil
import tempfile

from .protect import log_json   # linha de log em JSON (protect.py não importa nada nosso)


class EnvFileError(Exception):
    pass


def update_env_file(path: str, changes: dict[str, str]) -> None:
    """Apply KEY=value changes to `path`, preserving structure and comments."""
    if not os.path.isfile(path):
        raise EnvFileError(f"arquivo não encontrado: {path}")

    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    pending = dict(changes)
    out: list[str] = []
    for lineno, raw in enumerate(lines, start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            out.append(raw)
            continue
        if "=" not in stripped:
            raise EnvFileError(f"{path}:{lineno}: linha inesperada — abortando sem adivinhar")
        key = stripped.partition("=")[0].strip()
        if key in pending:
            out.append(f"{key}={pending.pop(key)}\n")
        else:
            out.append(raw)

    for key, value in pending.items():
        # Key not present in the file: append explicitly at the end.
        out.append(f"{key}={value}\n")

    directory = os.path.dirname(os.path.abspath(path))
    original_mode = os.stat(path).st_mode & 0o777
    shutil.copy2(path, path + ".bak")

    fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".env-tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            tmp.writelines(out)
            tmp.flush()
            os.fsync(tmp.fileno())
        os.chmod(tmp_path, original_mode)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError as exc:
            # O erro original é o que importa e será relançado; o temporário
            # órfão fica registrado para quem for limpar o diretório.
            log_json("WARN", "env_tmp_unlink_failed", path=tmp_path, reason=str(exc)[:200])
        raise
