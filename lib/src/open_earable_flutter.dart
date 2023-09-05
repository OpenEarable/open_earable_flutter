library open_earable_flutter;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:convert';

import 'package:location/location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:typed_data/typed_data.dart';

part 'constants.dart';
part 'open_earable_sensors.dart';
part 'sensor_data_provider.dart';
part 'ble_manager.dart';

class OpenEarable {
  late final BleManager bleManager;
  late final SensorManager sensorDataProvider;

  OpenEarable() {
    bleManager = BleManager();

    sensorDataProvider = SensorManager(bleManager: bleManager);
  }

  void setSensorConfig(OpenEarableSensorConfig sensorConfig) async {
    bleManager.write(
        serviceId: sensorServiceUuid,
        characteristicId: sensorConfigurationCharacteristicUuid,
        value: sensorConfig.byteList);
  }

  Stream getSensorDataStream(sensorId) {
    return sensorDataProvider.subscribeToSensorData(sensorId);
  }

  void disposeSensorDataStream(sensorId) {
    sensorDataProvider.disposeStreamController(sensorId);
  }

  void disposeAllSensorDataStreams(sensorId) {
    sensorDataProvider.disposeAll();
  }

  Future<String> readDeviceIdentifier() async {
    return bleManager.readString(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceIdentifierCharacteristicUuid);
  }

  Future<String> readDeviceGeneration() async {
    return bleManager.readString(
        serviceId: deviceInfoServiceUuid,
        characteristicId: deviceGenerationCharacteristicUuid);
  }

  void writeWAVState(int state, int size, String name) {
    ByteData data = ByteData(2 + name.length);
    data.setUint8(0, state);
    data.setUint8(1, size);

    List<int> nameBytes = utf8.encode(name);
    for (var i = 0; i < nameBytes.length; i++) {
      data.setUint8(2 + i, nameBytes[i]);
    }

    bleManager.write(
        serviceId: WAVPlayServiceUuid,
        characteristicId: WAVPlayCharacteristic,
        value: data.buffer.asUint8List());
  }

  Stream getBatteryLevelStream() {
    return bleManager.subscribe(
        serviceId: batteryServiceUuid,
        characteristicId: batteryLevelCharacteristicUuid);
  }

  Stream getButtonStateStream() {
    return bleManager.subscribe(
        serviceId: buttonServiceUuid,
        characteristicId: buttonStateCharacteristicUuid);
  }

  void setLEDstate(int state) async {
    ByteData data = ByteData(1);
    data.setUint8(0, state);
    bleManager.write(
        serviceId: LEDServiceUuid,
        characteristicId: LEDSetStateCharacteristic,
        value: data.buffer.asInt8List());
  }
}
