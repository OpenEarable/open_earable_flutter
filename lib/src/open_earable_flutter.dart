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

  OpenEarable() {
    bleManager = BleManager();
    rgbLed = RgbLed(bleManager: bleManager);
    sensorManager = SensorManager(bleManager: bleManager);
    audioPlayer = AudioPlayer(bleManager: bleManager);
  }

  Future<String> readDeviceIdentifier() async {
    List<int> deviceIdentifier = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceIdentifierCharacteristicUuid);
    return String.fromCharCodes(deviceIdentifier);
  }

  Future<String> readDeviceGeneration() async {
    List<int> deviceGeneration = await bleManager.read(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceGenerationCharacteristicUuid);
    return String.fromCharCodes(deviceGeneration);
  }
}
