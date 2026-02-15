#!/usr/bin/env python3
"""
OpenWearables network relay minimal example.

This example focuses on the core flow:
1) run the reusable UDP network relay server
2) map each packet to a concrete device + sensor sample
3) split each sample into concrete sensor channels

Replace the two placeholder hooks at the bottom with your own logic.
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import List, Optional, Tuple

from network_relay_server import DeviceInfo, NetworkRelayServer, UdpSensorSample


@dataclass(frozen=True)
class SensorChannel:
    index: int
    name: str
    unit: str


@dataclass(frozen=True)
class SensorSample:
    device: DeviceInfo
    sensor_name: str
    timestamp: float
    values: Tuple[float, ...]
    channels: Tuple[SensorChannel, ...]


@dataclass(frozen=True)
class ChannelSample:
    device: DeviceInfo
    sensor_name: str
    channel: SensorChannel
    timestamp: float
    value: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Minimal network relay receiver for OpenWearables UDP packets."
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="UDP bind host (default: 0.0.0.0).",
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
        help="Polling interval in seconds (default: 0.25).",
    )
    return parser.parse_args()


def _channels_from_sample(sample: UdpSensorSample) -> Tuple[SensorChannel, ...]:
    channels: List[SensorChannel] = []
    for index in range(len(sample.values)):
        name = sample.axis_names[index] if index < len(sample.axis_names) else f"ch_{index}"
        unit = sample.axis_units[index] if index < len(sample.axis_units) else ""
        channels.append(SensorChannel(index=index, name=str(name), unit=str(unit)))
    return tuple(channels)


def to_sensor_sample(sample: UdpSensorSample) -> SensorSample:
    timestamp_seconds: Optional[float] = sample.timestamp_seconds
    if timestamp_seconds is None:
        timestamp_seconds = time.time()
    return SensorSample(
        device=sample.stream.device,
        sensor_name=sample.stream.sensor_name,
        timestamp=float(timestamp_seconds),
        values=sample.values,
        channels=_channels_from_sample(sample),
    )


def split_channels(sample: SensorSample) -> List[ChannelSample]:
    items: List[ChannelSample] = []
    for index, value in enumerate(sample.values):
        if index < len(sample.channels):
            channel = sample.channels[index]
        else:
            channel = SensorChannel(index=index, name=f"ch_{index}", unit="")
        items.append(
            ChannelSample(
                device=sample.device,
                sensor_name=sample.sensor_name,
                channel=channel,
                timestamp=sample.timestamp,
                value=value,
            )
        )
    return items


def handle_sensor_sample(sample: SensorSample) -> None:
    """
    Placeholder #1: handle the full multi-channel sensor sample.
    """
    device = sample.device
    side = f"[{device.channel}] " if device.channel else ""
    print(
        f"{device.name} {side}{sample.sensor_name} "
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

    if args.poll_interval <= 0:
        print("--poll-interval must be > 0", file=sys.stderr)
        return 2

    server = NetworkRelayServer(host=args.host, port=args.port, on_warning=print)

    def _on_udp_sample(raw_sample: UdpSensorSample, remote: tuple[str, int]) -> None:
        _ = remote
        sample = to_sensor_sample(raw_sample)
        handle_sensor_sample(sample)
        for channel_sample in split_channels(sample):
            handle_channel_sample(channel_sample)

    server.add_sample_listener(_on_udp_sample)

    print(f"Listening for OpenWearables UDP packets on {args.host}:{server.port}")
    print("Press Ctrl+C to stop.")

    try:
        server.run(poll_interval=args.poll_interval)
    except KeyboardInterrupt:
        print("\nStopping minimal receiver...")
    finally:
        server.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
