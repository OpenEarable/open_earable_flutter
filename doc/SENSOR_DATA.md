# Using Sensor Data

This guide explains how to use the `Sensor`, `SensorValue`, and their subclasses to access, read, and display live sensor data in your application.

---

## 1. Accessing the Sensor Stream

Each sensor provides a stream of live data via the `sensorStream` property. You can listen to this stream to receive new data as it's emitted:

```dart
StreamSubscription? subscription = sensor.sensorStream.listen((value) {
  // Handle the new sensor value
  print("Timestamp: ${value.timestamp}");
  print("Values: ${value.valueStrings}");
});
```

> 🔄 Make sure the sensor is properly configured and active before subscribing to the stream. You can learn more about configuring sensors in the [Configuring Sensors](doc/SENSOR_CONFIG.md) documentation.

---

## 2. Interpreting Sensor Values

The data received from the stream is a subclass of `SensorValue`. It contains:

- `timestamp`: The time the data was recorded.
- `valueStrings`: A list of string representations of each axis value (e.g., ["0.1", "0.2", "0.3"]).

You can loop through the values to display or process them:

```dart
void handleSensorValue(SensorValue value) {
  for (int i = 0; i < value.dimensions; i++) {
    print("Axis ${i + 1}: ${value.valueStrings[i]}");
  }
}
```

---

## 3. Working with Typed Sensor Values

Depending on the sensor, you may receive:

- `SensorDoubleValue` — contains `List<double> values`
- `SensorIntValue` — contains `List<int> values`

To access the raw numeric data:

```dart
sensor.sensorStream.listen((value) {
  if (value is SensorDoubleValue) {
    print("Double values: ${value.values}");
  } else if (value is SensorIntValue) {
    print("Int values: ${value.values}");
  }
});
```

---

## 4. Understanding Axis Metadata

You can use the sensor’s `axisNames` and `axisUnits` to label or format values meaningfully:

```dart
for (int i = 0; i < sensor.axisCount; i++) {
  print("${sensor.axisNames[i]} (${sensor.axisUnits[i]}): ${value.valueStrings[i]}");
}
```

---

## 5. Timestamp Handling

Each `SensorValue` includes a `timestamp` which represents the time the reading was taken. The time unit is determined by the sensor’s `timestampExponent`.

Example:
- `-3` means the timestamp is in **milliseconds**
- `0` means **seconds**
- `-6` means **microseconds**

To convert the timestamp to a `DateTime` (assuming the timestamp is in milliseconds):

```dart
DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(value.timestamp);
```

Adjust accordingly based on `timestampExponent`.

---

## 6. Best Practices

- Always check the sensor is configured and enabled before using the stream.
- Unsubscribe from the stream when the data is no longer needed:

```dart
subscription?.cancel();
```

- Use `valueStrings` for display and `values` for numeric computation (when using typed values).

---

This guide covers the typical usage of sensor data in your app. Make sure to refer to your specific sensor subclass for any additional functionality or interpretation.
