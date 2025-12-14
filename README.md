# OpenEarable Flutter

![Pub Likes](https://img.shields.io/pub/likes/open_earable_flutter)
![Pub Points](https://img.shields.io/pub/points/open_earable_flutter)
![Pub Version (including pre-releases)](https://img.shields.io/pub/v/open_earable_flutter)

This Dart package provides functionality for interacting with OpenEarable devices and some other wearables.  
  
[Try it online](https://lib-example.open-earable.teco.edu/), provided your browser supports [Web Bluetooth](https://caniuse.com/web-bluetooth).

  

[![Button](https://raw.githubusercontent.com/OpenEarable/open_earable_flutter/main/.github/assets/get_oe_button.svg)](https://forms.gle/R3LMcqtyKwVH7PZB9)

[![Button](https://raw.githubusercontent.com/OpenEarable/open_earable_flutter/main/.github/assets/show_on_pub_dev_button.svg)](https://pub.dev/packages/open_earable_flutter)


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

### 1. Installation
  Add the package to your flutter project: \
  ```bash
  flutter pub add open_earable_flutter
  ```
  Alternatively, you can follow the instructions on [pub.dev](https://pub.dev/packages/open_earable_flutter/install)

### 2. Import the package
  ```dart
  import 'package:open_earable_flutter/open_earable_flutter.dart';
  ```

### 3. Initialize WearableManager
  ```dart
  final WearableManager _wearableManager = WearableManager();
  ```

### 4. Scan for devices
  ```dart
  _wearableManager.scanStream.listen((scannedDevice) {
    // Handle scanned devices
  });

  _wearableManager.startScan();
  ```

### 5. Handle new connections
  ```dart
  // Deal with new connected devices
  _wearableManager.connectStream.listen((wearable) {
    // Handle new wearable connection
    
    wearable.addDisconnectListener(() {
      // Handle disconnection
    });
  });
  ```

### 6. Connect to a device
  ```dart
  Wearable wearable = await _wearableManager.connectToDevice(scannedDevice);
  ```

### 7. Access sensor data
  In order to access sensor data, you need to check if the device is a `SensorManager`. Then you can access the sensor data streams by accessing the `sensors` property:
  ```dart
  if (wearable is SensorManager) {
    wearable.sensors.forEach((sensor) {
      sensor.sensorStream.listen((data) {
        // Handle sensor data
      });
    });
  }
  ```

  For more information about using sensor data, refer to the [Using Sensor Data](doc/SENSOR_DATA.md) documentation.

  For most devices, the sensors have to be configured before they start sending data. You can learn more about configuring sensors in the chapter [Configuring Sensors](doc/SENSOR_CONFIG.md).

## Add custom Wearable Support
Learn more about how to add support for your own wearable devices in the [Adding Custom Wearable Support](doc/ADD_CUSTOM_WEARABLE.md) documentation.