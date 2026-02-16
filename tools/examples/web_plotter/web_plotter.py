#!/usr/bin/env python3
"""
OpenWearables web plotter example.

Receives UDP JSON sensor packets from open_earable_flutter through the shared
NetworkRelayServer and serves a live web dashboard (SSE + static HTML).
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import socket
import sys
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Optional, Set

TOOLS_DIR = Path(__file__).resolve().parents[2]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from network_relay_server import NetworkRelayServer, UdpSensorSample  # noqa: E402


DEFAULT_DASHBOARD_PORT = 8765
DEFAULT_MAX_EVENTS = 300

DASHBOARD_TITLE = "OpenWearables Web Plotter"

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
    channel_count: int
    source_id: str
    device_name: str
    device_channel: str
    sensor_name: str
    source: str


@dataclass
class SensorClockAlignment:
    sensor_zero_seconds: float
    wall_zero_seconds: float
    last_wall_seconds: float


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
        plot_timestamp: float,
    ) -> None:
        now = time.time()
        relay_name = str(sample.get("stream_prefix") or "").strip()
        payload = {
            "stream_name": spec.name,
            "source_id": spec.source_id,
            "device_name": spec.device_name,
            "device_channel": spec.device_channel,
            "sensor_name": spec.sensor_name,
            "source": spec.source,
            "relay_name": relay_name,
            "values": values,
            "axis_names": sample.get("axis_names") or [],
            "axis_units": sample.get("axis_units") or [],
            "timestamp": sample.get("timestamp"),
            "timestamp_exponent": sample.get("timestamp_exponent"),
            # Kept for compatibility with the existing dashboard UI payload shape.
            "lsl_timestamp": plot_timestamp,
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
                    "relay_name": relay_name,
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
            stream_item["relay_name"] = relay_name
            stream_item["last_lsl_timestamp"] = plot_timestamp
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
    dashboard_html_path: Path

    def do_GET(self) -> None:  # noqa: N802 - stdlib API
        if self.path in ("/", "/index.html"):
            try:
                body = self.dashboard_html_path.read_bytes()
            except OSError as exc:
                self.send_error(500, f"Failed to load dashboard HTML: {exc}")
                return

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
            "Receive OpenWearables UDP sensor packets and serve a live web "
            "plotting dashboard."
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
        "--poll-interval",
        type=float,
        default=0.25,
        help="Polling interval for UDP relay loop in seconds (default: 0.25).",
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


def _stream_spec(sample: UdpSensorSample) -> StreamSpec:
    return StreamSpec(
        name=sample.stream.name,
        channel_count=len(sample.values),
        source_id=sample.stream.source_id,
        device_name=sample.stream.device.name,
        device_channel=sample.stream.device.channel,
        sensor_name=sample.stream.sensor_name,
        source=sample.stream.device.source,
    )


class WebPlotterApp:
    def __init__(self, args: argparse.Namespace) -> None:
        self._args = args
        self._relay_server = NetworkRelayServer(
            host=args.host,
            port=args.port,
            on_warning=print,
        )
        self._relay_server.add_sample_listener(self._on_sample)
        self._clock_alignment: Dict[StreamSpec, SensorClockAlignment] = {}

        self._dashboard_state = DashboardState(
            max_events=args.max_events,
            udp_host=args.host,
            udp_port=self._relay_server.port,
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
            name="openwearables-web-plotter",
        )

        self._print_startup()

    def _handler_class(self) -> type[DashboardRequestHandler]:
        dashboard_state = self._dashboard_state
        stop_event = self._stop_event
        dashboard_html_path = Path(__file__).with_name("dashboard.html")

        class Handler(DashboardRequestHandler):
            pass

        Handler.dashboard_state = dashboard_state
        Handler.stop_event = stop_event
        Handler.dashboard_html_path = dashboard_html_path
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
        print(_styled("OpenWearables Web Plotter started.", ANSI_BOLD, ANSI_CYAN))
        print(
            _styled(
                f"Listening for UDP packets on {self._args.host}:{self._relay_server.port}",
                ANSI_GREEN,
            )
        )
        print(_styled("Use one of these IPs in your Flutter app:", ANSI_BOLD))
        for ip in udp_ips:
            marker = " (recommended)" if ip == selected_udp_ip else ""
            print(f"  - {_styled(ip, ANSI_YELLOW)}{marker}")

        print("")
        print(_styled("Example app setup:", ANSI_BOLD))
        print(_styled("  final udpBridgeForwarder = UdpBridgeForwarder.instance;", ANSI_DIM))
        print(
            _styled(
                f"  udpBridgeForwarder.configure(host: '{selected_udp_ip}', port: {self._relay_server.port}, enabled: true);",
                ANSI_DIM,
            )
        )
        print(_styled("  WearableManager().addSensorForwarder(udpBridgeForwarder);", ANSI_DIM))

        print("")
        print(_styled("Web dashboard URLs:", ANSI_BOLD))
        for ip in dashboard_ips:
            marker = " (recommended)" if ip == dashboard_ips[0] else ""
            print(f"  - http://{ip}:{self._args.dashboard_port}{marker}")

        print("")
        print(f"Open your browser to {dashboard_url}")
        print("Press Ctrl+C to stop.")

    def _plot_timestamp_for_sample(
        self, spec: StreamSpec, sensor_time_seconds: Optional[float]
    ) -> float:
        if sensor_time_seconds is None:
            return time.time()

        alignment = self._clock_alignment.get(spec)
        if alignment is None:
            now = time.time()
            self._clock_alignment[spec] = SensorClockAlignment(
                sensor_zero_seconds=sensor_time_seconds,
                wall_zero_seconds=now,
                last_wall_seconds=now,
            )
            return now

        plot_time = alignment.wall_zero_seconds + (
            sensor_time_seconds - alignment.sensor_zero_seconds
        )
        if plot_time <= alignment.last_wall_seconds:
            plot_time = alignment.last_wall_seconds + 1e-6
        alignment.last_wall_seconds = plot_time
        return plot_time

    def _on_sample(self, sample: UdpSensorSample, remote: tuple[str, int]) -> None:
        _ = remote
        values = list(sample.values)
        spec = _stream_spec(sample)
        plot_timestamp = self._plot_timestamp_for_sample(spec, sample.timestamp_seconds)

        self._dashboard_state.record_sample(spec, values, sample.raw, plot_timestamp)

        if self._args.verbose:
            print(
                f"Sample {spec.name}: {values} "
                f"(device_ts={sample.timestamp}, plot_ts={plot_timestamp:.6f})"
            )

    def run(self) -> None:
        self._dashboard_thread.start()
        self._relay_server.run(
            stop_event=self._stop_event,
            poll_interval=self._args.poll_interval,
        )

    def close(self) -> None:
        self._stop_event.set()
        try:
            self._dashboard_server.shutdown()
            self._dashboard_server.server_close()
        except Exception:
            pass
        self._relay_server.close()


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
    if args.poll_interval <= 0:
        print("--poll-interval must be > 0", file=sys.stderr)
        return 2
    if not Path(__file__).with_name("dashboard.html").is_file():
        print("Missing dashboard.html next to web_plotter.py", file=sys.stderr)
        return 2

    try:
        app = WebPlotterApp(args)
    except OSError as exc:
        print(
            "Failed to bind plotter sockets "
            f"(udp={args.host}:{args.port}, dashboard={args.dashboard_host}:{args.dashboard_port}): {exc}",
            file=sys.stderr,
        )
        return 2

    try:
        app.run()
    except KeyboardInterrupt:
        print("\nStopping web plotter...")
    finally:
        app.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
