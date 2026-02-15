#!/usr/bin/env python3
"""
Reusable OpenWearables network relay server.

This module provides:
- parsing helpers for OpenWearables UDP sample packets
- lightweight device/stream/sample abstractions
- a reusable UDP relay server (`NetworkRelayServer`) that receives packets,
  answers probe pings, and emits parsed samples to listeners
"""

from __future__ import annotations

import json
import select
import socket
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Mapping, Optional, Tuple
from urllib.parse import quote, unquote


UDP_PACKET_TYPE_SAMPLE = "open_earable_udp_sample"
UDP_PACKET_TYPE_PROBE = "open_earable_udp_probe"
UDP_PACKET_TYPE_PROBE_ACK = "open_earable_udp_probe_ack"

SOURCE_ID_PREFIX = "oe-v1"
SOURCE_ID_EMPTY_COMPONENT = "-"

MAX_UDP_PACKET_SIZE = 65535

SampleListener = Callable[["UdpSensorSample", Tuple[str, int]], None]
WarningListener = Callable[[str], None]


@dataclass(frozen=True)
class DeviceInfo:
    name: str
    channel: str
    source: str


@dataclass(frozen=True)
class StreamInfo:
    name: str
    source_id: str
    sensor_name: str
    device: DeviceInfo


@dataclass(frozen=True)
class UdpSensorSample:
    stream: StreamInfo
    values: Tuple[float, ...]
    axis_names: Tuple[str, ...]
    axis_units: Tuple[str, ...]
    timestamp: Any
    timestamp_exponent: Any
    timestamp_seconds: Optional[float]
    raw: Dict[str, Any]


def clean_text(value: object, fallback: str = "") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    if not text:
        return fallback
    return " ".join(text.split())


def normalize_channel(value: object) -> str:
    channel = clean_text(value, "")
    if not channel:
        return ""
    lower = channel.lower()
    if lower.startswith("l"):
        return "L"
    if lower.startswith("r"):
        return "R"
    return channel


def _encode_source_component(value: str) -> str:
    cleaned = clean_text(value, "")
    if not cleaned:
        return SOURCE_ID_EMPTY_COMPONENT
    return quote(cleaned, safe="")


def _decode_source_component(value: str) -> str:
    if value == SOURCE_ID_EMPTY_COMPONENT:
        return ""
    return clean_text(unquote(value), "")


