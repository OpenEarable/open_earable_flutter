#!/usr/bin/env python3
"""
OpenWearables LSL receiver minimal example.

This example focuses on the core flow:
1) receive LSL sensor samples
2) map each stream to a concrete device + sensor
3) split each sample into concrete sensor channels

Replace the two placeholder hooks at the bottom with your own logic.
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple
from urllib.parse import unquote

try:
    from pylsl import StreamInfo, StreamInlet, resolve_byprop
except ImportError as exc:  # pragma: no cover - import guard
    print(
        "Missing dependency: pylsl.\n"
        "Install with:\n"
        "  pip install pylsl",
        file=sys.stderr,
    )
    raise SystemExit(2) from exc


SOURCE_ID_PREFIX = "oe-v1"


@dataclass(frozen=True)
class DeviceRef:
    name: str
    channel: str
    source: str


@dataclass(frozen=True)
class SensorChannel:
    index: int
    name: str
    unit: str


@dataclass(frozen=True)
class SensorStreamRef:
    stream_name: str
    source_id: str
    sensor_name: str
    device: DeviceRef
    channels: Tuple[SensorChannel, ...]


@dataclass(frozen=True)
class SensorSample:
    stream: SensorStreamRef
    timestamp: float
    values: Tuple[float, ...]


@dataclass(frozen=True)
class ChannelSample:
    device: DeviceRef
    sensor_name: str
    channel: SensorChannel
    timestamp: float
    value: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Minimal LSL receiver for OpenWearables streams."
    )
    parser.add_argument(
        "--stream-type",
        default="OpenWearables",
        help="LSL stream type to resolve (default: OpenWearables).",
    )
    parser.add_argument(
        "--resolve-timeout",
        type=float,
        default=5.0,
        help="Timeout in seconds for stream discovery (default: 5.0).",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=0.02,
        help="Polling interval in seconds (default: 0.02).",
    )
    return parser.parse_args()


def _clean_text(value: object, fallback: str = "") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    return text if text else fallback


def _safe_decode_component(value: str) -> str:
    if value == "-":
        return ""
    try:
        return _clean_text(unquote(value), "")
    except Exception:
        return _clean_text(value, "")


def _decode_source_id(source_id: str) -> Optional[dict]:
    parts = source_id.split(":")
    if len(parts) != 5 or parts[0] != SOURCE_ID_PREFIX:
        return None
    return {
        "device_name": _safe_decode_component(parts[1]),
        "device_channel": _safe_decode_component(parts[2]),
        "sensor_name": _safe_decode_component(parts[3]),
        "source": _safe_decode_component(parts[4]),
    }


def _channel_from_desc(
    info: StreamInfo, channel_count: int
) -> Tuple[SensorChannel, ...]:
    channels: List[SensorChannel] = []
    labels: List[str] = []
    units: List[str] = []

    try:
        channels_root = info.desc().child("channels")
        channel_node = channels_root.child("channel")
        while not channel_node.empty() and len(labels) < channel_count:
            labels.append(_clean_text(channel_node.child_value("label"), ""))
            units.append(_clean_text(channel_node.child_value("unit"), ""))
            channel_node = channel_node.next_sibling("channel")
    except Exception:
        labels = []
        units = []

    for index in range(channel_count):
        label = labels[index] if index < len(labels) and labels[index] else f"ch_{index}"
        unit = units[index] if index < len(units) else ""
        channels.append(SensorChannel(index=index, name=label, unit=unit))
    return tuple(channels)


def build_stream_ref(info: StreamInfo) -> SensorStreamRef:
    source_id = _clean_text(info.source_id(), "")
    decoded = _decode_source_id(source_id) if source_id else None

    name = _clean_text(info.name(), "unknown_stream")
    sensor_name = _clean_text(decoded.get("sensor_name") if decoded else "", "")
    if not sensor_name:
        sensor_name = name

    device = DeviceRef(
        name=_clean_text(decoded.get("device_name") if decoded else "", "unknown_device"),
        channel=_clean_text(decoded.get("device_channel") if decoded else "", ""),
        source=_clean_text(decoded.get("source") if decoded else "", "unknown_source"),
    )

    channel_count = int(info.channel_count() or 0)
    channels = _channel_from_desc(info, channel_count)

    return SensorStreamRef(
        stream_name=name,
        source_id=source_id,
        sensor_name=sensor_name,
        device=device,
        channels=channels,
    )


def to_sensor_sample(
    stream_ref: SensorStreamRef, timestamp: float, values: Sequence[float]
) -> SensorSample:
    parsed_values: List[float] = []
    for value in values:
        try:
            parsed_values.append(float(value))
        except (TypeError, ValueError):
            parsed_values.append(float("nan"))
    return SensorSample(
        stream=stream_ref,
        timestamp=float(timestamp),
        values=tuple(parsed_values),
    )


def split_channels(sample: SensorSample) -> List[ChannelSample]:
    items: List[ChannelSample] = []
    for index, value in enumerate(sample.values):
        if index < len(sample.stream.channels):
            channel = sample.stream.channels[index]
        else:
            channel = SensorChannel(index=index, name=f"ch_{index}", unit="")
        items.append(
            ChannelSample(
                device=sample.stream.device,
                sensor_name=sample.stream.sensor_name,
                channel=channel,
                timestamp=sample.timestamp,
                value=value,
            )
        )
    return items


def handle_sensor_sample(sample: SensorSample) -> None:
    """
    Placeholder #1: handle full multi-channel sensor sample.
    """
    device = sample.stream.device
    side = f"[{device.channel}] " if device.channel else ""
    print(
        f"{device.name} {side}{sample.stream.sensor_name} "
        f"ts={sample.timestamp:.6f} values={list(sample.values)}"
    )


def handle_channel_sample(channel_sample: ChannelSample) -> None:
    """
    Placeholder #2: handle each concrete channel value.

    Example:
    - route channel_sample.device.name to per-device pipelines
    - map channel_sample.sensor_name + channel_sample.channel.name
      to custom processing
    """
    # Intentionally empty. Add your channel-specific logic here.
    return


def main() -> int:
    args = parse_args()

    if args.resolve_timeout <= 0:
        print("--resolve-timeout must be > 0", file=sys.stderr)
        return 2
    if args.poll_interval <= 0:
        print("--poll-interval must be > 0", file=sys.stderr)
        return 2

    print(
        f"Resolving LSL streams where type='{args.stream_type}' "
        f"(timeout={args.resolve_timeout}s)..."
    )
    stream_infos = resolve_byprop(
        prop="type",
        value=args.stream_type,
        timeout=args.resolve_timeout,
    )

    if not stream_infos:
        print(
            "No matching streams found. Start the OpenWearables bridge first and try again.",
            file=sys.stderr,
        )
        return 1

    inlets: List[Tuple[StreamInlet, SensorStreamRef]] = []
    for info in stream_infos:
        inlet = StreamInlet(info)
        stream_ref = build_stream_ref(info)
        inlets.append((inlet, stream_ref))
        device = stream_ref.device
        side = f"[{device.channel}]" if device.channel else ""
        print(
            f"Connected: {stream_ref.stream_name} "
            f"(device={device.name}{side}, sensor={stream_ref.sensor_name}, "
            f"channels={len(stream_ref.channels)})"
        )

    print(f"Reading from {len(inlets)} stream(s). Press Ctrl+C to stop.")

    try:
        while True:
            for inlet, stream_ref in inlets:
                values, timestamp = inlet.pull_sample(timeout=0.0)
                if values is None:
                    continue

                sample = to_sensor_sample(stream_ref, timestamp, values)
                handle_sensor_sample(sample)
                for channel_sample in split_channels(sample):
                    handle_channel_sample(channel_sample)
            time.sleep(args.poll_interval)
    except KeyboardInterrupt:
        print("\nStopping minimal receiver...")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
