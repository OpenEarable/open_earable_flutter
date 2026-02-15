# LSL Forwarding

This package can forward sensor data to a bridge endpoint that converts incoming samples into Lab Streaming Layer (LSL) outlets.

## Configure in Flutter

```dart
final lslForwarder = LslForwarder.instance;
lslForwarder.configure(
  host: "192.168.1.42", // bridge host/IP
  port: 16571, // bridge UDP port
  enabled: true,
  streamPrefix: "OpenEarable",
);

final manager = WearableManager(
  sensorForwarders: [lslForwarder],
);
```

Toggle forwarding at runtime:

```dart
manager.setSensorForwarderEnabled(lslForwarder, true);
```

## Forwarder Abstraction

Forwarding is protocol-agnostic and supports dependency injection.
`LslForwarder` is just one `SensorForwarder` implementation.

You can provide a custom global list of forwarders:

```dart
final manager = WearableManager(
  sensorForwarders: [
    LslForwarder.instance,
    // MyCustomForwarder(),
  ],
);
```

## Transport and Payload

- Transport: UDP
- Encoding: UTF-8 JSON (one datagram per sample)
- Endpoint: `host:port` configured above

Payload format:

```json
{
  "type": "open_earable_lsl_sample",
  "stream_name": "OpenEarable_OpenEarable2_Accelerometer",
  "device_id": "...",
  "device_name": "...",
  "sensor_name": "Accelerometer",
  "axis_names": ["X", "Y", "Z"],
  "axis_units": ["m/s^2", "m/s^2", "m/s^2"],
  "timestamp": 123456789,
  "timestamp_exponent": -6,
  "values": [0.1, 0.2, 0.3],
  "value_strings": ["0.1", "0.2", "0.3"]
}
```

## Bundled Python Bridge

This repository includes a ready-to-use bridge script at `tools/lsl_bridge.py`.

Install dependency:

```bash
pip install pylsl
```

Run bridge:

```bash
python tools/lsl_bridge.py --port 16571
```

The script prints reachable local IP addresses at startup. Use one of those IPs as `host` in `LslForwarder.configure(...)`.

Optional:

```bash
python tools/lsl_bridge.py --host 0.0.0.0 --port 16571 --verbose
```
