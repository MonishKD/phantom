#!/usr/bin/env python3
"""Phantom device helper: the bridge between Phantom.app and pymobiledevice3.

Protocol (newline-delimited JSON):
  stdin   {"id": 1, "cmd": "set", "udid": "...", "lat": 48.8584, "lon": 2.2945}
  stdout  {"id": 1, "ok": true}  |  {"id": 1, "ok": false, "error": {"code": "...", "message": "..."}}
          {"event": "devices", "devices": [...]}  |  {"event": "status", "status": {...}}
  stderr  human-readable logging

Commands: hello, list, set, clear, pair, shutdown.

How a location reaches the device:
  iOS 17+   CoreDevice, over an RSD tunnel: the com.apple.coredevice.feature.simulatelocation
            feature's setsimulatedlocation / clearsimulatedlocation actions. Set and clear must
            both go through CoreDevice; the DVT instruments service tracks a separate location
            that CoreDevice's clear doesn't release.
  iOS <17   com.apple.dt.simulatelocation over lockdown, once the developer disk image is mounted.
Apps then receive it through CoreLocation, flagged as simulated
(CLLocationSourceInformation.isSimulatedBySoftware). `simctl location` is the Simulator's
equivalent and doesn't reach physical devices.

Each device gets a Session that keeps its connection, re-sends the location periodically, and
reconnects when the cable or tunnel drops.
"""

from __future__ import annotations

import asyncio
import importlib.metadata
import json
import logging
import math
import os
import struct
import sys
import threading
from contextlib import suppress
from typing import Any, Optional

# The protocol owns the real stdout. Point fd 1 at stderr so nothing a library prints can corrupt it.
_protocol_fd = os.dup(1)
os.dup2(2, 1)
_protocol_out = os.fdopen(_protocol_fd, "w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr
_emit_lock = threading.Lock()

logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(levelname)s %(name)s: %(message)s")
logging.getLogger("asyncio").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)
logger = logging.getLogger("phantom")


def emit(message: dict[str, Any]) -> None:
    line = json.dumps(message, separators=(",", ":"), default=str)
    with _emit_lock:
        _protocol_out.write(line + "\n")
        _protocol_out.flush()


try:
    from packaging.version import Version
    from pymobiledevice3 import usbmux
    from pymobiledevice3.exceptions import (
        AlreadyMountedError,
        ConnectionFailedError,
        ConnectionTerminatedError,
        DeveloperDiskImageNotFoundError,
        DeveloperModeIsNotEnabledError,
        DeviceHasPasscodeSetError,
        DeviceNotFoundError,
        FatalPairingError,
        InvalidHostIDError,
        MissingManifestError,
        NoDeviceConnectedError,
        NoSuchBuildIdentityError,
        NotPairedError,
        PairingDialogResponsePendingError,
        PairingError,
        PasscodeRequiredError,
        PasswordRequiredError,
        PyMobileDevice3Exception,
        StartServiceError,
        TunneldConnectionError,
        UserDeniedPairingError,
        UserspaceTunnelUnavailableError,
    )
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.remote.core_device.location_service import LocationService
    from pymobiledevice3.services.amfi import AmfiService
    from pymobiledevice3.services.mobile_image_mounter import auto_mount, fetch_personalized_ddi
    from pymobiledevice3.tunneld.api import get_tunneld_device_by_udid
except ImportError as import_error:
    emit({
        "event": "fatal",
        "error": {"code": "MISSING_DEPENDENCY", "message": f"pymobiledevice3 isn't installed ({import_error})."},
    })
    sys.exit(3)

PAIR_TIMEOUT = 45  # seconds to wait for "Trust This Computer?"
KEEPALIVE_INTERVAL = 15
DEVICE_POLL_INTERVAL = 2
DETAIL_REFRESH_INTERVAL = 8  # re-read unpaired / Developer Mode-off devices so the UI notices changes
DEVICE_CALL_TIMEOUT = 20
TUNNEL_TIMEOUT = 45

# CoreDevice's location feature, used for both set and clear on iOS/iPadOS 17+. The older DVT
# instruments service can also set a location, but the two track separate state: a DVT-set location
# is not the one CoreDevice clears, so mixing them leaves a fix that nothing can turn off.
SIMULATE_LOCATION_FEATURE = "com.apple.coredevice.feature.simulatelocation"
SET_SIMULATED_LOCATION_ACTION = "com.apple.coredevice.action.setsimulatedlocation"
CLEAR_SIMULATED_LOCATION_ACTION = "com.apple.coredevice.action.clearsimulatedlocation"


