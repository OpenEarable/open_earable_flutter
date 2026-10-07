# OmniBuds (experimental)

The library recognizes OmniBuds by its vendor GATT service. One BLE peripheral
carries separate left and right channels; it is represented by **one `OmniBuds`
wearable** with side-labelled sensors. Do not pair two connections using the
OpenEarable `StereoDevice` API.

This integration was derived from the public Android app, not hardware captures.
Packet decoding and connection/configuration handling have automated tests;
actual sampling rates, simultaneous streaming, sensor availability across
firmware versions, and peer-status behavior still require OmniBuds hardware.
There is no firmware update, microphone recording, or audio playback API here.

## Sensors and rates

These are the selectable settings in the official app, **per ear**, not measured
BLE throughput or a guarantee that all streams can run together at maximum rate.

| Sensor | Peripheral ID | Selectable Hz | Output |
| --- | --- | --- | --- |
| Accelerometer | 0 | 10*, 25, 50, 100 | X/Y/Z in g; original LSB values retained |
| Gyroscope | 1 | 10*, 25, 50, 100 | X/Y/Z in degrees/second; original LSB values retained |
| Magnetometer | 2 | 10, 20, 50, 100 | X/Y/Z in gauss; original LSB values retained |
| PPG | 5 | 25, 50, 100 | Green, red, infrared counts |
| Object temperature | 7 | 0.2 | Degrees Celsius |
| Heart rate | 9 | Not established | Beats/minute |
| Heart-rate variability | 10 | Not established | Milliseconds |
| Blood oxygen | 11 | Not established | Percent |
| Respiration | 12 | Not established | Breaths/minute |

*The APK's accelerometer/gyro controls label rate code 0 as **10 Hz**, but its
decoder uses **12 Hz** for within-packet timing. We preserve those respective
behaviors and flag the discrepancy rather than claim either is the measured
hardware rate. Packet timestamps and original values remain accessible so this
can be checked on hardware. There is no verified output-frequency setting for
the four calculated vital signs in this integration; they have on/off controls.

Additional settings: accelerometer range 2/4/8/16 g, gyroscope range
125/250/500/1000/2000 degrees/second, and PPG LED current 31/62/93/124 mA.
`setSensorRange` selects these without changing the streaming state.

The APK names other peripherals (including ambient temperature, steps, gestures,
and battery), but names alone do not establish their configuration and payload
contracts. They are not advertised as supported typed sensors. Unmodelled events
and data remain accessible through `messages`. The microphone advertised on the
product website has no raw-stream decoder or command identified in this APK.
Characteristics A03/A04 are firmware-transfer channels, not microphone streams.

## Use

`OmniBudsFactory` is registered by default in `WearableManager`, including its
service in the browser's permitted-service list. Normal scanning/connecting is
unchanged. Connect to the earbuds, not a charging-case advertisement.

```dart
final wearable = await manager.connectToDevice(discoveredDevice);
if (wearable is OmniBuds) {
  final sensor = wearable.sensors.firstWhere(
    (s) => s.ear == DevicePosition.left && s.kind == OmniBudsSensorKind.ppg,
  );
  final samples = sensor.sensorStream.listen((sample) {
    print('${sample.timestamp}: ${sample.values}');
    // rawValues: values before conversion; message.bytes: complete notification.
  }, onError: (Object error) {
    print('Invalid sensor packet: $error');
  });
  final diagnostics = wearable.diagnostics.listen((error) {
    print('OmniBuds: $error');
  });

  await wearable.configureSensor(
    DevicePosition.left,
    OmniBudsSensorKind.ppg,
    enabled: true,
    frequencyHz: 100,
  );
  // Select DevicePosition.right to configure the other ear independently.
  // Leave subscriptions active while collecting data, then clean up:
  await wearable.configureSensor(
    DevicePosition.left,
    OmniBudsSensorKind.ppg,
    enabled: false,
  );
  await samples.cancel();
  await diagnostics.cancel();
  await wearable.disconnect();
}
```

The common `SensorManager`/`SensorConfigurationManager` APIs expose the same
sensors and controls. Raw sensors use `OmniBudsRateConfiguration`; vital signs
use `OmniBudsToggleConfiguration`. Their `apply` methods are awaitable. The
inherited void `setConfiguration` API reports asynchronous failures on
`diagnostics`. No sensors are enabled or disabled just by connecting.

