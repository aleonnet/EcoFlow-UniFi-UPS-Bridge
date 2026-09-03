"""Local HTTP + SSE API for the native UI (§7A.3).

Serves ONLY on 127.0.0.1 (hard fence — non-loopback bind is refused), bearer
token from a 0600 file, no TLS/rate limiting (registered §15 exceptions).
Runs inside a daemon thread with its own asyncio loop; the sync poll loop
shares data through SharedState (thread-safe).

Restart contract (§7A.3): POST /v1/service/restart answers 202, the response
is drained, and the exit callback fires ~0.5 s later OUTSIDE the handler —
never exit inside a handler (the client would see a reset instead of the 202).
"""

from __future__ import annotations

import asyncio
import json
import threading

from aiohttp import web

from . import __version__
from .config import (
    BridgeConfig,
    ConfigError,
    FILE_ONLY_KEYS,
    HOT_RELOAD_KEYS,
    config_field_names,
    validate_update,
)
from .envfile import update_env_file
from .history import METRICS, HistoryStore
from .localtoken import get_or_create_token
from .plugins import plugin_statuses
from .protect import _emit
from .state import SharedState

# Fence: the API is loopback-only by design (§7A.3). Tests + gate mutation
# scene assert on this constant — do not parametrize it away.
BIND_HOST = "127.0.0.1"

RESTART_EXIT_DELAY_SECONDS = 0.5


def ensure_loopback(host: str) -> None:
    if host != "127.0.0.1":
        raise ConfigError(f"bind não-loopback recusado: {host} (API é local por desenho)")


def _empty_state(name: str, comm_ok: bool, last_error: str | None) -> dict:
    """Honest §7.3 shape when no snapshot exists yet: nulls, never invention."""
    return {
        "identity": {"name": name, "manufacturer": None, "model": None, "serial": None},
        "power": {
            "state": "UNKNOWN", "states": [], "input_present": None,
            "input_voltage_v": None, "output_voltage_v": None,
            "output_power_w": None, "load_percent": None,
        },
        "battery": {
            "charge_percent": None, "charge_low_percent": None,
            "runtime_seconds": None, "voltage_v": None, "temperature_c": None,
        },
        "health": {
            "communication_ok": comm_ok, "low_battery": False, "overload": False,
            "alarm": [], "unknown_status_tokens": [],
            "last_error": last_error,
        },
        "source": {
            "nut": True, "usb_hid": True, "usb_cdc": False,
            "driver_name": None, "driver_version": None,
        },
        "timestamp": None,
    }


def _authorize(changes: dict, plugins: list, snapshot: dict | None,
               comm_ok: bool) -> tuple[int, str, str] | None:
    """Runs BEFORE anything is written, so a 4xx never leaves a trace no .env.

    The file-only rule is GENERIC and stays here: it has to answer the same way
    with no plugins at all. Everything else belongs to a device, and the FIRST
    plugin to refuse wins.
    """
    file_only = sorted(set(changes) & FILE_ONLY_KEYS)
    if file_only:
        return 400, "chave_somente_arquivo", (
            f"{file_only[0]}: somente no arquivo de configuração do serviço (trava de armamento)")
    for plugin in plugins:
        refusal = plugin.authorize(changes, snapshot, comm_ok)
        if refusal is not None:
            return refusal
    return None


