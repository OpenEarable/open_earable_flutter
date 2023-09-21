# OpenEarable Flutter

This Dart package provides functionality for interacting with OpenEarable devices. It enables you to communicate with OpenEarable devices, control LED colors, play audio files, and access raw sensor data.

## Getting Started

To get started with the OpenEarable Flutter package, follow these steps:

1. **Installation**: Add the package to your `pubspec.yaml` file:

   ```yaml
   dependencies:
     open_earable_flutter: ^1.0.0
     ```
2. **Import the package**: 
   ```dart
   import 'package:open_earable_flutter/open_earable_flutter.dart';
   ```
3. **Initialize OpenEarable**
   ```dart
   final openEarable = OpenEarable();
   ```
4. **Connect to Earable Device**
   ```dart
   openEarable.bleManager.startScan();

   // Listen for discovered devices
   openEarable.bleManager.scanStream.listen((device) {
     // Handle discovered device
   });

   // Connect to a device
   openEarable.bleManager.connectToDevice(device);

   ```
## Usage
- Read device information:
	```dart
	final deviceIdentifier = await openEarable.readDeviceIdentifier();
	final deviceGeneration = await openEarable.readDeviceGeneration();
	```
- Sensors:
	- Configuration of Sensors:
	  ```dart
	  var config  = OpenEarableSensorConfig(sensorId: 0, samplingRate: 30, latency: 0);
	  openEarable.sensorManager.writeSensorConfig(config);
	  ```
	  Please refer to [open-earable](https://github.com/OpenEarable/open-earable/tree/v4_experimental_mess#LED) for a documentation on all possible sensor configurations
	- Subscribing to sensor data with sensor id 0
	  ```dart
	  openEarable.sensorManager.subscribeToSensorData(0).listen((data) {
		// Handle sensor data
		});
	  ```
	  Sensor data is returned as a dictionary:
	  ```json
		{
		  sensorId: 0,
		  timestamp: 163538,
		  sensorName: ACC_GYRO_MAG,
		  ACC: {
		    units: {X: g, Y: g, Z: g},
		    X: 5.255882263183594,
		    Y: -2.622856855392456,
		    Z: 8.134146690368652
		  },
		  GYRO: {
		    units: {X: dps, Y: dps, Z: dps},
		    X: 0.007621999830007553,
		    Y: -0.030487999320030212,
		    Z: -0.015243999660015106
		  },
		  MAG: {
		    units: {X: uT, Y: uT, Z: uT},
		    X: -566.1000366210938,
		    Y: -95.70000457763672,
		    Z: -117.30000305175781
		  }
		}
	  ```
	- Battery Level percentage:
	  ```dart
	  Stream batteryLevelStream = openEarable.sensorManager.getBatteryLevelStream();
	  ```
	 - Button States:
		- 0: Idle
		- 1: Pressed
		- 2: Held
		 ```dart
		 Stream buttonStateStream = openEarable.sensorManager.getButtonStateStream();
		 ```
 - Control built-in LED:
	 **This does not work at the moment**
	 ```dart
	 openEarable.rgbLed.setLEDstate(LedColor.green);
	 ```
- Control WAV audio player:
  **Has not been tested yet**
	 ```dart
	 openEarable.wavAudioPlayer.writeState(WavAudioPlayerState.start, "audio.wav");
	 ```
	 
	 

