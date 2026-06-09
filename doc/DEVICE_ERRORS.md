# Device Error Notifications

OpenEarable V2 firmware exposes a dedicated BLE Device Error Service for
device-side events that should be visible to apps.

## BLE contract

| Item | UUID | Properties |
| --- | --- | --- |
| Device Error Service | `5f9c0001-6f4a-4c6b-9f0d-4f2f3b0a0001` | |
| Device Error Event | `5f9c0002-6f4a-4c6b-9f0d-4f2f3b0a0001` | Notify |

The payload is 57 bytes. Multi-byte fields are little-endian.

| Offset | Size | Field | Description |
| --- | ---: | --- | --- |
| 0 | 1 | `version` | Current value: `1`. |
| 1 | 1 | `level` | `0` info, `1` warning, `2` error, `3` fatal. |
| 2 | 2 | `error_code` | Stable device error code. |
| 4 | 1 | `source_id` | Sensor or system source. |
| 5 | 4 | `timestamp_ms` | Device uptime in milliseconds. |
| 9 | 48 | `message` | Null-terminated ASCII message. |

Because the payload is 57 bytes, clients need an ATT MTU of at least 60. The
Flutter package requests MTU 100 on platforms where explicit MTU negotiation is
available.

## Flutter API

Every `Wearable` exposes:

```dart
Stream<SensorError> get onError;
```

For OpenEarable V2 devices, the package subscribes to the Device Error Event
characteristic automatically after connection. Apps can listen to the stream:

```dart
wearable.onError.listen((event) {
  print(event.level);            // DeviceErrorLevel.warning, error, etc.
  print(event.errorCode);        // Numeric code, e.g. 0x0005
  print(event.sensorName);       // Human-readable source
  print(event.formattedMessage); // Ready for logs or UI
});
```

## Error codes

| Code | Meaning |
| --- | --- |
| `0x0001` | SD card removed while recording. |
| `0x0002` | SD card is not mounted. |
| `0x0003` | SD card mount failed. |
| `0x0004` | SD card file open failed. |
| `0x0005` | SD card write failed. |
| `0x0006` | SD card log header write failed. |
| `0x0007` | SD card flush failed. |
| `0x0008` | SD card/ring buffer is full. |
| `0x0009` | SD card file close failed. |
| `0x0101` | Sensor queue is full. |
| `0x0102` | Sensor initialization failed. |
| `0x0103` | Sensor read failed. |
| `0x0104` | Invalid sensor sample rate. |
| `0x0105` | Sensor not found. |
| `0x0106` | Sensor configuration queue is full. |
| `0x0201` | BLE notification failed. |
| `0x0301` | Firmware fatal error. |
