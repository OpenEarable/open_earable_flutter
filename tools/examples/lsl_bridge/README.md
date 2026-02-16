# OpenWearables LSL Bridge

Receives OpenWearables UDP samples and publishes one LSL outlet per stream.

## What It Does

- Parses UDP packets using `NetworkRelayServer`
- Creates outlets keyed by stream identity (`source_id`)
- Pushes float samples with aligned timestamps
- Attaches device/sensor metadata to each outlet

## Requirements

```bash
cd tools/examples/lsl_bridge
python3 -m pip install -r requirements.txt
```

Dependency:

- `pylsl`

## Run

```bash
cd tools/examples/lsl_bridge
python3 lsl_bridge.py --port 16571
```

Main flags:

- `--host` UDP bind host (default `0.0.0.0`)
- `--port` UDP bind port (default `16571`)
- `--poll-interval` relay poll interval seconds (default `0.25`)
- `--verbose` print each bridged sample

## Connect The OpenWearables App

At startup, the script prints candidate local IPs:

1. Select the recommended IP.
2. Configure OpenWearables `UdpBridgeForwarder` with that IP and port.
3. Start sensor streaming in the app.
4. Discover outlets in your LSL consumer.

## Outlet Metadata

Each created outlet includes metadata such as:

- `device_token`
- `device_name`
- `device_channel` / `device_side`
- `device_source`
- `sensor_name`
- `source_id`
- channel `label`, `unit`, and `type`

## Troubleshooting

No outlets appear:

- Verify UDP packets reach this machine.
- Confirm host/port match app configuration.
- Confirm `pylsl` is installed correctly.

Timestamps look odd:

- Bridge uses sensor timestamp when available.
- Falls back to local clock when sensor timestamp is missing.
