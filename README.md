# OpenEarable Flutter

[![Pub Likes](https://img.shields.io/pub/likes/open_earable_flutter)](https://pub.dev/packages/open_earable_flutter)
[![Pub Popularity](https://img.shields.io/pub/popularity/open_earable_flutter)](https://pub.dev/packages/open_earable_flutter)
[![Pub Points](https://img.shields.io/pub/points/open_earable_flutter)](https://pub.dev/packages/open_earable_flutter)
[![Pub Version (including pre-releases)](https://img.shields.io/pub/v/open_earable_flutter)](https://pub.dev/packages/open_earable_flutter)

A Flutter plugin for communicating with [OpenEarable](https://www.open-earable.com/) devices. This package provides seamless integration for connecting to OpenEarable devices, controlling LED colors, managing audio playback, and retrieving raw sensor data via BLE. 

> **Note:** This README has been updated to reflect the latest library improvements and example application practices.

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Setup and Permissions](#setup-and-permissions)
- [Usage](#usage)
  - [Initialization and Connection](#initialization-and-connection)
  - [Sensor Data and Configurations](#sensor-data-and-configurations)
  - [LED and Audio Control](#led-and-audio-control)
- [Example Application](#example-application)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Bluetooth Low Energy (BLE) Communication:** Scan, connect, and manage OpenEarable devices.
- **Sensor Management:** Configure and subscribe to sensor data streams (e.g., accelerometer, gyroscope, magnetometer, and Euler angles).
- **LED Control:** Change built-in LED colors easily.
- **Audio Playback:** Play WAV files, generate tones using frequency and waveform control, or trigger built-in jingles.

---

## Installation

Add the package to your Flutter project via the command line:

```bash
flutter pub add open_earable_flutter
```

Alternatively, follow the detailed installation instructions on [pub.dev](https://pub.dev/packages/open_earable_flutter/install).

---

## Setup and Permissions

### Android

In your `AndroidManifest.xml`, add the following permissions:

```xml
<!-- BLE and location permissions required for BLE scanning and connections -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- Additional permissions if your app uses location services -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

> **Tip:** If your app already uses location services, ensure you remove `android:maxSdkVersion="30"` from any location permission tags.

### iOS / macOS

For iOS, update your app's `Info.plist` with the following keys:

- For iOS 13 and higher:
  - `NSBluetoothAlwaysUsageDescription`
- For iOS 12 and lower:
  - `NSBluetoothPeripheralUsageDescription`

For macOS, add the Bluetooth capability through Xcode.

Refer to [this example](https://github.com/PhilipsHue/flutter_reactive_ble/blob/master/example/ios/Runner/Info.plist) for guidance and [this blog post](https://medium.com/flawless-app-stories/handling-ios-13-bluetooth-permissions-26c6a8cbb816) for more details.

---

## Usage

### Initialization and Connection

Begin by importing the package and initializing the `OpenEarable` instance:

```dart
import 'package:open_earable_flutter/open_earable_flutter.dart';

final openEarable = OpenEarable();
```

To scan for and connect to an OpenEarable device:

```dart
// Start scanning for devices
openEarable.bleManager.startScan();

// Listen for discovered devices
openEarable.bleManager.scanStream.listen((device) {
  // Process each discovered device
  print('Found device: ${device.name}');
});

// Connect to a selected device (replace 'device' with your selected device instance)
openEarable.bleManager.connectToDevice(device);
```

### Sensor Data and Configurations

After connecting, you can read device information:

```dart
String? deviceName = openEarable.deviceName;
String? deviceIdentifier = openEarable.deviceIdentifier;
String? deviceFirmwareVersion = openEarable.deviceFirmwareVersion;
```

**Configure Sensors**

Set up sensor configurations (e.g., for sensor with ID 0):

```dart
var config = OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
openEarable.sensorManager.writeSensorConfig(config);
```

**Subscribe to Sensor Data**

Listen for sensor updates:

```dart
openEarable.sensorManager.subscribeToSensorData(0).listen((data) {
  // Handle sensor data, which is provided as a Map (JSON-like structure)
  print('Sensor data: \$data');
});
```

**Battery Level and Button State**

Access real-time battery level and button state streams:

```dart
// Battery level stream
Stream batteryLevelStream = openEarable.sensorManager.getBatteryLevelStream();

// Button state stream (0: Idle, 1: Pressed, 2: Held)
Stream buttonStateStream = openEarable.sensorManager.getButtonStateStream();
```

### LED and Audio Control

**Control the LED**

Set the built-in LED color:

```dart
openEarable.rgbLed.writeLedColor(r: 0, g: 255, b: 0); // Green LED
```

**Audio Playback Options**

1. **Play a WAV File**:

```dart
openEarable.audioPlayer.wavFile("audio.wav");
openEarable.audioPlayer.setState(AudioPlayerState.start);
```

2. **Generate a Tone**:

```dart
int waveForm = 1; // 0: sine, 1: triangle, 2: square, 3: sawtooth

double frequency = 500.0;

double loudness = 0.5; // Range: 0.0 to 1.0

openEarable.audioPlayer.frequency(waveForm, frequency, loudness);
openEarable.audioPlayer.setState(AudioPlayerState.start);
```

3. **Play a Jingle**:

```dart
int jingleId = 1; // Available jingles: 0: IDLE, 1: NOTIFICATION, 2: SUCCESS, 3: ERROR, 4: ALARM, 5: PING, 6: OPEN, 7: CLOSE, 8: CLICK

openEarable.audioPlayer.jingle(jingleId);
openEarable.audioPlayer.setState(AudioPlayerState.start);
```

---

## Example Application

An up-to-date example application is provided in the repository to demonstrate how to integrate and use the plugin. To try it out:

1. Clone the repository:

```bash
git clone https://github.com/your_org/open_earable_flutter.git
```

2. Navigate to the example directory:

```bash
cd open_earable_flutter/example
```

3. Run the application:

```bash
flutter run
```

The example covers scanning, connecting, sensor data handling, LED control, and audio playback. Use it as a reference for integrating OpenEarable in your own projects.

---

## Contributing

Contributions are welcome! Please see our [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to report issues, submit patches, or request new features.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.
