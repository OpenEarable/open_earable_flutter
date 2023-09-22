library open_earable_flutter;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:convert';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

part 'constants.dart';
part 'sensor_manager.dart';
part 'ble_manager.dart';
part 'rgb_led.dart';
part 'audio_player.dart';

/// The `OpenEarable` class provides a high-level interface for interacting with OpenEarable devices
/// using Flutter and Reactive BLE.
///
/// You can use this class to manage Bluetooth connections, control RGB LEDs, read sensor data,
/// and play WAV audio files on OpenEarable devices.
class OpenEarable {
  late final BleManager bleManager;
  late final RgbLed rgbLed;
  late final SensorManager sensorManager;
  late final WavAudioPlayer wavAudioPlayer;
  String? _deviceIdentifier;
  String? _deviceGeneration;

  /// Creates an instance of the `OpenEarable` class.
  ///
  /// Initializes the Bluetooth manager, RGB LED controller, sensor manager, and audio player.
  OpenEarable() {
    bleManager = BleManager();
    rgbLed = RgbLed(bleManager: bleManager);
    sensorManager = SensorManager(bleManager: bleManager);
    wavAudioPlayer = WavAudioPlayer(bleManager: bleManager);
  }

  /// Reads the device identifier from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device identifier as a `String`.
  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceIdentifierCharacteristicUuid);
    _deviceIdentifier = String.fromCharCodes(deviceIdentifierBytes);
    return _deviceIdentifier;
  }

  /// Reads the device generation from the connected OpenEarable device.
  ///
  /// Returns a `Future` that completes with the device generation as a `String`.
  Future<String?> readDeviceGeneration() async {
    List<int> deviceGenerationBytes = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceGenerationCharacteristicUuid);
    _deviceGeneration = String.fromCharCodes(deviceGenerationBytes);
    return _deviceGeneration;
  }
}
