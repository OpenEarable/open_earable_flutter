#!/usr/bin/env python3
"""
OpenWearables LSL Dashboard.

Receives UDP JSON packets from open_earable_flutter, publishes them as
Lab Streaming Layer (LSL) outlets, and forwards live updates to a simple
built-in web dashboard.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import select
import socket
import sys
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, List, Optional, Set
from urllib.parse import quote, unquote

try:
    from pylsl import StreamInfo, StreamOutlet, local_clock
except ImportError as exc:  # pragma: no cover - import guard
    print(
        "Missing dependency: pylsl.\n"
        "Install with:\n"
        "  pip install pylsl",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc


MAX_UDP_PACKET_SIZE = 65535
SOURCE_ID_PREFIX = "oe-v1"
SOURCE_ID_EMPTY_COMPONENT = "-"
DEFAULT_DASHBOARD_PORT = 8765
DEFAULT_MAX_EVENTS = 300

DASHBOARD_TITLE = "OpenWearables LSL Dashboard"

ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"
ANSI_DIM = "\033[2m"
ANSI_GREEN = "\033[32m"
ANSI_YELLOW = "\033[33m"
ANSI_CYAN = "\033[36m"


def _supports_color() -> bool:
    if os.getenv("NO_COLOR") is not None:
        return False
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


def _styled(text: str, *codes: str) -> str:
    if not _supports_color() or not codes:
        return text
    return f"{''.join(codes)}{text}{ANSI_RESET}"


@dataclass(frozen=True)
class StreamSpec:
    name: str
    stream_type: str
    channel_count: int
    source_id: str
    device_name: str
    device_channel: str
    sensor_name: str
    source: str


@dataclass(frozen=True)
class StreamMeta:
    stream_name: str
    source_id: str
    device_name: str
    device_channel: str
    sensor_name: str
    source: str


@dataclass
class SensorClockAlignment:
    sensor_zero_seconds: float
    lsl_zero_seconds: float
    last_lsl_seconds: float


class DashboardState:
    def __init__(self, max_events: int, udp_host: str, udp_port: int) -> None:
        self._max_events = max(1, max_events)
        self._udp_host = udp_host
        self._udp_port = udp_port
        self._lock = threading.Lock()
        self._listeners: Set[queue.Queue] = set()
        self._streams_by_id: Dict[str, dict] = {}
        self._recent_events: List[dict] = []
        self._packets_received = 0
        self._last_packet_wall_time: Optional[float] = None

    def add_listener(self) -> queue.Queue:
        listener: queue.Queue = queue.Queue(maxsize=256)
        with self._lock:
            self._listeners.add(listener)
        return listener

    def remove_listener(self, listener: queue.Queue) -> None:
        with self._lock:
            self._listeners.discard(listener)

    def _publish_event(self, event_name: str, payload: dict) -> None:
        with self._lock:
            listeners = list(self._listeners)

        for listener in listeners:
            try:
                listener.put_nowait((event_name, payload))
            except queue.Full:
                try:
                    listener.get_nowait()
                except queue.Empty:
                    pass
                try:
                    listener.put_nowait((event_name, payload))
                except queue.Full:
                    self.remove_listener(listener)

    def snapshot(self) -> dict:
        with self._lock:
            streams = sorted(
                self._streams_by_id.values(),
                key=lambda item: (
                    str(item.get("device_name", "")).casefold(),
                    str(item.get("device_channel", "")).casefold(),
                    str(item.get("sensor_name", "")).casefold(),
                ),
            )
            return {
                "title": DASHBOARD_TITLE,
                "packets_received": self._packets_received,
                "last_packet_wall_time": self._last_packet_wall_time,
                "udp_host": self._udp_host,
                "udp_port": self._udp_port,
                "streams": streams,
                "recent_events": list(self._recent_events),
            }

    def record_sample(
        self,
        spec: StreamSpec,
        values: List[float],
        sample: dict,
        lsl_timestamp: float,
    ) -> None:
        now = time.time()
        payload = {
            "stream_name": spec.name,
            "source_id": spec.source_id,
            "device_name": spec.device_name,
            "device_channel": spec.device_channel,
            "sensor_name": spec.sensor_name,
            "source": spec.source,
            "values": values,
            "axis_names": sample.get("axis_names") or [],
            "axis_units": sample.get("axis_units") or [],
            "timestamp": sample.get("timestamp"),
            "timestamp_exponent": sample.get("timestamp_exponent"),
            "lsl_timestamp": lsl_timestamp,
            "received_at": now,
        }

        with self._lock:
            self._packets_received += 1
            self._last_packet_wall_time = now

            stream_item = self._streams_by_id.get(spec.source_id)
            if stream_item is None:
                stream_item = {
                    "stream_name": spec.name,
                    "source_id": spec.source_id,
                    "device_name": spec.device_name,
                    "device_channel": spec.device_channel,
                    "sensor_name": spec.sensor_name,
                    "source": spec.source,
                    "channel_count": spec.channel_count,
                    "samples_received": 0,
                    "last_values": [],
                    "axis_names": payload["axis_names"],
                    "axis_units": payload["axis_units"],
                    "last_lsl_timestamp": None,
                    "last_received_at": None,
                }
                self._streams_by_id[spec.source_id] = stream_item

            stream_item["samples_received"] = int(stream_item["samples_received"]) + 1
            stream_item["channel_count"] = spec.channel_count
            stream_item["last_values"] = values
            stream_item["axis_names"] = payload["axis_names"]
            stream_item["axis_units"] = payload["axis_units"]
            stream_item["last_lsl_timestamp"] = lsl_timestamp
            stream_item["last_received_at"] = now

            self._recent_events.append(payload)
            if len(self._recent_events) > self._max_events:
                self._recent_events.pop(0)

        self._publish_event(
            "sample",
            {
                "packets_received": self.packet_count,
                "last_packet_wall_time": self.last_packet_wall_time,
                "sample": payload,
            },
        )

    @property
    def packet_count(self) -> int:
        with self._lock:
            return self._packets_received

    @property
    def last_packet_wall_time(self) -> Optional[float]:
        with self._lock:
            return self._last_packet_wall_time


class DashboardRequestHandler(BaseHTTPRequestHandler):
    dashboard_state: DashboardState
    stop_event: threading.Event

    def do_GET(self) -> None:  # noqa: N802 - stdlib API
        if self.path in ("/", "/index.html"):
            body = DASHBOARD_HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/events":
            self._serve_events()
            return

        if self.path == "/health":
            body = json.dumps(
                {
                    "status": "ok",
                    "packets_received": self.dashboard_state.packet_count,
                    "last_packet_wall_time": self.dashboard_state.last_packet_wall_time,
                }
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_error(404, "Not Found")

    def _serve_events(self) -> None:
        listener = self.dashboard_state.add_listener()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        try:
            self._send_sse("snapshot", self.dashboard_state.snapshot())
            while not self.stop_event.is_set():
                try:
                    event_name, payload = listener.get(timeout=10.0)
                    self._send_sse(event_name, payload)
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        finally:
            self.dashboard_state.remove_listener(listener)

    def _send_sse(self, event_name: str, payload: dict) -> None:
        data = json.dumps(payload, separators=(",", ":"))
        self.wfile.write(f"event: {event_name}\n".encode("utf-8"))
        self.wfile.write(f"data: {data}\n\n".encode("utf-8"))
        self.wfile.flush()

    def log_message(self, format: str, *args: object) -> None:
        return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Receive OpenWearables UDP sensor packets, publish LSL streams, and "
            "serve a simple web dashboard."
        )
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="UDP bind host. Use 0.0.0.0 to listen on all interfaces (default).",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=16571,
        help="UDP bind port (default: 16571).",
    )
    parser.add_argument(
        "--dashboard-host",
        default="0.0.0.0",
        help="Web dashboard bind host (default: 0.0.0.0).",
    )
    parser.add_argument(
        "--dashboard-port",
        type=int,
        default=DEFAULT_DASHBOARD_PORT,
        help=f"Web dashboard bind port (default: {DEFAULT_DASHBOARD_PORT}).",
    )
    parser.add_argument(
        "--max-events",
        type=int,
        default=DEFAULT_MAX_EVENTS,
        help=(
            "How many recent dashboard events to keep in memory for reconnecting "
            f"clients (default: {DEFAULT_MAX_EVENTS})."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print every received sample.",
    )

    # Backward-compatible no-op flags from the old plot-based script.
    parser.add_argument("--history-seconds", type=float, default=20.0, help=argparse.SUPPRESS)
    parser.add_argument("--refresh-ms", type=int, default=100, help=argparse.SUPPRESS)
    parser.add_argument("--max-samples", type=int, default=2000, help=argparse.SUPPRESS)

    return parser.parse_args()


def _candidate_ips(bind_host: str) -> List[str]:
    addresses = set()

    if bind_host not in ("0.0.0.0", "", "::"):
        addresses.add(bind_host)

    try:
        host_name = socket.gethostname()
        for ip in socket.gethostbyname_ex(host_name)[2]:
            if "." in ip and not ip.startswith("127."):
                addresses.add(ip)
    except OSError:
        pass

    for probe_host in ("8.8.8.8", "1.1.1.1"):
        try:
            probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            probe.connect((probe_host, 80))
            local_ip = probe.getsockname()[0]
            probe.close()
            if local_ip and not local_ip.startswith("127."):
                addresses.add(local_ip)
        except OSError:
            continue

    if not addresses:
        addresses.add("127.0.0.1")

    return sorted(addresses)


def _clean_text(value: object, fallback: str = "") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    if not text:
        return fallback
    return " ".join(text.split())


def _normalize_channel(value: object) -> str:
    channel = _clean_text(value, "")
    if not channel:
        return ""
    lower = channel.lower()
    if lower.startswith("l"):
        return "L"
    if lower.startswith("r"):
        return "R"
    return channel


def _encode_source_component(value: str) -> str:
    cleaned = _clean_text(value, "")
    if not cleaned:
        return SOURCE_ID_EMPTY_COMPONENT
    return quote(cleaned, safe="")


def _decode_source_component(value: str) -> str:
    if value == SOURCE_ID_EMPTY_COMPONENT:
        return ""
    return _clean_text(unquote(value), "")


def _encode_source_id(
    device_name: str,
    device_channel: str,
    sensor_name: str,
    source: str,
) -> str:
    return ":".join(
        [
            SOURCE_ID_PREFIX,
            _encode_source_component(device_name),
            _encode_source_component(device_channel),
            _encode_source_component(sensor_name),
            _encode_source_component(source),
        ]
    )


def _decode_source_id(source_id: str) -> Optional[Dict[str, str]]:
    parts = source_id.split(":")
    if len(parts) != 5 or parts[0] != SOURCE_ID_PREFIX:
        return None

    return {
        "device_name": _decode_source_component(parts[1]),
        "device_channel": _decode_source_component(parts[2]),
        "sensor_name": _decode_source_component(parts[3]),
        "source": _decode_source_component(parts[4]),
    }


def _build_stream_name(
    device_name: str,
    device_channel: str,
    sensor_name: str,
    source: str,
) -> str:
    channel_suffix = f" [{device_channel}]" if device_channel else ""
    return f"{device_name}{channel_suffix} ({source}) - {sensor_name}"


def _resolve_stream_meta(sample: dict) -> StreamMeta:
    raw_source_id = _clean_text(sample.get("source_id"), "")
    decoded_source = _decode_source_id(raw_source_id) if raw_source_id else None

    fallback_device = _clean_text(
        sample.get("device_name")
        or sample.get("device_token")
        or sample.get("device_id"),
        "unknown_device",
    )
    fallback_channel = _normalize_channel(
        sample.get("device_channel") or sample.get("device_side")
    )
    fallback_sensor = _clean_text(sample.get("sensor_name"), "unknown_sensor")
    fallback_source = _clean_text(
        sample.get("device_source")
        or sample.get("device_id")
        or sample.get("device_token"),
        "unknown_source",
    )

    device_name = _clean_text(
        decoded_source.get("device_name") if decoded_source else None,
        fallback_device,
    )
    device_channel = _normalize_channel(
        decoded_source.get("device_channel") if decoded_source else fallback_channel
    )
    sensor_name = _clean_text(
        decoded_source.get("sensor_name") if decoded_source else None,
        fallback_sensor,
    )
    source = _clean_text(
        decoded_source.get("source") if decoded_source else None,
        fallback_source,
    )

    source_id = raw_source_id or _encode_source_id(
        device_name=device_name,
        device_channel=device_channel,
        sensor_name=sensor_name,
        source=source,
    )
    stream_name = _clean_text(sample.get("stream_name"), "") or _build_stream_name(
        device_name=device_name,
        device_channel=device_channel,
        sensor_name=sensor_name,
        source=source,
    )

    return StreamMeta(
        stream_name=stream_name,
        source_id=source_id,
        device_name=device_name,
        device_channel=device_channel,
        sensor_name=sensor_name,
        source=source,
    )


def _parse_values(sample: dict) -> List[float]:
    raw_values = sample.get("values")
    if not isinstance(raw_values, list):
        return []

    parsed: List[float] = []
    for value in raw_values:
        try:
            parsed.append(float(value))
        except (TypeError, ValueError):
            continue
    return parsed


def _stream_spec(sample: dict, values: List[float]) -> StreamSpec:
    meta = _resolve_stream_meta(sample)
    return StreamSpec(
        name=meta.stream_name,
        stream_type="OpenWearables",
        channel_count=len(values),
        source_id=meta.source_id,
        device_name=meta.device_name,
        device_channel=meta.device_channel,
        sensor_name=meta.sensor_name,
        source=meta.source,
    )


def _sensor_timestamp_seconds(sample: dict) -> Optional[float]:
    raw_timestamp = sample.get("timestamp")
    raw_exponent = sample.get("timestamp_exponent")
    if raw_timestamp is None or raw_exponent is None:
        return None

    try:
        timestamp = float(raw_timestamp)
        exponent = int(raw_exponent)
    except (TypeError, ValueError):
        return None

    try:
        return timestamp * (10.0 ** exponent)
    except OverflowError:
        return None


def _create_outlet(sample: dict, values: List[float]) -> StreamOutlet:
    meta = _resolve_stream_meta(sample)
    device_token = _clean_text(
        sample.get("device_token") or sample.get("device_id"),
        "unknown_device",
    )
    axis_names = sample.get("axis_names") or []
    axis_units = sample.get("axis_units") or []

    info = StreamInfo(
        name=meta.stream_name,
        type="OpenWearables",
        channel_count=len(values),
        nominal_srate=0.0,
        channel_format="float32",
        source_id=meta.source_id,
    )

    desc = info.desc()
    desc.append_child_value("manufacturer", "OpenWearables")
    desc.append_child_value("device_token", device_token)
    desc.append_child_value("device_name", meta.device_name)
    desc.append_child_value("device_channel", meta.device_channel)
    if meta.device_channel:
        desc.append_child_value("device_side", meta.device_channel)
    desc.append_child_value("device_source", meta.source)
    desc.append_child_value("sensor_name", meta.sensor_name)
    desc.append_child_value("source_id", meta.source_id)
    desc.append_child_value("timestamp_exponent", str(sample.get("timestamp_exponent", -3)))

    channels = desc.append_child("channels")
    for idx in range(len(values)):
        ch = channels.append_child("channel")
        label = axis_names[idx] if idx < len(axis_names) else f"ch_{idx}"
        if meta.device_channel:
            label = f"{meta.device_channel}-{label}"
        unit = axis_units[idx] if idx < len(axis_units) else ""
        ch.append_child_value("label", str(label))
        ch.append_child_value("unit", str(unit))
        ch.append_child_value("type", meta.sensor_name)

    return StreamOutlet(info)


class LslBridgeApp:
    def __init__(self, args: argparse.Namespace) -> None:
        self._args = args
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.bind((args.host, args.port))
        self._sock.setblocking(False)

        self._outlets: Dict[StreamSpec, StreamOutlet] = {}
        self._clock_alignment: Dict[StreamSpec, SensorClockAlignment] = {}

        self._dashboard_state = DashboardState(
            max_events=args.max_events,
            udp_host=args.host,
            udp_port=args.port,
        )
        self._stop_event = threading.Event()

        handler_cls = self._handler_class()
        self._dashboard_server = ThreadingHTTPServer(
            (args.dashboard_host, args.dashboard_port), handler_cls
        )
        self._dashboard_server.daemon_threads = True
        self._dashboard_thread = threading.Thread(
            target=self._dashboard_server.serve_forever,
            kwargs={"poll_interval": 0.25},
            daemon=True,
            name="openwearables-dashboard",
        )

        self._print_startup()

    def _handler_class(self) -> type[DashboardRequestHandler]:
        dashboard_state = self._dashboard_state
        stop_event = self._stop_event

        class Handler(DashboardRequestHandler):
            pass

        Handler.dashboard_state = dashboard_state
        Handler.stop_event = stop_event
        return Handler

    def _print_startup(self) -> None:
        udp_ips = _candidate_ips(self._args.host)
        selected_udp_ip = udp_ips[0]

        if self._args.dashboard_host in ("0.0.0.0", "", "::"):
            dashboard_ips = _candidate_ips(self._args.dashboard_host)
        else:
            dashboard_ips = [self._args.dashboard_host]

        dashboard_url = f"http://{dashboard_ips[0]}:{self._args.dashboard_port}"

        print("")
        print(_styled("OpenWearables LSL Dashboard started.", ANSI_BOLD, ANSI_CYAN))
        print(
            _styled(
                f"Listening for UDP packets on {self._args.host}:{self._args.port}",
                ANSI_GREEN,
            )
        )
        print(_styled("Use one of these IPs in your Flutter app:", ANSI_BOLD))
        for ip in udp_ips:
            marker = " (recommended)" if ip == selected_udp_ip else ""
            print(f"  - {_styled(ip, ANSI_YELLOW)}{marker}")

        print("")
        print(_styled("Example app setup:", ANSI_BOLD))
        print(_styled("  final lslForwarder = LslForwarder.instance;", ANSI_DIM))
        print(
            _styled(
                f"  lslForwarder.configure(host: '{selected_udp_ip}', port: {self._args.port}, enabled: true);",
                ANSI_DIM,
            )
        )
        print(_styled("  WearableManager().addSensorForwarder(lslForwarder);", ANSI_DIM))

        print("")
        print(_styled("Web dashboard URLs:", ANSI_BOLD))
        for ip in dashboard_ips:
            marker = " (recommended)" if ip == dashboard_ips[0] else ""
            print(f"  - http://{ip}:{self._args.dashboard_port}{marker}")

        print("")
        print(f"Open your browser to {dashboard_url}")
        print("Press Ctrl+C to stop.")

    def _lsl_timestamp_for_sample(
        self, spec: StreamSpec, sensor_time_seconds: Optional[float]
    ) -> float:
        if sensor_time_seconds is None:
            return local_clock()

        alignment = self._clock_alignment.get(spec)
        if alignment is None:
            now = local_clock()
            self._clock_alignment[spec] = SensorClockAlignment(
                sensor_zero_seconds=sensor_time_seconds,
                lsl_zero_seconds=now,
                last_lsl_seconds=now,
            )
            return now

        lsl_time = alignment.lsl_zero_seconds + (
            sensor_time_seconds - alignment.sensor_zero_seconds
        )

        if lsl_time <= alignment.last_lsl_seconds:
            lsl_time = alignment.last_lsl_seconds + 1e-6
        alignment.last_lsl_seconds = lsl_time
        return lsl_time

    def _process_packet(self, packet: bytes, remote: tuple[str, int]) -> None:
        try:
            sample = json.loads(packet.decode("utf-8"))
        except json.JSONDecodeError:
            print(f"Ignoring non-JSON packet from {remote[0]}:{remote[1]}")
            return

        if not isinstance(sample, dict):
            print(f"Ignoring unexpected payload type from {remote[0]}:{remote[1]}")
            return

        if sample.get("type") != "open_earable_lsl_sample":
            return

        values = _parse_values(sample)
        if not values:
            return

        spec = _stream_spec(sample, values)
        sensor_time_seconds = _sensor_timestamp_seconds(sample)
        lsl_timestamp = self._lsl_timestamp_for_sample(spec, sensor_time_seconds)

        outlet = self._outlets.get(spec)
        if outlet is None:
            outlet = _create_outlet(sample, values)
            self._outlets[spec] = outlet
            print(
                "Created LSL outlet: "
                f"name='{spec.name}', channels={spec.channel_count}, source_id='{spec.source_id}'"
            )

        outlet.push_sample(values, lsl_timestamp)
        self._dashboard_state.record_sample(spec, values, sample, lsl_timestamp)

        if self._args.verbose:
            print(
                f"Sample {spec.name}: {values} "
                f"(device_ts={sample.get('timestamp')}, lsl_ts={lsl_timestamp:.6f})"
            )

    def _drain_udp(self) -> None:
        while True:
            try:
                packet, remote = self._sock.recvfrom(MAX_UDP_PACKET_SIZE)
            except BlockingIOError:
                return
            except OSError:
                return
            self._process_packet(packet, remote)

    def run(self) -> None:
        self._dashboard_thread.start()
        while not self._stop_event.is_set():
            try:
                ready, _, _ = select.select([self._sock], [], [], 0.25)
            except (ValueError, OSError):
                break
            if ready:
                self._drain_udp()

    def close(self) -> None:
        self._stop_event.set()
        try:
            self._dashboard_server.shutdown()
            self._dashboard_server.server_close()
        except Exception:
            pass
        self._sock.close()


DASHBOARD_HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>OpenWearables LSL Dashboard</title>
  <style>
    :root {
      --bg: #ffffff;
      --panel: #ffffff;
      --border: #dbe4ee;
      --text: #213244;
      --muted: #5c7287;
      --accent: #2f7fb3;
      --channel-tint: #B89491;
      --live-bg: #e7f4ec;
      --live-text: #2e7a55;
      --wait-bg: #edf3f8;
      --wait-text: #5c7287;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
    }

    .shell {
      width: 100%;
      margin: 0;
      padding: 12px 14px 24px;
    }

    .head {
      background: #B89491;
      border: 1px solid #a88481;
      border-radius: 14px;
      padding: 18px 20px;
      box-shadow: 0 8px 20px rgba(111, 84, 82, 0.22);
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      grid-template-areas:
        "title right"
        "meta meta";
      column-gap: 14px;
      row-gap: 8px;
      align-items: start;
      min-width: 0;
    }

    .title {
      grid-area: title;
      margin: 0;
      font-size: clamp(18px, 2.2vw, 22px);
      line-height: 1.2;
      letter-spacing: 0.2px;
      color: #fff7f6;
      min-width: 0;
      max-width: 100%;
      overflow-wrap: anywhere;
    }

    .meta {
      grid-area: meta;
      display: flex;
      gap: 10px;
      row-gap: 6px;
      flex-wrap: wrap;
      align-items: center;
      margin-top: 0;
      color: #f7eceb;
      font-size: 14px;
      min-width: 0;
    }

    .meta > span {
      white-space: nowrap;
      min-width: 0;
    }

    .meta-right {
      grid-area: right;
      justify-self: end;
      align-self: start;
      display: inline-flex;
      flex-direction: column;
      align-items: flex-end;
      justify-content: flex-start;
      gap: 5px;
      min-width: 0;
      max-width: min(48vw, 360px);
    }

    .endpoint {
      font-size: 12px;
      color: #fff1ef;
      font-family: "SFMono-Regular", Menlo, Consolas, monospace;
      letter-spacing: 0.1px;
      white-space: nowrap;
      text-align: right;
      line-height: 1.2;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .status-pill {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 999px;
      font-size: 12px;
      line-height: 1;
      padding: 4px 10px;
      border: 1px solid var(--border);
    }

    .status-pill.live {
      background: var(--live-bg);
      color: var(--live-text);
    }

    .status-pill.waiting {
      background: var(--wait-bg);
      color: var(--wait-text);
    }

    .devices {
      margin-top: 12px;
      display: grid;
      gap: 18px;
    }

    .device-section {
      background: transparent;
      border: 0;
      border-radius: 0;
      padding: 0;
      box-shadow: none;
    }

    .device-header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 8px;
      padding: 4px 2px 10px;
      border-bottom: 1px solid #e9eef5;
      margin-bottom: 10px;
    }

    .device-title {
      margin: 0;
      font-size: 16px;
      color: var(--text);
      letter-spacing: 0.15px;
      display: inline-flex;
      align-items: center;
      gap: 7px;
    }

    .channel-badge {
      width: 19px;
      height: 19px;
      border-radius: 999px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.2px;
      text-transform: uppercase;
      color: #6f5452;
      background: rgba(184, 148, 145, 0.22);
      border: 1px solid rgba(184, 148, 145, 0.52);
    }

    .device-meta {
      font-size: 12px;
      color: var(--muted);
      text-align: right;
      white-space: nowrap;
    }

    .sensor-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(460px, 1fr));
      gap: 12px;
      align-items: start;
    }

    .stream-row {
      padding: 0;
      border: 0;
      border-radius: 0;
      background: transparent;
      min-width: 0;
    }

    .stream-head {
      display: flex;
      align-items: baseline;
      justify-content: flex-start;
    }

    .stream-title {
      margin: 0;
      font-size: 16px;
      line-height: 1.25;
      color: var(--text);
    }

    .legend {
      margin-top: 8px;
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }

    .legend-item {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border: 1px solid #dbe5f0;
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 11px;
      color: #41566b;
      background: #f8fbff;
      cursor: pointer;
      user-select: none;
      transition: background-color 120ms ease, border-color 120ms ease, opacity 120ms ease;
    }

    .legend-item:hover {
      background: #eef5fd;
      border-color: #c9d7e7;
    }

    .legend-item:focus-visible {
      outline: 2px solid #8fb4d8;
      outline-offset: 1px;
    }

    .legend-item.is-disabled {
      opacity: 0.45;
      background: #f6f8fb;
      border-color: #dfe7f1;
    }

    .legend-item.is-disabled .legend-text {
      text-decoration: line-through;
      text-decoration-thickness: 1.2px;
    }

    .legend-check {
      margin: 0;
      width: 13px;
      height: 13px;
      accent-color: #799fc2;
      cursor: pointer;
    }

    .legend-dot {
      width: 8px;
      height: 8px;
      border-radius: 999px;
      flex: 0 0 8px;
    }

    .chart-wrap {
      margin-top: 8px;
      width: 100%;
      aspect-ratio: 1000 / 320;
      height: auto;
      min-height: 150px;
      border: 1px solid #d8e4f0;
      border-radius: 6px;
      background: #ffffff;
      overflow: hidden;
    }

    .chart-wrap svg {
      width: 100%;
      height: 100%;
      display: block;
    }

    .empty {
      margin-top: 16px;
      background: var(--panel);
      border: 1px dashed var(--border);
      border-radius: 12px;
      padding: 26px;
      color: var(--muted);
      text-align: center;
    }

    @media (max-width: 1500px) {
      .sensor-grid {
        grid-template-columns: repeat(auto-fit, minmax(390px, 1fr));
      }
    }

    @media (max-width: 1100px) {
      .sensor-grid {
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      }

      .head {
        padding: 16px 16px;
      }

      .title {
        font-size: clamp(17px, 2.8vw, 21px);
      }
    }

    @media (max-width: 700px) {
      .shell {
        padding: 8px 8px 18px;
      }

      .head {
        grid-template-columns: 1fr;
        grid-template-areas:
          "right"
          "title"
          "meta";
        row-gap: 10px;
      }

      .meta-right {
        justify-self: end;
        align-items: flex-end;
        width: min(100%, 340px);
        max-width: 100%;
      }

      .meta {
        font-size: 13px;
        gap: 8px;
      }
    }

    @media (max-width: 460px) {
      .head {
        padding: 12px 12px;
        row-gap: 8px;
      }

      .endpoint {
        font-size: 11px;
      }

      .title {
        font-size: 16px;
      }

      .status-pill {
        font-size: 11px;
        padding: 3px 8px;
      }

      .sensor-grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="head">
      <h1 class="title" id="title">OpenWearables LSL Dashboard</h1>
      <div class="meta-right">
        <span id="endpoint" class="endpoint">UDP: --</span>
        <span id="status" class="status-pill waiting">WAITING</span>
      </div>
      <div class="meta">
        <span id="packets">0 packets</span>
        <span id="streamsCount">0 streams</span>
        <span id="lastPacket">No data yet</span>
      </div>
    </section>

    <section id="devices" class="devices" hidden></section>
    <section id="empty" class="empty">Waiting for packets. Keep this page open.</section>
  </main>

  <script>
    const state = {
      packetsReceived: 0,
      lastPacketWallTime: null,
      udpHost: "",
      udpPort: null,
      streams: new Map(),
      channelEnabledBySource: new Map(),
      renderTimer: null,
    };

    const CHART_COLORS = [
      "#1f77b4",
      "#d62728",
      "#2ca02c",
      "#ff7f0e",
      "#9467bd",
      "#17becf",
      "#8c564b",
      "#e377c2",
    ];
    const MAX_POINTS_PER_CHANNEL = 6000;
    const GRAPH_LOOKBACK_SECONDS = 20.0;
    const RENDER_DEBOUNCE_MS = 80;

    const titleEl = document.getElementById("title");
    const packetsEl = document.getElementById("packets");
    const streamsCountEl = document.getElementById("streamsCount");
    const lastPacketEl = document.getElementById("lastPacket");
    const endpointEl = document.getElementById("endpoint");
    const statusEl = document.getElementById("status");
    const devicesEl = document.getElementById("devices");
    const emptyEl = document.getElementById("empty");

    function asNumber(value) {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : null;
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
    }

    function formatTime(epochSeconds) {
      const ms = asNumber(epochSeconds);
      if (ms === null) return "No data yet";
      return `Last packet: ${new Date(ms * 1000).toLocaleTimeString()}`;
    }

    function statusClass(isLive) {
      return isLive ? "status-pill live" : "status-pill waiting";
    }

    function formattedUdpEndpoint() {
      const configuredHost = String(state.udpHost || "").trim();
      const host =
        configuredHost && configuredHost !== "0.0.0.0" && configuredHost !== "::"
          ? configuredHost
          : (window.location.hostname || "localhost");
      const port = Number(state.udpPort);
      if (!Number.isFinite(port) || port <= 0) {
        return `${host}:--`;
      }
      return `${host}:${port}`;
    }

    function normalizeStringList(value) {
      if (!Array.isArray(value)) return [];
      return value.map((item) => String(item ?? ""));
    }

    function normalizeNumberList(value) {
      if (!Array.isArray(value)) return [];
      return value.map((item) => asNumber(item));
    }

    function safeDecodeURIComponent(value) {
      try {
        return decodeURIComponent(value);
      } catch (error) {
        return value;
      }
    }

    function decodeSourceComponent(value) {
      if (value === "-") return "";
      return safeDecodeURIComponent(String(value || ""));
    }

    function decodeSourceId(sourceId) {
      const raw = String(sourceId || "");
      const parts = raw.split(":");
      if (parts.length !== 5 || parts[0] !== "oe-v1") return null;
      return {
        device_name: decodeSourceComponent(parts[1]),
        device_channel: decodeSourceComponent(parts[2]),
        sensor_name: decodeSourceComponent(parts[3]),
        source: decodeSourceComponent(parts[4]),
      };
    }

    function buildFallbackStreamName(meta) {
      const side = meta.device_channel ? ` [${meta.device_channel}]` : "";
      return `${meta.device_name || "unknown"}${side} (${meta.source || "unknown"}) - ${meta.sensor_name || "unknown_sensor"}`;
    }

    function sensorTimeSeconds(sample) {
      const timestamp = asNumber(sample?.timestamp);
      const exponent = Number(sample?.timestamp_exponent);
      if (timestamp === null || !Number.isFinite(exponent)) return null;
      const seconds = timestamp * (10 ** exponent);
      return Number.isFinite(seconds) ? seconds : null;
    }

    function sampleTimelineTimeSeconds(sample) {
      return (
        sensorTimeSeconds(sample) ??
        asNumber(sample?.lsl_timestamp) ??
        asNumber(sample?.received_at) ??
        (Date.now() / 1000)
      );
    }

    function channelCountFor(stream) {
      return Math.max(
        Number(stream.channel_count || 0),
        Array.isArray(stream.last_values) ? stream.last_values.length : 0,
        Array.isArray(stream.axis_names) ? stream.axis_names.length : 0,
        Array.isArray(stream._history) ? stream._history.length : 0
      );
    }

    function ensureChannelState(stream, channelCount) {
      const sourceId = String(stream?.source_id || "");
      if (!sourceId) return [];

      let states = state.channelEnabledBySource.get(sourceId);
      if (!Array.isArray(states)) {
        states = [];
      }
      while (states.length < channelCount) {
        states.push(true);
      }
      state.channelEnabledBySource.set(sourceId, states);
      return states;
    }

    function isChannelEnabled(stream, channelIndex) {
      const states = ensureChannelState(stream, channelIndex + 1);
      return states[channelIndex] !== false;
    }

    function setChannelEnabled(stream, channelIndex, enabled) {
      const states = ensureChannelState(stream, channelIndex + 1);
      states[channelIndex] = Boolean(enabled);
    }

    function normalizeStream(raw) {
      const decoded = decodeSourceId(raw.source_id);
      const deviceName = String(raw.device_name || decoded?.device_name || "unknown");
      const deviceChannel = String(raw.device_channel || decoded?.device_channel || "");
      const sensorName = String(raw.sensor_name || decoded?.sensor_name || "");
      const source = String(raw.source || raw.device_source || decoded?.source || "unknown");
      const streamName = String(
        raw.stream_name || buildFallbackStreamName({
          device_name: deviceName,
          device_channel: deviceChannel,
          sensor_name: sensorName,
          source: source,
        })
      );

      const stream = {
        stream_name: streamName,
        source_id: String(raw.source_id || ""),
        device_name: deviceName,
        device_channel: deviceChannel,
        sensor_name: sensorName,
        source: source,
        channel_count: Number(raw.channel_count || 0),
        samples_received: Number(raw.samples_received || 0),
        last_values: normalizeNumberList(raw.last_values),
        axis_names: normalizeStringList(raw.axis_names),
        axis_units: normalizeStringList(raw.axis_units),
        last_lsl_timestamp: raw.last_lsl_timestamp ?? null,
        last_received_at: raw.last_received_at ?? null,
        _latest_time_seconds: asNumber(raw._latest_time_seconds),
        _history: [],
      };
      stream.channel_count = channelCountFor(stream);
      ensureChannelState(stream, stream.channel_count);
      return stream;
    }

    function ensureHistory(stream, channelCount) {
      while (stream._history.length < channelCount) {
        stream._history.push([]);
      }
    }

    function pruneSeries(series, windowEndSeconds) {
      const cutoff = windowEndSeconds - GRAPH_LOOKBACK_SECONDS;
      while (series.length > 2 && series[0].t < cutoff) {
        series.shift();
      }

      if (series.length <= MAX_POINTS_PER_CHANNEL) {
        return;
      }

      // Keep the full time window while reducing density for very high-rate streams.
      const stride = Math.ceil(series.length / MAX_POINTS_PER_CHANNEL);
      const reduced = [];
      for (let i = 0; i < series.length; i += stride) {
        reduced.push(series[i]);
      }
      const last = series[series.length - 1];
      if (reduced[reduced.length - 1] !== last) {
        reduced.push(last);
      }
      series.splice(0, series.length, ...reduced);
    }

    function appendHistory(stream, sample) {
      const values = Array.isArray(sample.values) ? sample.values : stream.last_values;
      const timestamp = sampleTimelineTimeSeconds(sample);
      const count = Math.max(channelCountFor(stream), Array.isArray(values) ? values.length : 0);
      ensureHistory(stream, count);
      if (stream._latest_time_seconds === null || timestamp > stream._latest_time_seconds) {
        stream._latest_time_seconds = timestamp;
      }
      const windowEnd = stream._latest_time_seconds ?? timestamp;

      for (let i = 0; i < count; i += 1) {
        const value = asNumber(values[i]);
        if (value === null) continue;
        const series = stream._history[i];
        series.push({ t: timestamp, v: value });
        if (series.length > 1 && series[series.length - 2].t > timestamp) {
          series.sort((a, b) => a.t - b.t);
        }
        pruneSeries(series, windowEnd);
      }
    }

    function upsertStreamFromSample(sample) {
      const sourceId = String(sample.source_id || "");
      if (!sourceId) return null;
      let stream = state.streams.get(sourceId);
      if (stream) return stream;

      stream = normalizeStream({
        stream_name: sample.stream_name,
        source_id: sourceId,
        device_name: sample.device_name,
        device_channel: sample.device_channel,
        sensor_name: sample.sensor_name,
        source: sample.source,
        channel_count: Array.isArray(sample.values) ? sample.values.length : 0,
        samples_received: 0,
        last_values: Array.isArray(sample.values) ? sample.values : [],
        axis_names: sample.axis_names,
        axis_units: sample.axis_units,
        last_lsl_timestamp: sample.lsl_timestamp,
        last_received_at: sample.received_at,
        _latest_time_seconds: sampleTimelineTimeSeconds(sample),
      });

      state.streams.set(sourceId, stream);
      return stream;
    }

    function mergeSampleIntoStream(stream, sample, incrementSamples) {
      const decoded = decodeSourceId(sample.source_id || stream.source_id);
      const nextDeviceName = String(sample.device_name || decoded?.device_name || stream.device_name || "unknown");
      const nextDeviceChannel = String(sample.device_channel || decoded?.device_channel || stream.device_channel || "");
      const nextSensorName = String(sample.sensor_name || decoded?.sensor_name || stream.sensor_name || "");
      const nextSource = String(sample.source || sample.device_source || decoded?.source || stream.source || "unknown");

      stream.device_name = nextDeviceName;
      stream.device_channel = nextDeviceChannel;
      stream.sensor_name = nextSensorName;
      stream.source = nextSource;
      stream.stream_name = String(
        sample.stream_name || stream.stream_name || buildFallbackStreamName({
          device_name: nextDeviceName,
          device_channel: nextDeviceChannel,
          sensor_name: nextSensorName,
          source: nextSource,
        })
      );

      if (Array.isArray(sample.values) && sample.values.length > 0) {
        stream.last_values = normalizeNumberList(sample.values);
      }
      if (Array.isArray(sample.axis_names) && sample.axis_names.length > 0) {
        stream.axis_names = normalizeStringList(sample.axis_names);
      }
      if (Array.isArray(sample.axis_units) && sample.axis_units.length > 0) {
        stream.axis_units = normalizeStringList(sample.axis_units);
      }

      stream.channel_count = Math.max(channelCountFor(stream), Array.isArray(sample.values) ? sample.values.length : 0);
      ensureChannelState(stream, stream.channel_count);
      stream.last_lsl_timestamp = sample.lsl_timestamp ?? stream.last_lsl_timestamp ?? null;
      stream.last_received_at = sample.received_at ?? stream.last_received_at ?? null;
      const sampleTime = sampleTimelineTimeSeconds(sample);
      if (stream._latest_time_seconds === null || sampleTime > stream._latest_time_seconds) {
        stream._latest_time_seconds = sampleTime;
      }

      if (incrementSamples) {
        stream.samples_received = Number(stream.samples_received || 0) + 1;
      }

      appendHistory(stream, sample);
    }

    function scheduleRender(immediate = false) {
      if (immediate) {
        if (state.renderTimer !== null) {
          clearTimeout(state.renderTimer);
          state.renderTimer = null;
        }
        updateStatus();
        renderStreams();
        return;
      }

      if (state.renderTimer !== null) return;
      state.renderTimer = setTimeout(() => {
        state.renderTimer = null;
        updateStatus();
        renderStreams();
      }, RENDER_DEBOUNCE_MS);
    }

    function updateStatus() {
      const now = Date.now() / 1000;
      const isLive =
        state.lastPacketWallTime !== null &&
        (now - state.lastPacketWallTime) < 2.0;

      statusEl.className = statusClass(isLive);
      statusEl.textContent = isLive ? "LIVE" : "WAITING";
      packetsEl.textContent = `${state.packetsReceived} packets`;
      streamsCountEl.textContent = `${state.streams.size} streams`;
      lastPacketEl.textContent = formatTime(state.lastPacketWallTime);
      endpointEl.textContent = `UDP ${formattedUdpEndpoint()}`;
    }

    function streamWindowEnd(stream) {
      const explicit = asNumber(stream._latest_time_seconds);
      if (explicit !== null) return explicit;

      let latest = null;
      for (const series of stream._history) {
        if (!Array.isArray(series) || series.length === 0) continue;
        const t = asNumber(series[series.length - 1]?.t);
        if (t === null) continue;
        if (latest === null || t > latest) latest = t;
      }

      if (latest !== null) return latest;
      return asNumber(stream.last_received_at) ?? (Date.now() / 1000);
    }

    function formatAxisNumber(value) {
      const num = asNumber(value);
      if (num === null) return "";
      const abs = Math.abs(num);
      if (abs >= 1000) return num.toFixed(0);
      if (abs >= 100) return num.toFixed(1);
      if (abs >= 1) return num.toFixed(2);
      if (abs >= 0.01) return num.toFixed(3);
      return num.toExponential(1);
    }

    function formatUnitLabel(unit) {
      const raw = String(unit ?? "").trim();
      if (!raw) return "";

      const superscriptMap = {
        "0": "⁰",
        "1": "¹",
        "2": "²",
        "3": "³",
        "4": "⁴",
        "5": "⁵",
        "6": "⁶",
        "7": "⁷",
        "8": "⁸",
        "9": "⁹",
        "+": "⁺",
        "-": "⁻",
      };

      return raw.replace(/\\^([+-]?\\d+)/g, (_match, exponent) =>
        String(exponent)
          .split("")
          .map((char) => superscriptMap[char] || char)
          .join("")
      );
    }

    function commonUnitLabel(stream) {
      const units = normalizeStringList(stream.axis_units).filter((item) => item.length > 0);
      if (units.length === 0) return "value";
      const first = units[0];
      return units.every((item) => item === first) ? formatUnitLabel(first) : "value";
    }

    function channelLegend(stream) {
      const channels = channelCountFor(stream);
      if (channels <= 0) return "";
      ensureHistory(stream, channels);
      ensureChannelState(stream, channels);
      const entries = Array.from({ length: channels }, (_, index) => {
        const label = stream.axis_names[index] || `ch_${index}`;
        const unit = stream.axis_units[index] || "";
        const prettyUnit = formatUnitLabel(unit);
        const text = prettyUnit ? `${label} (${prettyUnit})` : label;
        const color = CHART_COLORS[index % CHART_COLORS.length];
        const isEnabled = isChannelEnabled(stream, index);
        const disabledClass = isEnabled ? "" : " is-disabled";
        const checkedAttr = isEnabled ? " checked" : "";
        return `<label class="legend-item${disabledClass}">
          <input type="checkbox" class="legend-check" data-source-id="${escapeHtml(stream.source_id)}" data-channel-index="${index}"${checkedAttr}>
          <span class="legend-dot" style="background:${color}"></span>
          <span class="legend-text">${escapeHtml(text)}</span>
        </label>`;
      }).join("");
      return `<div class="legend">${entries}</div>`;
    }

    function streamChartSvg(stream, windowEndSeconds) {
      const viewWidth = 1000;
      const viewHeight = 320;
      const plotLeft = 88;
      const plotRight = 970;
      const plotTop = 16;
      const plotBottom = 258;
      const plotWidth = plotRight - plotLeft;
      const plotHeight = plotBottom - plotTop;
      const axisColor = "#9eb2c7";
      const gridColor = "#dbe6f2";
      const axisText = "#4e657c";
      const xTicks = [-20, -15, -10, -5, 0];
      const yTicks = 6;
      const windowEnd = Number.isFinite(windowEndSeconds) ? windowEndSeconds : streamWindowEnd(stream);
      const windowStart = windowEnd - GRAPH_LOOKBACK_SECONDS;
      const channels = channelCountFor(stream);
      const yAxisLabel = commonUnitLabel(stream);

      ensureHistory(stream, channels);
      ensureChannelState(stream, channels);
      const hasAnyEnabledChannel = Array.from({ length: channels }, (_, index) => isChannelEnabled(stream, index)).some(Boolean);

      const series = Array.from({ length: channels }, (_, index) => {
        const rawPoints = Array.isArray(stream._history[index]) ? stream._history[index] : [];
        const points = rawPoints.filter(
          (point) =>
            Number.isFinite(point?.t) &&
            Number.isFinite(point?.v) &&
            point.t >= windowStart &&
            point.t <= windowEnd
        );
        const label = stream.axis_names[index] || `ch_${index}`;
        return {
          label,
          color: CHART_COLORS[index % CHART_COLORS.length],
          enabled: isChannelEnabled(stream, index),
          points,
        };
      }).filter((item) => item.enabled && item.points.length > 0);

      function axisFrame(extra = "") {
        const xTickMarks = xTicks
          .map((tick) => {
            const ratio = (tick + GRAPH_LOOKBACK_SECONDS) / GRAPH_LOOKBACK_SECONDS;
            const x = plotLeft + ratio * plotWidth;
            return `<line x1="${x.toFixed(2)}" y1="${plotBottom}" x2="${x.toFixed(2)}" y2="${(plotBottom + 8).toFixed(2)}" stroke="${axisColor}" stroke-width="1"></line>
              <text x="${x.toFixed(2)}" y="${(plotBottom + 24).toFixed(2)}" font-size="13" text-anchor="middle" fill="${axisText}" font-weight="600">${tick}</text>`;
          })
          .join("");

        return `<svg viewBox="0 0 ${viewWidth} ${viewHeight}" preserveAspectRatio="xMidYMid meet">
          <line x1="${plotLeft}" y1="${plotTop}" x2="${plotLeft}" y2="${plotBottom}" stroke="${axisColor}" stroke-width="1.2"></line>
          <line x1="${plotLeft}" y1="${plotBottom}" x2="${plotRight}" y2="${plotBottom}" stroke="${axisColor}" stroke-width="1.2"></line>
          ${xTickMarks}
          <text x="${((plotLeft + plotRight) / 2).toFixed(2)}" y="${(plotBottom + 46).toFixed(2)}" font-size="14" text-anchor="middle" fill="${axisText}" font-weight="600">time (s)</text>
          <text x="24" y="${((plotTop + plotBottom) / 2).toFixed(2)}" transform="rotate(-90 24 ${((plotTop + plotBottom) / 2).toFixed(2)})" font-size="14" text-anchor="middle" fill="${axisText}" font-weight="600">${escapeHtml(yAxisLabel)}</text>
          ${extra}
        </svg>`;
      }

      if (!hasAnyEnabledChannel) {
        return axisFrame(`<text x="${((plotLeft + plotRight) / 2).toFixed(2)}" y="${((plotTop + plotBottom) / 2).toFixed(2)}" font-size="13" text-anchor="middle" fill="#8297ac">All channels disabled</text>`);
      }

      if (series.length === 0) {
        return axisFrame(`<text x="${((plotLeft + plotRight) / 2).toFixed(2)}" y="${((plotTop + plotBottom) / 2).toFixed(2)}" font-size="13" text-anchor="middle" fill="#8297ac">Waiting for samples in current window</text>`);
      }

      let yMin = Infinity;
      let yMax = -Infinity;
      for (const item of series) {
        for (const point of item.points) {
          if (point.v < yMin) yMin = point.v;
          if (point.v > yMax) yMax = point.v;
        }
      }

      if (!Number.isFinite(yMin) || !Number.isFinite(yMax)) {
        return axisFrame(`<text x="${((plotLeft + plotRight) / 2).toFixed(2)}" y="${((plotTop + plotBottom) / 2).toFixed(2)}" font-size="13" text-anchor="middle" fill="#8297ac">Waiting for samples in current window</text>`);
      }

      if (yMin === yMax) {
        const pad = Math.max(Math.abs(yMin) * 0.1, 1e-6);
        yMin -= pad;
        yMax += pad;
      }

      const ySpan = yMax - yMin;
      const yGrid = Array.from({ length: yTicks }, (_, index) => {
        const ratio = index / (yTicks - 1);
        const y = plotBottom - ratio * plotHeight;
        const value = yMin + ratio * ySpan;
        return `<line x1="${plotLeft}" y1="${y.toFixed(2)}" x2="${plotRight}" y2="${y.toFixed(2)}" stroke="${gridColor}" stroke-width="1"></line>
          <text x="${(plotLeft - 12).toFixed(2)}" y="${(y + 4).toFixed(2)}" font-size="12" text-anchor="end" fill="${axisText}">${escapeHtml(formatAxisNumber(value))}</text>`;
      }).join("");

      const xGrid = xTicks
        .map((tick) => {
          const ratio = (tick + GRAPH_LOOKBACK_SECONDS) / GRAPH_LOOKBACK_SECONDS;
          const x = plotLeft + ratio * plotWidth;
          return `<line x1="${x.toFixed(2)}" y1="${plotTop}" x2="${x.toFixed(2)}" y2="${plotBottom}" stroke="${gridColor}" stroke-width="1"></line>`;
        })
        .join("");

      const lineLayers = series
        .map((item) => {
          const mapped = item.points.map((point) => {
            const xRatio = (point.t - windowStart) / GRAPH_LOOKBACK_SECONDS;
            const x = plotLeft + Math.max(0, Math.min(1, xRatio)) * plotWidth;
            const y = plotBottom - ((point.v - yMin) / ySpan) * plotHeight;
            return `${x.toFixed(2)},${y.toFixed(2)}`;
          });
          if (mapped.length < 2) return "";
          const lastPoint = mapped[mapped.length - 1].split(",");
          const lastX = Number(lastPoint[0]);
          const lastY = Number(lastPoint[1]);
          return `
            <polyline points="${mapped.join(" ")}" fill="none" stroke="${item.color}" stroke-opacity="0.18" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"></polyline>
            <polyline points="${mapped.join(" ")}" fill="none" stroke="${item.color}" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"></polyline>
            <circle cx="${lastX.toFixed(2)}" cy="${lastY.toFixed(2)}" r="2.2" fill="${item.color}" fill-opacity="0.95"></circle>`;
        })
        .join("");

      return axisFrame(`${yGrid}${xGrid}${lineLayers}`);
    }

    function renderStreams() {
      const streams = [...state.streams.values()].sort((a, b) => {
        const keyA = `${a.device_name || ""}|${a.device_channel || ""}|${a.sensor_name || ""}`.toLowerCase();
        const keyB = `${b.device_name || ""}|${b.device_channel || ""}|${b.sensor_name || ""}`.toLowerCase();
        return keyA.localeCompare(keyB);
      });

      if (streams.length === 0) {
        devicesEl.hidden = true;
        emptyEl.hidden = false;
        return;
      }

      devicesEl.hidden = false;
      emptyEl.hidden = true;

      const deviceGroups = new Map();
      streams.forEach((stream) => {
        const key = `${stream.device_name || "unknown"}|${stream.device_channel || ""}|${stream.source || "unknown"}`.toLowerCase();
        if (!deviceGroups.has(key)) {
          deviceGroups.set(key, {
            device_name: stream.device_name || "unknown",
            device_channel: stream.device_channel || "",
            source: stream.source || "unknown",
            streams: [],
          });
        }
        deviceGroups.get(key).streams.push(stream);
      });

      const groups = [...deviceGroups.values()].sort((a, b) => {
        const keyA = `${a.device_name}|${a.device_channel}|${a.source}`.toLowerCase();
        const keyB = `${b.device_name}|${b.device_channel}|${b.source}`.toLowerCase();
        return keyA.localeCompare(keyB);
      });

      devicesEl.innerHTML = groups
        .map((group) => {
          const sideValue = String(group.device_channel || "").trim().toUpperCase();
          const sideBadge = sideValue ? `<span class="channel-badge">${escapeHtml(sideValue.slice(0, 1))}</span>` : "";
          const title = `${group.device_name}`;
          const streamCount = group.streams.length;
          const streamLabel = streamCount === 1 ? "sensor stream" : "sensor streams";

          const streamRows = group.streams
            .sort((a, b) => (a.sensor_name || "").toLowerCase().localeCompare((b.sensor_name || "").toLowerCase()))
            .map((stream) => {
              const chart = streamChartSvg(stream, streamWindowEnd(stream));
              const legend = channelLegend(stream);
              return `<article class="stream-row">
                <div class="stream-head">
                  <h3 class="stream-title">${escapeHtml(stream.sensor_name || stream.stream_name || "Unknown stream")}</h3>
                </div>
                ${legend}
                <div class="chart-wrap">${chart}</div>
              </article>`;
            })
            .join("");

          return `<section class="device-section">
            <div class="device-header">
              <h2 class="device-title">${escapeHtml(title)}${sideBadge}</h2>
              <div class="device-meta">${escapeHtml(group.source)} · ${streamCount} ${streamLabel}</div>
            </div>
            <div class="sensor-grid">${streamRows}</div>
          </section>`;
        })
        .join("");
    }

    function applySnapshot(snapshot) {
      if (snapshot && snapshot.title) {
        titleEl.textContent = snapshot.title;
        document.title = snapshot.title;
      }

      state.packetsReceived = Number(snapshot.packets_received || 0);
      state.lastPacketWallTime = snapshot.last_packet_wall_time ?? null;
      state.udpHost = String(snapshot.udp_host || state.udpHost || "");
      state.udpPort = Number(snapshot.udp_port || state.udpPort || 0);
      state.streams.clear();

      const streams = Array.isArray(snapshot.streams) ? snapshot.streams : [];
      streams.forEach((stream) => {
        if (!stream || !stream.source_id) return;
        const normalized = normalizeStream(stream);
        state.streams.set(normalized.source_id, normalized);
      });

      const recentEvents = Array.isArray(snapshot.recent_events) ? snapshot.recent_events : [];
      recentEvents
        .slice()
        .sort((a, b) => sampleTimelineTimeSeconds(a) - sampleTimelineTimeSeconds(b))
        .forEach((sample) => {
          if (!sample || !sample.source_id) return;
          const stream = upsertStreamFromSample(sample);
          if (!stream) return;
          mergeSampleIntoStream(stream, sample, false);
        });

      scheduleRender(true);
    }

    function applySampleEvent(payload) {
      state.packetsReceived = Number(payload.packets_received || 0);
      state.lastPacketWallTime = payload.last_packet_wall_time ?? null;

      const sample = payload.sample;
      if (sample && sample.source_id) {
        const stream = upsertStreamFromSample(sample);
        if (stream) {
          mergeSampleIntoStream(stream, sample, true);
        }
      }

      scheduleRender(false);
    }

    devicesEl.addEventListener("change", (event) => {
      const target = event.target;
      if (!(target instanceof HTMLInputElement) || !target.classList.contains("legend-check")) {
        return;
      }

      const sourceId = target.getAttribute("data-source-id");
      const channelIndex = Number(target.getAttribute("data-channel-index"));
      if (!sourceId || !Number.isInteger(channelIndex) || channelIndex < 0) {
        return;
      }

      const stream = state.streams.get(sourceId);
      if (!stream) {
        return;
      }
      setChannelEnabled(stream, channelIndex, target.checked);
      scheduleRender(true);
    });

    const eventSource = new EventSource("/events");

    eventSource.addEventListener("snapshot", (event) => {
      try {
        applySnapshot(JSON.parse(event.data));
      } catch (error) {
        console.error("Failed to parse snapshot", error);
      }
    });

    eventSource.addEventListener("sample", (event) => {
      try {
        applySampleEvent(JSON.parse(event.data));
      } catch (error) {
        console.error("Failed to parse sample", error);
      }
    });

    eventSource.onerror = () => {
      statusEl.className = "status-pill waiting";
      statusEl.textContent = "DISCONNECTED";
    };

    setInterval(updateStatus, 1000);
    scheduleRender(true);
  </script>
</body>
</html>
"""


def main() -> int:
    args = parse_args()

    if args.port < 1 or args.port > 65535:
        print(f"Invalid UDP port: {args.port}", file=sys.stderr)
        return 2
    if args.dashboard_port < 1 or args.dashboard_port > 65535:
        print(f"Invalid dashboard port: {args.dashboard_port}", file=sys.stderr)
        return 2
    if args.max_events < 1:
        print("--max-events must be > 0", file=sys.stderr)
        return 2

    try:
        app = LslBridgeApp(args)
    except OSError as exc:
        print(
            "Failed to bind bridge sockets "
            f"(udp={args.host}:{args.port}, dashboard={args.dashboard_host}:{args.dashboard_port}): {exc}",
            file=sys.stderr,
        )
        return 2

    try:
        app.run()
    except KeyboardInterrupt:
        print("\nStopping bridge...")
    finally:
        app.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