class HelperError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class LegacyLocationSimulation:
    """``com.apple.dt.simulatelocation`` for iOS 16 and earlier, reached over lockdown.

    Implemented here rather than with pymobiledevice3's ``DtSimulateLocation``, which never closes
    the connection it opens for each command and formats coordinates with ``str()``, so a value
    like 0.00001 goes out as "1e-05". The device keeps the location after the connection closes.
    """

    SERVICE_NAME = "com.apple.dt.simulatelocation"
    START, STOP = 0, 1

    def __init__(self, lockdown: Any) -> None:
        self.lockdown = lockdown

    @staticmethod
    def encode_set(latitude: float, longitude: float) -> bytes:
        """START, then each coordinate as length-prefixed fixed-point text (big-endian lengths)."""
        payload = struct.pack(">I", LegacyLocationSimulation.START)
        for value in (latitude, longitude):
            text = f"{value:.7f}".encode()
            payload += struct.pack(">I", len(text)) + text
        return payload

    async def set(self, latitude: float, longitude: float) -> None:
        await self._send(self.encode_set(latitude, longitude))

    async def clear(self) -> None:
        await self._send(struct.pack(">I", self.STOP))

    async def _send(self, payload: bytes) -> None:
        service = await self.lockdown.start_lockdown_developer_service(self.SERVICE_NAME)
        try:
            await service.sendall(payload)  # drains before returning
        finally:
            await service.close()


def classify(exc: BaseException, noun: str = "device") -> tuple[str, str]:
    """Maps an exception to an (error code, user-facing message) pair understood by the app.

    ``noun`` names the device in the message ("iPhone", "iPad", or a neutral fallback).
    """
    if isinstance(exc, HelperError):
        return exc.code, exc.message
    if isinstance(exc, (NoDeviceConnectedError, DeviceNotFoundError)):
        return "NO_DEVICE", f"The {noun} isn't connected to this Mac."
    if isinstance(exc, PasswordRequiredError):
        return "LOCKED", f"The {noun} must be unlocked to pair with this Mac."
    if isinstance(exc, UserDeniedPairingError):
        return "PAIRING", f"“Trust This Computer” was declined on the {noun}."
    if isinstance(exc, PairingDialogResponsePendingError):
        return "PAIRING", f"Timed out waiting for you to tap Trust on the {noun}."
    if isinstance(exc, (NotPairedError, PairingError, FatalPairingError, InvalidHostIDError)):
        return "PAIRING", f"This Mac isn't trusted by the {noun} yet."
    if isinstance(exc, PasscodeRequiredError):
        return "LOCKED", f"The {noun} is locked."
    if isinstance(exc, DeviceHasPasscodeSetError):
        return "DEVELOPER_MODE", f"Developer Mode has to be switched on manually on a {noun} with a passcode."
    if isinstance(exc, DeveloperModeIsNotEnabledError):
        return "DEVELOPER_MODE", f"Developer Mode is turned off on the {noun}."
    if isinstance(exc, (DeveloperDiskImageNotFoundError, MissingManifestError, NoSuchBuildIdentityError, StartServiceError)):
        return "DISK_IMAGE", f"The developer disk image couldn't be mounted ({type(exc).__name__})."
    if isinstance(exc, (UserspaceTunnelUnavailableError, TunneldConnectionError)):
        return "TUNNEL", str(exc) or f"No tunnel to the {noun} could be opened."
    if isinstance(exc, (ConnectionTerminatedError, ConnectionFailedError, ConnectionError, asyncio.IncompleteReadError)):
        return "CONNECTION", f"The connection to the {noun} was interrupted."
    if isinstance(exc, (TimeoutError, asyncio.TimeoutError)):
        return "CONNECTION", f"The {noun} stopped responding."
    detail = str(exc)
    return "UNKNOWN", f"{type(exc).__name__}: {detail}" if detail else type(exc).__name__


