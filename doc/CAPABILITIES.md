# Functionality of Wearables

Wearable functionality in the Open Earable Flutter package is modular and extensible through the use of **capabilities**. Capabilities are abstract interfaces that define specific features (like sensor access, battery info, button interaction, etc.). Each `Wearable` can implement any combination of these capabilities depending on its hardware and firmware support.

This guide outlines the most common capabilities and how to use them with the new capability lookup helpers.

Use `hasCapability<T>()` to check support and `getCapability<T>()` or `requireCapability<T>()` to fetch an instance:

```dart
if (wearable.hasCapability<SensorManager>()) {
  final sensorManager = wearable.requireCapability<SensorManager>();
  final sensors = sensorManager.sensors;
}
```

The difference between `getCapability<T>()` and `requireCapability<T>()` is that the latter throws an exception if the capability is not supported, while the former returns `null`.

> [!WARNING]
> The old way of checking capabilities using `is <Capability>` is deprecated. Please use `hasCapability<T>()` instead.

---

## Popular Capabilities

Some of the most commonly used capabilities include:

### SensorManager

Enables access to available sensors on the wearable.

```dart
final sensorManager = wearable.getCapability<SensorManager>();
if (sensorManager != null) {
  List<Sensor> sensors = sensorManager.sensors;
}
```

---

### SensorConfigurationManager

Allows configuration of the wearable’s sensors, including setting sampling rates or modes.

```dart
final configurationManager = wearable.getCapability<SensorConfigurationManager>();
if (configurationManager != null) {
  List<SensorConfiguration> configurations = configurationManager.sensorConfigurations;
}
```

---

### 🔋 Battery Capabilities

#### BatteryEnergyStatusService

Provides access to battery energy data.

```dart
final energyStatusService = wearable.getCapability<BatteryEnergyStatusService>();
if (energyStatusService != null) {
  BatteryEnergyStatus status = await energyStatusService.readEnergyStatus();
}
```

#### BatteryHealthStatusService

Reads battery health and performance metrics.

```dart
final healthStatusService = wearable.getCapability<BatteryHealthStatusService>();
if (healthStatusService != null) {
  BatteryHealthStatus healthStatus = await healthStatusService.readHealthStatus();
}
```

#### BatteryLevelStatusService

Gives the current battery level as a percentage or unit.

```dart
final levelStatusService = wearable.getCapability<BatteryLevelStatusService>();
if (levelStatusService != null) {
  BatteryPowerStatus levelStatus = await levelStatusService.readPowerStatus();
}
```

---

### 🔘 ButtonManager

Enables listening to hardware button events on the wearable.

```dart
final buttonManager = wearable.getCapability<ButtonManager>();
if (buttonManager != null) {
  buttonManager.buttonEvents.listen((buttonEvent) {
    // Handle button events
  });
}
```

---

### 💾 EdgeRecorderManager

Controls on-device recording. You can specify filename prefixes or manage session behaviors.

```dart
final edgeRecorder = wearable.getCapability<EdgeRecorderManager>();
if (edgeRecorder != null) {
  edgeRecorder.setFilePrefix("my_recording");
}
```

---

### 🎤 MicrophoneManager

Lets you select the active microphone (if the device has multiple).

```dart
final microphoneManager = wearable.getCapability<MicrophoneManager>();
if (microphoneManager != null) {
  List<Microphone> microphones = microphoneManager.availableMicrophones;
  microphoneManager.setMicrophone(microphones.first);
}
```

---

### 🔈 AudioModeManager

Allows switching between different audio modes (e.g., mono, stereo, streaming).

```dart
final audioModeManager = wearable.getCapability<AudioModeManager>();
if (audioModeManager != null) {
  List<AudioMode> audioModes = audioModeManager.availableAudioModes;
  audioModeManager.setAudioMode(audioModes.first);
}
```

---

### ℹ️ Device Information Capabilities

#### DeviceFirmwareVersion

Reads the current firmware version of the device.

```dart
final firmwareVersionService = wearable.getCapability<DeviceFirmwareVersion>();
if (firmwareVersionService != null) {
  String firmwareVersion = await firmwareVersionService.readDeviceFirmwareVersion();
}
```

#### DeviceHardwareVersion

Reads the hardware version of the device.

```dart
final hardwareVersionService = wearable.getCapability<DeviceHardwareVersion>();
if (hardwareVersionService != null) {
  String hardwareVersion = await hardwareVersionService.readDeviceHardwareVersion();
}
```

#### DeviceIdentifier

Retrieves the device’s unique ID.

```dart
final deviceIdentifierService = wearable.getCapability<DeviceIdentifier>();
if (deviceIdentifierService != null) {
  String deviceId = await deviceIdentifierService.readDeviceIdentifier();
}
```

---

## Summary

Capabilities are the building blocks of wearable functionality. Use `hasCapability<T>()` to check support and `getCapability<T>()` to access a capability instance. This enables modular development and ensures your app only uses features supported by the connected device.
