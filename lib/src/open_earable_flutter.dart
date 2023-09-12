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

class OpenEarable {
  late final BleManager bleManager;
  late final RgbLed rgbLed;
  late final SensorManager sensorManager;
  late final AudioPlayer audioPlayer;
  String? _deviceIdentifier;
  String? _deviceGeneration;

  OpenEarable() {
    bleManager = BleManager();
    rgbLed = RgbLed(bleManager: bleManager);
    sensorManager = SensorManager(bleManager: bleManager);
    audioPlayer = AudioPlayer(bleManager: bleManager);
  }

  Future<String?> readDeviceIdentifier() async {
    List<int> deviceIdentifierBytes = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceIdentifierCharacteristicUuid);
    _deviceIdentifier = String.fromCharCodes(deviceIdentifierBytes);
    return _deviceIdentifier;
  }

  Future<String?> readDeviceGeneration() async {
    List<int> deviceGenerationBytes = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceGenerationCharacteristicUuid);
    _deviceGeneration = String.fromCharCodes(deviceGenerationBytes);
    return _deviceGeneration;
  }
}