class Session:
    """One device's connection stack, kept open while a location is simulated."""

    def __init__(self, helper: "Helper", udid: str) -> None:
        self.helper = helper
        self.udid = udid
        self.lock = asyncio.Lock()
        self.target: Optional[tuple[float, float]] = None
        self.latest_request = 0
        self.phase = "idle"

        self._lockdown = None
        self._tunnel = None  # NativeRemotedTunnel | UserspaceRsdTunnel
        self._tunneld_rsd = None  # RSD borrowed from a running tunneld; ours to close
        self._rsd = None  # CoreDevice RSD, iOS 17+
        self._location = None  # LegacyLocationSimulation, iOS 16 and earlier

    @property
    def _connected(self) -> bool:
        return self._rsd is not None or self._location is not None

    @property
    def noun(self) -> str:
        """Device word ("iPhone", "iPad", …) for messages about this device."""
        return self.helper.noun(self.udid)

    # -- public operations (each takes the session lock) --

    async def set_location(self, latitude: float, longitude: float, request_number: int) -> bool:
        """Applies the location. Returns False if a newer request replaced this one while it waited."""
        async with self.lock:
            if request_number != self.latest_request:
                return False
            self.target = (latitude, longitude)
            try:
                await self._apply_with_reconnect()
            except BaseException as exc:
                self.target = None
                await self._close()
                self._status("error", classify(exc, self.noun)[1])
                raise
            self._status("active")
            logger.info("%s now at %.6f, %.6f", self.udid, latitude, longitude)
            return True

    async def clear(self) -> None:
        async with self.lock:
            self.latest_request += 1  # drop any queued teleports
            self.target = None
            self._status("connecting", "Restoring the real location…")
            try:
                if not self._connected:
                    # No live connection — a relaunched app, or a session that dropped. Open one
                    # anyway so a location left over from an earlier run can still be cleared.
                    await self._open()
                await self._clear_now()
            except Exception as exc:
                await self._close()
                self._status("error", classify(exc, self.noun)[1])
                raise
            await self._close()
            self._status("idle")
            logger.info("%s restored to its real location", self.udid)

    async def keepalive(self) -> None:
        """Re-sends the location; reconnects and re-applies it if the connection dropped."""
        if self.target is None or self.lock.locked() or self._location is not None:
            return  # the pre-iOS 17 service keeps the location on its own; nothing to refresh
        async with self.lock:
            if self.target is None:
                return
            try:
                was_connected = self._connected
                await self._apply()
                if not was_connected:
                    logger.info("%s reconnected", self.udid)
                if self.phase != "active":
                    self._status("active")
            except Exception as exc:
                await self._close()
                reason = classify(exc, self.noun)[1]
                if self.phase != "reconnecting":
                    logger.warning("%s connection lost: %s", self.udid, reason)
                self._status("reconnecting", f"Connection lost: {reason} Retrying…")

    async def shutdown(self) -> None:
        """Best-effort restore when the app quits, over a connection that's already open: opening
        a new one can take longer than the app waits before terminating the helper."""
        async with self.lock:
            if self.target is not None and self._connected:
                try:
                    await asyncio.wait_for(self._clear_now(), 3)
                    logger.info("%s restored to its real location on quit", self.udid)
                except Exception as exc:
                    logger.warning("%s: couldn't restore the location on quit: %r", self.udid, exc)
            self.target = None
            await self._close()

    async def _clear_now(self) -> None:
        """Sends the clear through whichever service this connection uses. Caller holds the lock."""
        if self._rsd is not None:
            await self._core_device(CLEAR_SIMULATED_LOCATION_ACTION, {})
        else:
            await asyncio.wait_for(self._location.clear(), DEVICE_CALL_TIMEOUT)

    async def _core_device(self, action: str, payload: dict[str, Any]) -> Any:
        """Invoke a CoreDevice location action (iOS 17+), opening a short-lived service for it."""
        service = LocationService(self._rsd)
        try:
            await service.connect()
            return await asyncio.wait_for(
                service.invoke(SIMULATE_LOCATION_FEATURE, payload, action_identifier=action),
                DEVICE_CALL_TIMEOUT,
            )
        finally:
            with suppress(Exception):
                await service.close()

    # -- connection management (callers hold the lock) --

    async def _apply_with_reconnect(self) -> None:
        was_connected = self._connected
        try:
            await self._apply()
        except Exception as exc:
            await self._close()
            if not was_connected:
                raise
            logger.info("%s connection went stale (%r); reconnecting", self.udid, exc)
            await self._apply()

    async def _apply(self) -> None:
        assert self.target is not None
        if not self._connected:
            try:
                await self._open()
            except BaseException:
                await self._close()
                raise
        latitude, longitude = self.target
        if self._rsd is not None:
            await self._core_device(SET_SIMULATED_LOCATION_ACTION, {"latitude": latitude, "longitude": longitude})
        else:
            await asyncio.wait_for(self._location.set(latitude, longitude), DEVICE_CALL_TIMEOUT)

    async def _open(self) -> None:
        device = self.helper.devices.get(self.udid, {})
        waiting_for_trust = device and not device.get("paired")
        self._status("connecting", f"Unlock your {self.noun} and tap Trust…" if waiting_for_trust else None)

        self._lockdown = await create_using_usbmux(serial=self.udid, autopair=True, pair_timeout=PAIR_TIMEOUT)
        version = Version(self._lockdown.product_version)
        if version.major >= 16 and not await self._lockdown.get_developer_mode_status():
            raise DeveloperModeIsNotEnabledError()

        self._status("mounting")
        if version >= Version("17.0"):
            # The download is synchronous; keep it off the event loop so the app stays responsive.
            await asyncio.to_thread(fetch_personalized_ddi)
        try:
            await auto_mount(self._lockdown)
            logger.info("developer disk image mounted")
        except AlreadyMountedError:
            pass

        if version < Version("17.0"):
            # The classic service keeps the location after disconnecting; no tunnel needed.
            self._location = LegacyLocationSimulation(self._lockdown)
            return

        self._status("tunneling")
        self._rsd = await self._open_tunnel()

    async def _open_tunnel(self):
        """No-root tunnels first (Apple's remoted, then in-process userspace), then a running tunneld."""
        failures: list[str] = []

        try:
            from pymobiledevice3.remote.native_tunnel import NativeRemotedTunnel

            tunnel = NativeRemotedTunnel(serial=self.udid)
            rsd = await asyncio.wait_for(tunnel.aopen(), TUNNEL_TIMEOUT)
            self._tunnel = tunnel
            logger.info("tunnel: macOS remoted (no root)")
            return rsd
        except Exception as exc:
            failures.append(f"remoted: {classify(exc, self.noun)[1]}")
            logger.info("remoted tunnel unavailable: %r", exc)

        try:
            from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel

            tunnel = UserspaceRsdTunnel(serial=self.udid, autopair=True, remotepairing_fallback=False)
            rsd = await asyncio.wait_for(tunnel.aopen(), TUNNEL_TIMEOUT)
            self._tunnel = tunnel
            logger.info("tunnel: userspace (no root)")
            return rsd
        except Exception as exc:
            failures.append(f"userspace: {classify(exc, self.noun)[1]}")
            logger.info("userspace tunnel unavailable: %r", exc)

        try:
            rsd = await get_tunneld_device_by_udid(self.udid)
            if rsd is not None:
                self._tunneld_rsd = rsd
                logger.info("tunnel: tunneld")
                return rsd
            failures.append(f"tunneld: running, but has no tunnel for this {self.noun}")
        except TunneldConnectionError:
            failures.append("tunneld: not running")
        except Exception as exc:
            failures.append(f"tunneld: {classify(exc, self.noun)[1]}")

        raise HelperError("TUNNEL", f"Couldn't open a tunnel to the {self.noun}. " + "; ".join(failures))

    async def _close(self) -> None:
        tunnel, tunneld_rsd, lockdown = self._tunnel, self._tunneld_rsd, self._lockdown
        self._location = self._tunnel = self._tunneld_rsd = self._lockdown = self._rsd = None
        closers = [
            tunnel.aclose if tunnel else None,
            tunneld_rsd.close if tunneld_rsd else None,
            lockdown.close if lockdown else None,
        ]
        for closer in closers:
            if closer is not None:
                with suppress(Exception):
                    await asyncio.wait_for(closer(), 5)

    def _status(self, phase: str, message: Optional[str] = None) -> None:
        self.phase = phase
        latitude, longitude = self.target if self.target else (None, None)
        emit({
            "event": "status",
            "status": {"udid": self.udid, "phase": phase, "message": message, "latitude": latitude, "longitude": longitude},
        })


