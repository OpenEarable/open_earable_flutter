# OpenWearables Tools

Python utilities for receiving OpenWearables UDP relay traffic and turning it into dashboards, LSL streams, or custom pipelines.

## Core Component: `network_relay_server.py`

`network_relay_server.py` is the shared runtime used by all tool examples.

It provides:

- UDP socket receiver (default `0.0.0.0:16571`)
- Packet parsing and normalization
- Typed sample objects (`UdpSensorSample`)
- Listener fan-out (`add_sample_listener`)
- Probe handling (`open_earable_udp_probe` -> `open_earable_udp_probe_ack`)

## End-To-End Flow

1. OpenWearables app sends UDP JSON samples using `UdpBridgeForwarder`.
2. `NetworkRelayServer` receives packets and parses them.
3. Valid sample packets are converted to `UdpSensorSample` objects.
4. All registered listeners are called with `(sample, remote_addr)`.
5. Example scripts render dashboards, publish LSL outlets, or print/process data.

## Packet Types

- `open_earable_udp_sample`: sensor payload (forwarded to listeners)
- `open_earable_udp_probe`: connection probe (acknowledged, not forwarded)
- `open_earable_udp_probe_ack`: probe response from relay server

## Stream Identity (`source_id`)

When present, stream identity is encoded as:

- `oe-v1:<device_name>:<device_channel>:<sensor_name>:<source>`

Notes:

- Components are URL-encoded.
- Missing values are normalized.
- If `source_id` is absent, the server builds one from fallback fields.

## Quick Setup (From OpenWearables App)

Configure the app to send UDP to your computer:

```dart
final udpBridgeForwarder = UdpBridgeForwarder.instance;
udpBridgeForwarder.configure(host: '<YOUR_COMPUTER_IP>', port: 16571, enabled: true);
WearableManager().addSensorForwarder(udpBridgeForwarder);
```

Use the IP printed by the example scripts at startup.

## Scripts In This Folder

- `network_relay_server.py`: reusable server library
- `lsl_receive_minimal.py`: minimal sample hooks for custom logic
- `lsl_receive_and_ploty.py`: legacy all-in-one LSL + dashboard script
- `examples/web_plotter/web_plotter.py`: live web dashboard
- `examples/lsl_bridge/lsl_bridge.py`: LSL outlet bridge

## Typical Commands

Minimal receiver:

```bash
cd tools
python3 lsl_receive_minimal.py --port 16571
```

Web dashboard example:

```bash
cd tools/examples/web_plotter
python3 web_plotter.py --port 16571 --dashboard-port 8765
```

LSL bridge example:

```bash
cd tools/examples/lsl_bridge
python3 -m pip install -r requirements.txt
python3 lsl_bridge.py --port 16571
```

## Troubleshooting

No samples arriving:

- Verify app host/port exactly match script host/port.
- Ensure phone and receiver machine are on the same network.
- Allow inbound UDP on the selected port in local firewall.

Probe works but data is empty:

- Verify sensors are actively streaming in the app.
- Check the app did not disable the forwarder at runtime.

Unexpected stream labels:

- The parser falls back to available payload metadata when optional fields are missing.
