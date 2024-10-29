library open_earable_flutter;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'src/models/discovered_device.dart';

import 'package:open_earable_flutter/src/utils/mahony_ahrs.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

export 'src/models/discovered_device.dart';

part 'src/constants.dart';

part 'src/managers/sensor_manager.dart';

part 'src/managers/ble_manager.dart';

part 'src/managers/rgb_led.dart';

part 'src/managers/audio_player.dart';

/// The `OpenEarable` class provides a high-level interface for interacting with OpenEarable devices
/// using Flutter and Reactive BLE.
///
/// You can use this class to manage Bluetooth connections, control RGB LEDs, read sensor data,
/// and play WAV audio files on OpenEarable devices.
class OpenEarable {
  late final BleManager bleManager;
  late final RgbLed rgbLed;
  late final SensorManager sensorManager;
  late final AudioPlayer audioPlayer;

  String? get deviceName => bleManager.connectedDevice?.name;

  String? get deviceIdentifier => bleManager.deviceIdentifier;

  String? get deviceFirmwareVersion => bleManager.deviceFirmwareVersion;

  String? get deviceHardwareVersion => bleManager.deviceHardwareVersion;

  /// Creates an instance of the `OpenEarable` class.
  ///
  /// Initializes the Bluetooth manager, RGB LED controller, sensor manager, and audio player.
  OpenEarable() {
    bleManager = BleManager();
    rgbLed = RgbLed(bleManager: bleManager);
    sensorManager = SensorManager(bleManager: bleManager);
    audioPlayer = AudioPlayer(bleManager: bleManager);
  }
}