class Helper:
    def __init__(self) -> None:
        self.sessions: dict[str, Session] = {}
        self.devices: dict[str, dict[str, Any]] = {}
        self._mux_snapshot: set[tuple[str, str]] = set()
        self._last_detail_refresh = 0.0
        self._refresh_lock: Optional[asyncio.Lock] = None
        self._tasks: set[asyncio.Task] = set()
        self._revealed_developer_mode: set[str] = set()

    async def run(self) -> None:
        loop = asyncio.get_running_loop()
        self._refresh_lock = asyncio.Lock()
        lines: asyncio.Queue[Optional[str]] = asyncio.Queue()

        def read_stdin() -> None:
            while True:
                line = sys.stdin.readline()
                if not line:
                    break
                loop.call_soon_threadsafe(lines.put_nowait, line)
            loop.call_soon_threadsafe(lines.put_nowait, None)

        threading.Thread(target=read_stdin, name="stdin", daemon=True).start()
        background = [asyncio.create_task(self._poll_devices()), asyncio.create_task(self._keepalive())]
        logger.info("helper ready (pymobiledevice3 %s)", importlib.metadata.version("pymobiledevice3"))

        while True:
            line = await lines.get()
            if line is None:
                await self._shutdown()
                break
            try:
                request = json.loads(line)
            except json.JSONDecodeError:
                logger.warning("ignoring malformed request: %r", line)
                continue
            if request.get("cmd") == "shutdown":
                await self._shutdown()
                emit({"id": request.get("id"), "ok": True})
                break
            task = asyncio.create_task(self._handle(request))
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

        for task in background:
            task.cancel()

    async def _handle(self, request: dict[str, Any]) -> None:
        request_id = request.get("id")
        udid = request.get("udid")
        try:
            result = await self._dispatch(request.get("cmd"), request)
            emit({"id": request_id, "ok": True, **(result or {})})
        except Exception as exc:
            code, message = classify(exc, self.noun(udid) if isinstance(udid, str) else "device")
            if code == "UNKNOWN":
                logger.exception("%s failed", request.get("cmd"))
            else:
                logger.info("%s failed: %s (%r)", request.get("cmd"), message, exc)
            emit({"id": request_id, "ok": False, "error": {"code": code, "message": message}})

    async def _dispatch(self, cmd: Any, request: dict[str, Any]) -> Optional[dict[str, Any]]:
        if cmd == "hello":
            return {"version": importlib.metadata.version("pymobiledevice3"), "devices": await self._refresh_devices(force=True)}
        if cmd == "list":
            return {"devices": await self._refresh_devices(force=True)}
        if cmd == "set":
            udid = self._require_udid(request)
            latitude, longitude = self._require_coordinate(request)
            session = self.sessions.setdefault(udid, Session(self, udid))
            session.latest_request += 1
            applied = await session.set_location(latitude, longitude, session.latest_request)
            return None if applied else {"superseded": True}
        if cmd == "clear":
            # Always go through a session, even when this run never set a location: the device may
            # still be simulating one from an earlier run.
            udid = self._require_udid(request)
            await self.sessions.setdefault(udid, Session(self, udid)).clear()
            return None
        if cmd == "pair":
            udid = self._require_udid(request)
            lockdown = await create_using_usbmux(serial=udid, autopair=True, pair_timeout=PAIR_TIMEOUT)
            await lockdown.close()
            return {"devices": await self._refresh_devices(force=True)}
        raise HelperError("BAD_REQUEST", f"Unknown command: {cmd!r}")

    @staticmethod
    def _require_udid(request: dict[str, Any]) -> str:
        udid = request.get("udid")
        if not isinstance(udid, str) or not udid:
            raise HelperError("NO_DEVICE", "No device was specified.")
        return udid

    @staticmethod
    def _require_coordinate(request: dict[str, Any]) -> tuple[float, float]:
        try:
            latitude, longitude = float(request["lat"]), float(request["lon"])
        except (KeyError, TypeError, ValueError):
            raise HelperError("INVALID_COORDINATE", "Latitude and longitude must be numbers.") from None
        if not (-90 <= latitude <= 90) or not math.isfinite(longitude):
            raise HelperError("INVALID_COORDINATE", f"{latitude}, {longitude} is outside the valid range.")
        # A map panned across the antimeridian can report longitudes past ±180; wrap them back.
        return latitude, (longitude + 180.0) % 360.0 - 180.0

    # -- device discovery --

    #: lockdown DeviceClass values mapped to the word used in messages.
    DEVICE_NOUNS = {
        "iPhone": "iPhone",
        "iPad": "iPad",
        "iPod": "iPod touch",
        "AppleTV": "Apple TV",
        "Watch": "Apple Watch",
        "RealityDevice": "Vision Pro",
    }

    def noun(self, udid: Optional[str]) -> str:
        """What to call a device in messages: its class as a readable word, or a neutral fallback."""
        return self.DEVICE_NOUNS.get(self.devices.get(udid or "", {}).get("device_class"), "device")

    async def _poll_devices(self) -> None:
        while True:
            try:
                await self._refresh_devices()
            except Exception as exc:
                logger.debug("device poll failed: %r", exc)
            await asyncio.sleep(DEVICE_POLL_INTERVAL)

    async def _refresh_devices(self, force: bool = False) -> list[dict[str, Any]]:
        assert self._refresh_lock is not None
        async with self._refresh_lock:
            chosen: dict[str, Any] = {}
            for mux_device in await usbmux.list_devices():
                if mux_device.serial not in chosen or mux_device.is_usb:
                    chosen[mux_device.serial] = mux_device
            snapshot = {(udid, device.connection_type) for udid, device in chosen.items()}

            now = asyncio.get_running_loop().time()
            needs_attention = {
                udid for udid, info in self.devices.items()
                if not info["paired"] or info["developer_mode"] is False or info["problem"]
            }
            detail_due = bool(needs_attention) and now - self._last_detail_refresh >= DETAIL_REFRESH_INTERVAL
            if not force and snapshot == self._mux_snapshot and not detail_due:
                return list(self.devices.values())

            refreshed: dict[str, dict[str, Any]] = {}
            for udid, mux_device in chosen.items():
                known = self.devices.get(udid)
                if force or known is None or udid in needs_attention or known["connection"] != mux_device.connection_type:
                    refreshed[udid] = await self._describe(mux_device)
                else:
                    refreshed[udid] = known

            changed = refreshed != self.devices
            self.devices = refreshed
            self._mux_snapshot = snapshot
            self._last_detail_refresh = now
            if changed or force:
                emit({"event": "devices", "devices": list(refreshed.values())})
            return list(refreshed.values())

    async def _describe(self, mux_device: Any) -> dict[str, Any]:
        info: dict[str, Any] = {
            "udid": mux_device.serial,
            "name": "",
            "model": None,
            "ios_version": None,
            "connection": mux_device.connection_type,
            "device_class": None,
            "paired": False,
            "developer_mode": None,
            "problem": None,
        }
        try:
            # autopair=False: listing must never pop up the Trust dialog by itself.
            lockdown = await asyncio.wait_for(
                create_using_usbmux(serial=mux_device.serial, connection_type=mux_device.connection_type, autopair=False),
                10,
            )
        except Exception as exc:
            info["problem"] = classify(exc)[1]
            return info
        try:
            values = lockdown.all_values
            info["name"] = values.get("DeviceName") or ""
            info["model"] = lockdown.display_name or values.get("ProductType")
            info["ios_version"] = values.get("ProductVersion")
            info["device_class"] = values.get("DeviceClass")
            info["paired"] = bool(lockdown.paired)
            if lockdown.paired and Version(lockdown.product_version).major >= 16:
                with suppress(Exception):
                    info["developer_mode"] = await lockdown.get_developer_mode_status()
                if info["developer_mode"] is False and mux_device.serial not in self._revealed_developer_mode:
                    # Settings hides the Developer Mode switch until a developer tool asks for it,
                    # so ask once per device rather than making the user press a button.
                    self._revealed_developer_mode.add(mux_device.serial)
                    try:
                        await AmfiService(lockdown).reveal_developer_mode_option_in_ui()
                        logger.info("%s: revealed the Developer Mode switch in Settings", mux_device.serial)
                    except Exception as exc:
                        logger.info("%s: couldn't reveal the Developer Mode switch: %r", mux_device.serial, exc)
            elif lockdown.paired:
                info["developer_mode"] = True  # Developer Mode doesn't exist before iOS 16
        finally:
            with suppress(Exception):
                await lockdown.close()
        return info

    # -- lifecycle --

    async def _keepalive(self) -> None:
        while True:
            await asyncio.sleep(KEEPALIVE_INTERVAL)
            for session in list(self.sessions.values()):
                with suppress(Exception):
                    await session.keepalive()

    async def _shutdown(self) -> None:
        logger.info("shutting down; restoring real locations")
        await asyncio.gather(*(session.shutdown() for session in self.sessions.values()), return_exceptions=True)


def main() -> None:
    try:
        asyncio.run(Helper().run())
    except KeyboardInterrupt:
        pass
    finally:
        with suppress(Exception):
            _protocol_out.flush()
        # Tunnel libraries may leave worker threads parked; don't let them hold the process open.
        os._exit(0)


if __name__ == "__main__":
    main()