def encode_source_id(
    *,
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


def decode_source_id(source_id: str) -> Optional[Dict[str, str]]:
    parts = source_id.split(":")
    if len(parts) != 5 or parts[0] != SOURCE_ID_PREFIX:
        return None
    return {
        "device_name": _decode_source_component(parts[1]),
        "device_channel": _decode_source_component(parts[2]),
        "sensor_name": _decode_source_component(parts[3]),
        "source": _decode_source_component(parts[4]),
    }


def build_stream_name(
    *,
    device_name: str,
    device_channel: str,
    sensor_name: str,
    source: str,
) -> str:
    channel_suffix = f" [{device_channel}]" if device_channel else ""
    return f"{device_name}{channel_suffix} ({source}) - {sensor_name}"


def parse_values(payload: Mapping[str, Any]) -> Tuple[float, ...]:
    raw_values = payload.get("values")
    if not isinstance(raw_values, list):
        return tuple()
    parsed: List[float] = []
    for value in raw_values:
        try:
            parsed.append(float(value))
        except (TypeError, ValueError):
            continue
    return tuple(parsed)


def _string_list(value: Any) -> Tuple[str, ...]:
    if not isinstance(value, list):
        return tuple()
    return tuple(str(item if item is not None else "") for item in value)


def sensor_timestamp_seconds(payload: Mapping[str, Any]) -> Optional[float]:
    raw_timestamp = payload.get("timestamp")
    raw_exponent = payload.get("timestamp_exponent")
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


def parse_sensor_sample(payload: Mapping[str, Any]) -> Optional[UdpSensorSample]:
    if payload.get("type") != UDP_PACKET_TYPE_SAMPLE:
        return None

    values = parse_values(payload)
    if not values:
        return None

    raw_source_id = clean_text(payload.get("source_id"), "")
    decoded_source = decode_source_id(raw_source_id) if raw_source_id else None

    fallback_device = clean_text(
        payload.get("device_name")
        or payload.get("device_token")
        or payload.get("device_id"),
        "unknown_device",
    )
    fallback_channel = normalize_channel(
        payload.get("device_channel") or payload.get("device_side")
    )
    fallback_sensor = clean_text(payload.get("sensor_name"), "unknown_sensor")
    fallback_source = clean_text(
        payload.get("device_source")
        or payload.get("device_id")
        or payload.get("device_token"),
        "unknown_source",
    )

    device_name = clean_text(
        decoded_source.get("device_name") if decoded_source else None,
        fallback_device,
    )
    device_channel = normalize_channel(
        decoded_source.get("device_channel") if decoded_source else fallback_channel
    )
    sensor_name = clean_text(
        decoded_source.get("sensor_name") if decoded_source else None,
        fallback_sensor,
    )
    source = clean_text(
        decoded_source.get("source") if decoded_source else None,
        fallback_source,
    )

    source_id = raw_source_id or encode_source_id(
        device_name=device_name,
        device_channel=device_channel,
        sensor_name=sensor_name,
        source=source,
    )
    stream_name = clean_text(payload.get("stream_name"), "") or build_stream_name(
        device_name=device_name,
        device_channel=device_channel,
        sensor_name=sensor_name,
        source=source,
    )

    device = DeviceInfo(
        name=device_name,
        channel=device_channel,
        source=source,
    )
    stream = StreamInfo(
        name=stream_name,
        source_id=source_id,
        sensor_name=sensor_name,
        device=device,
    )

    return UdpSensorSample(
        stream=stream,
        values=values,
        axis_names=_string_list(payload.get("axis_names")),
        axis_units=_string_list(payload.get("axis_units")),
        timestamp=payload.get("timestamp"),
        timestamp_exponent=payload.get("timestamp_exponent"),
        timestamp_seconds=sensor_timestamp_seconds(payload),
        raw=dict(payload),
    )


def build_probe_ack_payload(payload: Mapping[str, Any]) -> Dict[str, Any]:
    ack: Dict[str, Any] = {"type": UDP_PACKET_TYPE_PROBE_ACK}
    nonce = payload.get("nonce")
    if nonce is not None:
        ack["nonce"] = nonce
    return ack


class NetworkRelayServer:
    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 16571,
        *,
        on_warning: Optional[WarningListener] = None,
    ) -> None:
        self._on_warning = on_warning
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.bind((host, port))
        self._sock.setblocking(False)

        bound_host, bound_port = self._sock.getsockname()
        self._host = str(bound_host)
        self._port = int(bound_port)

        self._closed = False
        self._lock = threading.Lock()
        self._sample_listeners: List[SampleListener] = []
        self._samples_received = 0
        self._last_packet_wall_time: Optional[float] = None

    @property
    def host(self) -> str:
        return self._host

    @property
    def port(self) -> int:
        return self._port

    @property
    def samples_received(self) -> int:
        with self._lock:
            return self._samples_received

    @property
    def last_packet_wall_time(self) -> Optional[float]:
        with self._lock:
            return self._last_packet_wall_time

    @property
    def is_closed(self) -> bool:
        return self._closed

    def add_sample_listener(self, listener: SampleListener) -> None:
        with self._lock:
            if listener in self._sample_listeners:
                return
            self._sample_listeners.append(listener)

    def remove_sample_listener(self, listener: SampleListener) -> None:
        with self._lock:
            self._sample_listeners = [cb for cb in self._sample_listeners if cb != listener]

    def poll(self, timeout: float = 0.0) -> int:
        if self._closed:
            return 0
        if timeout < 0:
            raise ValueError("timeout must be >= 0")

        if timeout > 0:
            try:
                ready, _, _ = select.select([self._sock], [], [], timeout)
            except (OSError, ValueError):
                return 0
            if not ready:
                return 0

        samples = 0
        while True:
            try:
                packet, remote = self._sock.recvfrom(MAX_UDP_PACKET_SIZE)
            except BlockingIOError:
                return samples
            except OSError:
                return samples

            if self._process_packet(packet, remote):
                samples += 1

    def run(
        self,
        *,
        stop_event: Optional[threading.Event] = None,
        poll_interval: float = 0.25,
    ) -> None:
        if poll_interval <= 0:
            raise ValueError("poll_interval must be > 0")
        while True:
            if self._closed:
                return
            if stop_event is not None and stop_event.is_set():
                return
            self.poll(timeout=poll_interval)

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        try:
            self._sock.close()
        except OSError:
            pass

    def _warn(self, message: str) -> None:
        if self._on_warning is not None:
            self._on_warning(message)

    def _process_packet(self, packet: bytes, remote: Tuple[str, int]) -> bool:
        try:
            payload = json.loads(packet.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._warn(f"Ignoring non-JSON packet from {remote[0]}:{remote[1]}")
            return False

        if not isinstance(payload, dict):
            self._warn(f"Ignoring unexpected payload type from {remote[0]}:{remote[1]}")
            return False

        if payload.get("type") == UDP_PACKET_TYPE_PROBE:
            ack = build_probe_ack_payload(payload)
            try:
                self._sock.sendto(
                    json.dumps(ack, separators=(",", ":")).encode("utf-8"),
                    remote,
                )
            except OSError:
                pass
            return False

        sample = parse_sensor_sample(payload)
        if sample is None:
            return False

        now = time.time()
        with self._lock:
            self._samples_received += 1
            self._last_packet_wall_time = now
            listeners = tuple(self._sample_listeners)

        for listener in listeners:
            try:
                listener(sample, remote)
            except Exception as exc:
                self._warn(
                    f"Sample listener failed for {remote[0]}:{remote[1]}: {exc}"
                )
        return True
