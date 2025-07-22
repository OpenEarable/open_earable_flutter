# Functionality of Wearables

Wearable functionality in the Open Earable Flutter package is modular and extensible through the use of **capabilities**. Capabilities are abstract interfaces that define specific features (like sensor access, battery info, button interaction, etc.). Each `Wearable` can implement any combination of these capabilities depending on its hardware and firmware support.

This guide outlines the most common capabilities and how to use them.

---

## Popular Capabilities

Some of the most commonly used capabilities include:

### SensorManager

Enables access to available sensors on the wearable.

```dart
if (wearable is SensorManager) {
  List<Sensor> sensors = wearable.sensors;
}
```

---

### SensorConfigurationManager

Allows configuration of the wearable’s sensors, including setting sampling rates or modes.

```dart
if (wearable is SensorConfigurationManager) {
  List<SensorConfiguration> configurations = wearable.sensorConfigurations;
}
```

---

### 🔋 Battery Capabilities

#### BatteryEnergyStatusService

Provides access to battery energy data.

```dart
if (wearable is BatteryEnergyStatusService) {
  BatteryEnergyStatus status = await wearable.readEnergyStatus();
}
```

#### BatteryHealthStatusService

Reads battery health and performance metrics.

```dart
if (wearable is BatteryHealthStatusService) {
  BatteryHealthStatus healthStatus = await wearable.readHealthStatus();
}
```

#### BatteryLevelStatusService

Gives the current battery level as a percentage or unit.

```dart
if (wearable is BatteryLevelStatusService) {
  BatteryPowerStatus levelStatus = await wearable.readPowerStatus();
}
```

---

### 🔘 ButtonManager

Enables listening to hardware button events on the wearable.

```dart
if (wearable is ButtonManager) {
  wearable.buttonEvents.listen((buttonEvent) {
    // Handle button events
  });
}
```

---

### 💾 EdgeRecorderManager

Controls on-device recording. You can specify filename prefixes or manage session behaviors.

```dart
if (wearable is EdgeRecorderManager) {
  wearable.setFilePrefix("my_recording");
}
```

---

### 🎤 MicrophoneManager

Lets you select the active microphone (if the device has multiple).

```dart
if (wearable is MicrophoneManager) {
  List<Microphone> microphones = wearable.availableMicrophones;
  wearable.setMicrophone(microphones.first);
}
```

---

### 🔈 AudioModeManager

Allows switching between different audio modes (e.g., mono, stereo, streaming).

```dart
if (wearable is AudioModeManager) {
  List<AudioMode> audioModes = wearable.availableAudioModes;
  wearable.setAudioMode(audioModes.first);
}
```

---

### ℹ️ Device Information Capabilities

#### DeviceFirmwareVersion

Reads the current firmware version of the device.

```dart
if (wearable is DeviceFirmwareVersion) {
  String firmwareVersion = await wearable.readDeviceFirmwareVersion();
}
```

#### DeviceHardwareVersion

Reads the hardware version of the device.

```dart
if (wearable is DeviceHardwareVersion) {
  String hardwareVersion = await wearable.readDeviceHardwareVersion();
}
```

#### DeviceIdentifier

Retrieves the device’s unique ID.

```dart
if (wearable is DeviceIdentifier) {
  String deviceId = await wearable.readDeviceIdentifier();
}
```

---

## Summary

Capabilities are the building blocks of wearable functionality. You can dynamically check for and use any supported capability through simple type checks (`if (wearable is SomeCapability)`). This enables modular development and ensures your app only uses features supported by the connected device.