Configuration state starts unknown. Successful responses populate
`sensorConfigurationStream`; `readConfiguration(ear, kind, endpoint)` explicitly
reads it back. Enabling a raw sensor waits for acknowledgements of stop, rate,
and start in that order. A rejected change is not reported as applied. If a
response times out, reconnect before retrying that endpoint: this protocol has
no transaction ID with which to distinguish a late acknowledgement from a retry.

`connectedEars` is the last optional peer-status response; `null` means unknown.
Call `refreshConnectionStatus()` to refresh it. Sensor channels existing in GATT
do not prove both ears are presently connected. `getWearableIconPath()` uses this
snapshot for the single-ear or pair illustration; if status is unavailable it
falls back to the exposed channels. Explicit `left`, `right`, and `pair` icon
variants are also available. The SVGs are original stylized illustrations, not
photographs. Consumers should refresh their image on `connectionStatusStream`.

## Wire format

Service: `00000a00-ae4a-11ed-afa1-0242ac120002`.
Left/right read-write notification channels: same UUID suffix with `00000a01`
and `00000a02`. Optional control: `00000a05`.

Configuration request bytes:

```text
peripheral, flags, length, 0, 0, endpoint, UTF-8 value
flags: 0x01 read; 0x09 write
length: 1 + UTF-8 value byte count
endpoint: 0 enable ("0"/"1"); 1 rate; 2 range/current
```

Motion rate/range values are zero-based indices into the lists above. PPG and
temperature rates, and PPG current, are literal decimal strings. Responses have
the peripheral at byte 0, message kind in the low three bits of byte 1, endpoint
at byte 5, error code at byte 6, and optional text from byte 7. Error 0 indicates
success. The implementation serializes commands and matches ear, peripheral,
and endpoint before accepting a response.

Data messages (kind 2) have a five-byte header followed by UTF-8 CSV:
`timestamp_ms,value,...`. Motion and PPG contain consecutive groups of three
values. For motion, byte 3's high nibble encodes the rate and its low nibble the
range. For PPG it contains the frequency in Hz. It is **not** a sequence number.
Scalar messages decode one value; extra scalar fields are left to the raw
message API instead of assigning them invented timing or meaning.

Motion scales are 0.061/0.122/0.244/0.488 mg/LSB for acceleration,
4.375/8.75/17.5/35/70 mdps/LSB for angular velocity, and 1.5 mG/LSB for magnetic
field. Public values convert to g, dps, and G, respectively.

`Sensor.timestampExponent` is -6. The device's millisecond timestamp is preserved
as each packet's anchor, then batch samples are interpolated at the advertised
rate using rounded microsecond offsets. This does **not** imply a microsecond
device clock or synchronized left/right sampling. Time requests (peripheral 35)
receive the phone's current Unix milliseconds, matching the vendor app. Firmware
versions can be read separately with `readEarFirmwareVersion(ear)` (peripheral
41, endpoint 0).

Optional control status uses request `[2]` and reply `[3, flags_hi, flags_lo]`;
bits 0/1 indicate left/right connection. This integration never sends firmware
transfer, reset, or firmware-mode commands.

## Evidence and remaining validation

Source: [official research page](https://www.omnibuds.tech/solutions/research),
which links the [Android APK](https://firmware.omnibuds.tech/app/ob_app.aab.apk).
Inspected package `tech.omnibuds`, app version **1.6.41**, version code **1**.
SHA-256: `40bd47eeae93f02553150d3abb28baa1b7406b48eb11fbf2712d0c03278f1251`.

Protocol observations came from its Hermes bundle's `decodeEarbudMessage`,
`convertCommandToBase64`, `ConfigCommandBuilder`, sensor configuration/conversion
tables, `readData`, `sendTimeToHeadphone`, and `getStatus` implementations. The
APK and its decompiled sources are not distributed with this package. Tests use
synthetic fixtures derived from these wire contracts, not recorded device data.

Before declaring hardware support verified:

- Confirm discovery, notification setup, configuration/readback, error replies,
  and reconnect with the installed firmware version.
- Measure each sensor at every listed rate, on each ear independently and as a
  pair. Resolve the 10/12 Hz discrepancy against device timestamps and elapsed
  time, not notification count (notifications may contain multiple readings).
- Run all streams together, with and without music. Measure achieved samples/s,
  gaps, malformed packets, and BLE MTU behavior on Android and iOS.
- Verify single-ear/pair status transitions and update the icon accordingly.
- Check coordinate axes, range scaling, PPG order, timestamp anchoring and
  restart behavior against the official app; determine vital-sign prerequisites
  and actual reporting intervals.
- Obtain a documented or captured microphone/other-peripheral contract before
  exposing additional typed sensors.
