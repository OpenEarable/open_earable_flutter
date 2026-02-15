#!/usr/bin/env python3
"""
OpenEarable UDP -> LSL bridge.

Receives UDP JSON packets from the open_earable_flutter package and publishes
them as LSL streams.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
from dataclasses import dataclass
from typing import Dict, List

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Receive OpenEarable UDP sensor packets and publish LSL streams."
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
        "--verbose",
        action="store_true",
        help="Print every received sample.",
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

    # This usually resolves the primary outbound interface without sending data.
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


def _create_outlet(sample: dict, values: List[float]) -> StreamOutlet:
    stream_name = str(sample.get("stream_name", "OpenEarable_Unknown"))
    device_id = str(sample.get("device_id", "unknown_device"))
    sensor_name = str(sample.get("sensor_name", "unknown_sensor"))
    axis_names = sample.get("axis_names") or []
    axis_units = sample.get("axis_units") or []

    info = StreamInfo(
        name=stream_name,
        type="OpenEarable",
        channel_count=len(values),
        nominal_srate=0.0,  # irregular
        channel_format="float32",
        source_id=f"{device_id}:{sensor_name}",
    )

    desc = info.desc()
    desc.append_child_value("manufacturer", "OpenEarable")
    desc.append_child_value("device_id", device_id)
    desc.append_child_value("device_name", str(sample.get("device_name", "")))
    desc.append_child_value("sensor_name", sensor_name)
    desc.append_child_value(
        "timestamp_exponent", str(sample.get("timestamp_exponent", -3))
    )

    channels = desc.append_child("channels")
    for idx in range(len(values)):
        ch = channels.append_child("channel")
        label = axis_names[idx] if idx < len(axis_names) else f"ch_{idx}"
        unit = axis_units[idx] if idx < len(axis_units) else ""
        ch.append_child_value("label", str(label))
        ch.append_child_value("unit", str(unit))
        ch.append_child_value("type", sensor_name)

    return StreamOutlet(info)


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
    stream_name = str(sample.get("stream_name", "OpenEarable_Unknown"))
    device_id = str(sample.get("device_id", "unknown_device"))
    sensor_name = str(sample.get("sensor_name", "unknown_sensor"))
    source_id = f"{device_id}:{sensor_name}"
    return StreamSpec(
        name=stream_name,
        stream_type="OpenEarable",
        channel_count=len(values),
        source_id=source_id,
    )


def main() -> int:
    args = parse_args()

    if args.port < 1 or args.port > 65535:
        print(f"Invalid port: {args.port}", file=sys.stderr)
        return 2

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.host, args.port))

    ips = _candidate_ips(args.host)
    print("")
    print("OpenEarable LSL bridge started.")
    print(f"Listening for UDP packets on {args.host}:{args.port}")
    print("Use one of these IPs in your Flutter app:")
    for ip in ips:
        print(f"  - {ip}")
    print("")
    print("Example app setup:")
    print("  final lslForwarder = LslForwarder.instance;")
    print(
        f"  lslForwarder.configure(host: '{ips[0]}', port: {args.port}, enabled: true);"
    )
    print("  WearableManager().addSensorForwarder(lslForwarder);")
    print("")
    print("Waiting for sensor packets...")

    outlets: Dict[StreamSpec, StreamOutlet] = {}

    try:
        while True:
            packet, remote = sock.recvfrom(65535)
            try:
                sample = json.loads(packet.decode("utf-8"))
            except json.JSONDecodeError:
                print(f"Ignoring non-JSON packet from {remote[0]}:{remote[1]}")
                continue

            if not isinstance(sample, dict):
                print(f"Ignoring unexpected payload type from {remote[0]}:{remote[1]}")
                continue

            if sample.get("type") != "open_earable_lsl_sample":
                continue

            values = _parse_values(sample)
            if not values:
                continue

            spec = _stream_spec(sample, values)

            outlet = outlets.get(spec)
            if outlet is None:
                outlet = _create_outlet(sample, values)
                outlets[spec] = outlet
                print(
                    "Created LSL outlet: "
                    f"name='{spec.name}', channels={spec.channel_count}, source_id='{spec.source_id}'"
                )

            outlet.push_sample(values, local_clock())

            if args.verbose:
                print(
                    f"Sample {spec.name}: {values} "
                    f"(device_ts={sample.get('timestamp')})"
                )
    except KeyboardInterrupt:
        print("\nStopping bridge...")
    finally:
        sock.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