class ApiServer:
    def __init__(
        self,
        cfg: BridgeConfig,
        state: SharedState,
        history: HistoryStore,
        env_path: str,
        restart_cb,
        token: str | None = None,
        plugins: list | None = None,
    ) -> None:
        ensure_loopback(BIND_HOST)
        self.cfg = cfg
        self.state = state
        self.history = history
        self.env_path = env_path
        self.restart_cb = restart_cb
        # list(...) e não o objeto cru: uma fixture sem plugins itera uma lista
        # vazia em vez de precisar de guardas `is None` em cada ponto.
        self.plugins = list(plugins or [])
        self.token = token if token is not None else get_or_create_token()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._started = threading.Event()
        self.port: int | None = None

    # -- app ---------------------------------------------------------------

    def build_app(self) -> web.Application:
        @web.middleware
        async def auth(request: web.Request, handler):
            header = request.headers.get("Authorization", "")
            if header != f"Bearer {self.token}":
                return web.json_response({"erro": "token ausente ou inválido"}, status=401)
            return await handler(request)

        app = web.Application(middlewares=[auth])
        app.router.add_get("/v1/state", self._h_state)
        app.router.add_get("/v1/events", self._h_events)
        app.router.add_get("/v1/events/log", self._h_events_log)
        app.router.add_delete("/v1/events/log", self._h_events_delete)
        app.router.add_get("/v1/history", self._h_history)
        app.router.add_get("/v1/health", self._h_health)
        app.router.add_get("/v1/config", self._h_config_get)
        app.router.add_put("/v1/config", self._h_config_put)
        app.router.add_post("/v1/service/restart", self._h_restart)
        app.router.add_get("/v1/version", self._h_version)
        return app

    # -- handlers ----------------------------------------------------------

    async def _h_state(self, _req: web.Request) -> web.Response:
        _version, snapshot, comm_ok, last_error = self.state.get()
        if snapshot is None:
            return web.json_response(_empty_state(self.cfg.river_name, comm_ok, last_error))
        return web.json_response(snapshot)

    async def _h_events(self, request: web.Request) -> web.StreamResponse:
        resp = web.StreamResponse(
            headers={
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        await resp.prepare(request)
        last_version = -1
        sent_events = 0
        try:
            while True:
                version, snapshot, comm_ok, last_error = self.state.get()
                if version != last_version:
                    last_version = version
                    payload = snapshot or _empty_state(
                        self.cfg.river_name, comm_ok, last_error
                    )
                    await resp.write(
                        f"event: state\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n".encode()
                    )
                    events = self.state.events()
                    for event in events[sent_events:]:
                        await resp.write(
                            f"event: event\ndata: {json.dumps(event, ensure_ascii=False)}\n\n".encode()
                        )
                    sent_events = len(events)
                await asyncio.sleep(0.25)
        except (ConnectionResetError, asyncio.CancelledError):
            return resp

    async def _h_events_log(self, request: web.Request) -> web.Response:
        q = request.query
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q.get("to", str(2**33)))
            limit = int(q.get("limit", "200"))
            types = [t for t in q.get("types", "").split(",") if t] or None
            device = q.get("device") or None
            rows = self.history.query_events(ts_from, ts_to, types, limit, device=device)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response({"rows": rows})

    async def _h_events_delete(self, request: web.Request) -> web.Response:
        # `to` is mandatory by design: an accidental parameterless DELETE must
        # never wipe the log. "Tudo" is the UI sending to=now explicitly.
        q = request.query
        if "to" not in q:
            return web.json_response(
                {"erro": "parâmetro to é obrigatório (limite superior da faixa)"},
                status=400,
            )
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q["to"])
            removed = self.history.delete_events(ts_from, ts_to)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response({"removidos": removed})

    async def _h_history(self, request: web.Request) -> web.Response:
        q = request.query
        metric = q.get("metric", "charge")
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q.get("to", str(2**33)))
            bucket = int(q.get("bucket", "60"))
            rows = self.history.query(metric, ts_from, ts_to, bucket)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response(
            {"metric": metric, "bucket_seconds": bucket, "rows": rows,
             "events": self.history.recent_events()}
        )

    async def _h_health(self, _req: web.Request) -> web.Response:
        return web.json_response(self.state.health())

    async def _h_config_get(self, _req: web.Request) -> web.Response:
        cfg = {name: getattr(self.cfg, name) for name in config_field_names()}
        return web.json_response({"config": cfg})

    async def _h_config_put(self, request: web.Request) -> web.Response:
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"erro": "corpo não é JSON"}, status=400)
        if not isinstance(body, dict) or not body:
            return web.json_response({"erro": "esperado objeto {CHAVE: valor}"}, status=400)

        parsed: dict[str, object] = {}
        for key, raw in body.items():
            try:
                parsed[key] = validate_update(str(key), str(raw))
            except ConfigError as exc:
                return web.json_response({"erro": str(exc)}, status=400)

        # Order is a fence: validate -> authorize -> write -> apply. A refusal never
        # leaves a trace in the .env file.
        _version, snapshot, comm_ok, _err = self.state.get()
        refusal = _authorize(parsed, self.plugins, snapshot, comm_ok)
        if refusal is not None:
            status, motivo, mensagem = refusal
            return web.json_response({"erro": mensagem, "motivo": motivo}, status=status)

        update_env_file(self.env_path, {k: str(v) if not isinstance(v, bool) else ("1" if v else "0") for k, v in parsed.items()})

        applied_hot: list[str] = []
        restart_required = False
        for key, value in parsed.items():
            if key in HOT_RELOAD_KEYS:
                setattr(self.cfg, key.lower(), value)   # outside any lock (never read by the policy)
                applied_hot.append(key)
            else:
                restart_required = True
        for plugin in self.plugins:
            _emit(plugin.on_config_applied(self.cfg), self.state, self.history)
        # O health é atualizado no fim do PUT: sem isto a tela mostraria o estado
        # anterior até o próximo tick do laço (≤ POLL_INTERVAL_SECONDS).
        self.state.set_plugins(plugin_statuses(self.plugins))
        return web.json_response(
            {"aplicadas_a_quente": applied_hot, "restart_required": restart_required}
        )

    async def _h_restart(self, _req: web.Request) -> web.Response:
        if any(plugin.armed for plugin in self.plugins):
            return web.json_response(
                {"erro": "proteção armada: desligue a proteção antes de reiniciar; ou reinicie "
                         "pelo terminal (sudo launchctl kickstart -k system/com.river.unifi-bridge)",
                 "motivo": "armado"},
                status=409,
            )
        # 202 first; the callback fires outside the handler after the response
        # has been flushed (see module docstring for the race this avoids).
        assert self._loop is not None
        self._loop.call_later(RESTART_EXIT_DELAY_SECONDS, self.restart_cb)
        return web.json_response({"status": "reinício agendado"}, status=202)

    async def _h_version(self, _req: web.Request) -> web.Response:
        return web.json_response({"version": __version__})

    # -- lifecycle ---------------------------------------------------------

    def start_in_thread(self) -> None:
        def runner() -> None:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            self._loop = loop

            async def serve() -> None:
                app_runner = web.AppRunner(self.build_app())
                await app_runner.setup()
                site = web.TCPSite(app_runner, BIND_HOST, self.cfg.ui_api_port)
                await site.start()
                self.port = self.cfg.ui_api_port
                self._started.set()

            loop.run_until_complete(serve())
            loop.run_forever()

        self._thread = threading.Thread(target=runner, name="ui-api", daemon=True)
        self._thread.start()
        if not self._started.wait(timeout=10):
            raise RuntimeError("API local não subiu em 10 s")

    def stop(self) -> None:
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._loop.stop)
