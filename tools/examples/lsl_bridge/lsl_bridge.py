#!/usr/bin/env python3
"""
OpenWearables LSL bridge example.

Receives UDP JSON sensor packets through the shared NetworkRelayServer and
publishes one LSL outlet per OpenWearables stream.
"""

from __future__ import annotations

import argparse
import socket
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

TOOLS_DIR = Path(__file__).resolve().parents[2]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from network_relay_server import (  # noqa: E402
    NetworkRelayServer,
    UdpSensorSample,
    clean_text,
)

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


@dataclass
class SensorClockAlignment:
    sensor_zero_seconds: float
    lsl_zero_seconds: float
    last_lsl_seconds: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Receive OpenWearables UDP sensor packets and publish them as "
            "LSL outlets."
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
        "--poll-interval",
        type=float,
        default=0.25,
        help="Polling interval for UDP relay loop in seconds (default: 0.25).",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print every bridged sample.",
    )
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
        stream_type="OpenWearables",
        channel_count=len(sample.values),
        source_id=sample.stream.source_id,
        device_name=sample.stream.device.name,
        device_channel=sample.stream.device.channel,
        sensor_name=sample.stream.sensor_name,
        source=sample.stream.device.source,
    )


def _create_outlet(sample: UdpSensorSample, values: List[float]) -> StreamOutlet:
    spec = _stream_spec(sample)
    device_token = clean_text(
        sample.raw.get("device_token") or sample.raw.get("device_id"),
        "unknown_device",
    )
    axis_names = list(sample.axis_names)
    axis_units = list(sample.axis_units)

    info = StreamInfo(
        name=spec.name,
        type=spec.stream_type,
        channel_count=len(values),
        nominal_srate=0.0,
        channel_format="float32",
        source_id=spec.source_id,
    )

    desc = info.desc()
    desc.append_child_value("manufacturer", "OpenWearables")
    desc.append_child_value("device_token", device_token)
    desc.append_child_value("device_name", spec.device_name)
    desc.append_child_value("device_channel", spec.device_channel)
    if spec.device_channel:
        desc.append_child_value("device_side", spec.device_channel)
    desc.append_child_value("device_source", spec.source)
    desc.append_child_value("sensor_name", spec.sensor_name)
    desc.append_child_value("source_id", spec.source_id)
    desc.append_child_value("timestamp_exponent", str(sample.timestamp_exponent or -3))

    channels = desc.append_child("channels")
    for idx in range(len(values)):
        ch = channels.append_child("channel")
        label = axis_names[idx] if idx < len(axis_names) else f"ch_{idx}"
        if spec.device_channel:
            label = f"{spec.device_channel}-{label}"
        unit = axis_units[idx] if idx < len(axis_units) else ""
        ch.append_child_value("label", str(label))
        ch.append_child_value("unit", str(unit))
        ch.append_child_value("type", spec.sensor_name)

    return StreamOutlet(info)


class LslBridgeApp:
    def __init__(self, args: argparse.Namespace) -> None:
        self._args = args
        self._relay_server = NetworkRelayServer(
            host=args.host,
            port=args.port,
            on_warning=print,
        )
        self._relay_server.add_sample_listener(self._on_sample)

        self._outlets: Dict[StreamSpec, StreamOutlet] = {}
        self._clock_alignment: Dict[StreamSpec, SensorClockAlignment] = {}

        self._print_startup()

    def _print_startup(self) -> None:
        udp_ips = _candidate_ips(self._args.host)
        selected_udp_ip = udp_ips[0]

        print("")
        print("OpenWearables LSL Bridge started.")
        print(f"Listening for UDP packets on {self._args.host}:{self._relay_server.port}")
        print("Use one of these IPs in your Flutter app:")
        for ip in udp_ips:
            marker = " (recommended)" if ip == selected_udp_ip else ""
            print(f"  - {ip}{marker}")

        print("")
        print("Example app setup:")
        print("  final udpBridgeForwarder = UdpBridgeForwarder.instance;")
        print(
            "  udpBridgeForwarder.configure("
            f"host: '{selected_udp_ip}', port: {self._relay_server.port}, enabled: true);"
        )
        print("  WearableManager().addSensorForwarder(udpBridgeForwarder);")
        print("")
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

    def _on_sample(self, sample: UdpSensorSample, remote: tuple[str, int]) -> None:
        _ = remote
        values = list(sample.values)
        spec = _stream_spec(sample)
        lsl_timestamp = self._lsl_timestamp_for_sample(spec, sample.timestamp_seconds)

        outlet = self._outlets.get(spec)
        if outlet is None:
            outlet = _create_outlet(sample, values)
            self._outlets[spec] = outlet
            print(
                "Created LSL outlet: "
                f"name='{spec.name}', channels={spec.channel_count}, source_id='{spec.source_id}'"
            )

        outlet.push_sample(values, lsl_timestamp)

        if self._args.verbose:
            print(
                f"Sample {spec.name}: {values} "
                f"(device_ts={sample.timestamp}, lsl_ts={lsl_timestamp:.6f})"
            )

    def run(self) -> None:
        self._relay_server.run(poll_interval=self._args.poll_interval)

    def close(self) -> None:
        self._relay_server.close()


def main() -> int:
    args = parse_args()

    if args.port < 1 or args.port > 65535:
        print(f"Invalid UDP port: {args.port}", file=sys.stderr)
        return 2
    if args.poll_interval <= 0:
        print("--poll-interval must be > 0", file=sys.stderr)
        return 2

    try:
        app = LslBridgeApp(args)
    except OSError as exc:
        print(
            f"Failed to bind UDP socket ({args.host}:{args.port}): {exc}",
            file=sys.stderr,
        )
        return 2

    try:
        app.run()
    except KeyboardInterrupt:
        print("\nStopping LSL bridge...")
    finally:
        app.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
