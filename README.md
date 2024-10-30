# OpenEarable Flutter

![Pub Likes](https://img.shields.io/pub/likes/open_earable_flutter)
![Pub Popularity](https://img.shields.io/pub/popularity/open_earable_flutter)
![Pub Points](https://img.shields.io/pub/points/open_earable_flutter)
![Pub Version (including pre-releases)](https://img.shields.io/pub/v/open_earable_flutter)


This Dart package provides functionality for interacting with OpenEarable devices. It enables you to communicate with OpenEarable devices, control LED colors, control audio, and access raw sensor data.  
  
[Try it online](https://open-earable-lib-web-example.web.app/), provided your browser supports [Web Bluetooth](https://caniuse.com/web-bluetooth).  
  
<br>  

<kbd> <br> [Get OpenEarable device now!](https://forms.gle/R3LMcqtyKwVH7PZB9) <br> </kbd>

<kbd> <br> [Show library on pub.dev](https://pub.dev/packages/open_earable_flutter) <br> </kbd>

## Permissions
For your app to be able to use [UniversalBLE](https://pub.dev/packages/universal_ble) in this package, you need to grant the following permissions:
### Android

You need to add the following permissions to your AndroidManifest.xml file:

```xml
<!-- flutter_reactive_ble permissions -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- location permissions -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
```

If you use location services in your app, remove `android:maxSdkVersion="30"` from the location permission tags

### iOS / macOS

For iOS it is required you add the following entries to the `Info.plist` file of your app. It is not allowed to access Core BLuetooth without this. See [our example app](https://github.com/PhilipsHue/flutter_reactive_ble/blob/master/example/ios/Runner/Info.plist) on how to implement this. For more indepth details: [Blog post on iOS bluetooth permissions](https://medium.com/flawless-app-stories/handling-ios-13-bluetooth-permissions-26c6a8cbb816)

iOS 13 and higher
* NSBluetoothAlwaysUsageDescription

iOS 12 and lower
* NSBluetoothPeripheralUsageDescription

For macOS, add the Bluetooth capability to the macOS app from Xcode.

## Getting Started
To get started with the OpenEarable Flutter package, follow these steps:

1. **Installation**: Add the package to your flutter project: \
  ```bash
  flutter pub add open_earable_flutter
  ```
  Alternatively, you can follow the instructions on [pub.dev](https://pub.dev/packages/open_earable_flutter/install)

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
- Read device information after connecting to a device:
	```dart
	String? deviceName = openEarable.deviceName;
	String? deviceIdentifier = openEarable.deviceIdentifier;
	String? deviceFirmwareVersion = openEarable.deviceFirmwareVersion;
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
			"EULER": {
				"units": {"ROLL": "rad", "PITCH": "rad", "YAW": "rad"},
				"ROLL": 0.8741,
				"PITCH": -0.2417,
				"YAW": 1.2913
			}
		}
		```
	- Battery Level percentage:
		```dart
		Stream batteryLevelStream = openEarable.sensorManager.getBatteryLevelStream();
		```
	- Button State:
		```dart
		Stream buttonStateStream = openEarable.sensorManager.getButtonStateStream();
		```
		- contains the following button states as integers:
    	- 0: Idle
    	- 1: Pressed
    	- 2: Held
- Control built-in LED:
	```dart
	openEarable.rgbLed.writeLedColor(r: 0, g: 255, b: 0);
	```
- Control audio player:
  - Play WAV files
    ```dart
	openEarable.audioPlayer.wavFile("audio.wav");
	openEarable.audioPlayer.setState(AudioPlayerState.start);
    ```
  	- name: filename of audio file stored on earable
  - Play Frequency:
    ```dart
	int waveForm = 1;
	double frequency = 500.0;
	double loudness = 0.5;
	openEarable.audioPlayer.frequency(waveForm, frequency, loudness);
    openEarable.audioPlayer.setState(AudioPlayerState.start);
    ```
	  - state: WavAudioPlayerState
		- frequency: double
		- waveForm: int
  		- 0: sine
  		- 1: triangle
  		- 2: square
  		- 3: sawtooth
		- loudness: double between 0.0 and 1.0
	- Play Jingle:
		```dart
		int jingleId = 1;
		openEarable.audioPlayer.jingle(jingleId);
    	openEarable.audioPlayer.setState(AudioPlayerState.start);
		```
    	- jingleId: id of jingle stored on earable
		- 0: 'IDLE'
  		- 1: 'NOTIFICATION'
  		- 2: 'SUCCESS'
  		- 3: 'ERROR'
  		- 4: 'ALARM'
  		- 5: 'PING'
  		- 6: 'OPEN'
  		- 7: 'CLOSE'
  		- 8: 'CLICK'
