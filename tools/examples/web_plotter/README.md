# OpenWearables Web Plotter

Live browser dashboard for OpenWearables UDP sensor streams.

## What It Does

- Receives UDP samples through `NetworkRelayServer`
- Serves a live dashboard over HTTP + SSE
- Groups streams by device / side
- Plots channel data with per-channel toggles
- Preserves recent events for browser reconnects

## Requirements

No third-party Python packages are required for this example.

```bash
python3 -m pip install -r requirements.txt
```

`requirements.txt` is comment-only by design.

## Run

```bash
cd tools/examples/web_plotter
python3 web_plotter.py --port 16571 --dashboard-port 8765
```

Main flags:

- `--host` UDP bind host (default `0.0.0.0`)
- `--port` UDP bind port (default `16571`)
- `--dashboard-host` HTTP bind host (default `0.0.0.0`)
- `--dashboard-port` HTTP bind port (default `8765`)
- `--max-events` SSE reconnect buffer size (default `300`)
- `--poll-interval` relay poll interval seconds (default `0.25`)
- `--verbose` print each sample

## Connect The OpenWearables App

Use startup output from `web_plotter.py`:

1. Pick the recommended local IP shown in terminal.
2. Configure `UdpBridgeForwarder` in the app with that IP and UDP port.
3. Open one printed dashboard URL in your browser.

## Dashboard Behavior

- `RESET PLOTS` clears current chart history only.
- Legend pills toggle channels per stream.
- Device headers include relay info: source in brackets (often device id / MAC) and relay device name at the end as `via <name>` when `stream_prefix` is present.

## Troubleshooting

Dashboard opens but no streams:

- Verify forwarding host/port in app and script.
- Ensure sensors are currently streaming.
- Check firewall rules for UDP relay port.

UI looks stale after local edits:

- Hard-refresh the browser.
