# OpenWearables LSL Dashboard Example (Python Setup)

This guide is focused on one thing: starting the Python bridge on your computer so it can:

- receive forwarded UDP sensor packets,
- publish them as LSL streams,
- and show live data in a web dashboard.

## Quick Start

From the repository root (`/Users/tobi/open_earable_flutter`):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pylsl
python tools/lsl_receive_and_ploty.py --port 16571 --dashboard-port 8765
```

When it starts, it prints:

- the UDP listener (`host:port`) for incoming forwarded data,
- one or more local IP addresses,
- dashboard URLs to open in a browser.

Open the dashboard in your browser, for example:

```text
http://<your-computer-ip>:8765
```

## What You Need to Configure on Sender Side

The sender app/device must forward UDP to your computer:

- `host`: your computer IP printed by the script
- `port`: `16571` (or your custom `--port`)

That is all that is required for the bridge to ingest data.

## Common Commands

Default setup:

```bash
python tools/lsl_receive_and_ploty.py --port 16571 --dashboard-port 8765
```

Verbose packet logging:

```bash
python tools/lsl_receive_and_ploty.py --host 0.0.0.0 --port 16571 --dashboard-port 8765 --verbose
```

Use a different dashboard port:

```bash
python tools/lsl_receive_and_ploty.py --port 16571 --dashboard-port 9000
```

## Verify It Is Running

- Dashboard opens and shows `LIVE` once packets arrive.
- `http://<your-computer-ip>:<dashboard-port>/health` returns JSON status.
- LSL streams become discoverable with type `OpenWearables`.

## Minimal Network Relay Consumer Example

If you only want to receive UDP relay data and process it yourself:

```bash
python tools/lsl_receive_minimal.py
```

This script runs the reusable `NetworkRelayServer` from:

- `tools/network_relay_server.py`

The placeholder hooks are in:

- `tools/lsl_receive_minimal.py` (`handle_sensor_sample(...)`)
- `tools/lsl_receive_minimal.py` (`handle_channel_sample(...)`)

The minimal script also includes lightweight abstractions:

- `SensorSample`: one concrete sample from one sensor stream on one device
- `ChannelSample`: one concrete channel value split out from `SensorSample`

## Troubleshooting

No packets in dashboard:

- Confirm sender `host` matches your computer IP (not `localhost` unless sender is same machine).
- Confirm sender `port` matches bridge `--port`.
- Ensure firewall allows inbound UDP on the chosen bridge port.

Dashboard unreachable:

- Confirm dashboard port is open and not in use.
- Try `http://127.0.0.1:<dashboard-port>` locally first.

No LSL streams found by consumers:

- Ensure packets are reaching the bridge (dashboard should show samples).
- Ensure consumer is filtering for stream type `OpenWearables`.
