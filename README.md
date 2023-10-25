# OpenEarable Flutter

This Dart package provides functionality for interacting with OpenEarable devices. It enables you to communicate with OpenEarable devices, control LED colors, control audio, and access raw sensor data.

<kbd> <br> [Get OpenEarable device now!](https://forms.gle/R3LMcqtyKwVH7PZB9) <br> </kbd>

## Permissions
For your app to be able to use [Flutter reactive BLE](https://github.com/PhilipsHue/flutter_reactive_ble) in this package, you need to grant the following permissions:
### Android

You need to add the following permissions to your AndroidManifest.xml file:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
```

If you use `BLUETOOTH_SCAN` to determine location, modify your AndroidManfiest.xml file to include the following entry:

```xml
 <uses-permission android:name="android.permission.BLUETOOTH_SCAN" 
                     tools:remove="android:usesPermissionFlags"
                     tools:targetApi="s" />
```

If you use location services in your app, remove `android:maxSdkVersion="30"` from the location permission tags

### Android ProGuard rules
In case you are using ProGuard add the following snippet to your `proguard-rules.pro` file:

```
-keep class com.signify.hue.** { *; }
```

This will prevent issues like [#131](https://github.com/PhilipsHue/flutter_reactive_ble/issues/131).

### iOS

For iOS it is required you add the following entries to the `Info.plist` file of your app. It is not allowed to access Core BLuetooth without this. See [our example app](https://github.com/PhilipsHue/flutter_reactive_ble/blob/master/example/ios/Runner/Info.plist) on how to implement this. For more indepth details: [Blog post on iOS bluetooth permissions](https://medium.com/flawless-app-stories/handling-ios-13-bluetooth-permissions-26c6a8cbb816)

iOS13 and higher
* NSBluetoothAlwaysUsageDescription

iOS12 and lower
* NSBluetoothPeripheralUsageDescription

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
			"sensorId": 0,
			"timestamp": 163538,
			"sensorName": "ACC_GYRO_MAG",
			"ACC": {
				"units": {"X": "g", "Y": "g", "Z": "g"},
				"X": 5.255882263183594,
				"Y": -2.622856855392456,
				"Z": 8.134146690368652
			},
			"GYRO": {
				"units": {"X": "dps", "Y": "dps", "Z": "dps"},
				"X": 0.007621999830007553,
				"Y": -0.030487999320030212,
				"Z": -0.015243999660015106
			},
			"MAG": {
				"units": {"X": "uT", "Y": "uT", "Z": "uT"},
				"X": -566.1000366210938,
				"Y": -95.70000457763672,
				"Z": -117.30000305175781
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
	 openEarable.rgbLed.writeLedColor(r: 0, g: 255, b: 0);
	 ```
- Control audio player:
  - Play WAV files
		**Has not been tested yet**
		```dart
		openEarable.audioPlayer.setWavState(state, name: "audio.wav");
		```
			- state: WavAudioPlayerState
    	- name: filename of audio file stored on earable
	- Play Frequency:
	  ```dart
		openEarable.audioPlayer.setFrequencyState(
      state, frequency, waveForm);
		```
		- state: WavAudioPlayerState
		- frequency: double
		- waveForm: int
	- Play Jingle:
		```dart
		openEarable.audioPlayer.setJingleState(state, name: "success.wav")
		```
		- state: WavAudioPlayerState
    - name: filename of jingle stored on earable
  - Put audio player into idle state:
		```dart
		openEarable.audioPlayer.setIdle()
		```
