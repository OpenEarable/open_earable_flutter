import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:open_earable_flutter/src/constants.dart';
import 'package:open_earable_flutter/src/managers/ble_manager.dart';

import 'sensor_scheme_reader.dart';

class V2SensorSchemeReader extends SensorSchemeReader {
  final String _deviceId;
  final BleManager _bleManager;

  final Map<int, SensorScheme> _sensorSchemes = {};
  final List<int> _sensorIds = [];

  V2SensorSchemeReader(this._bleManager, this._deviceId);

  Future<void> _readSensorIds() async {
    List<int> sensorIdBuffer = await _bleManager.read(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorListCharacteristicUuid,
    );

    if (sensorIdBuffer.isEmpty) {
      throw Exception("No sensor ids found.");
    }

    int sensorIdCount = sensorIdBuffer[0];
    List<int> sensorIds = sensorIdBuffer.sublist(1, sensorIdCount + 1);

    _sensorIds.clear();
    _sensorIds.addAll(sensorIds);
  }

  @override
  Future<SensorScheme> getSchemeForSensor(int sensorId) async {
    if (_sensorIds.isEmpty) {
      await _readSensorIds();
    }
    if (!_sensorIds.contains(sensorId)) {
      throw Exception("Sensor with id $sensorId does not exist.");
    }

    if (_sensorSchemes.containsKey(sensorId)) {
      return _sensorSchemes[sensorId]!;
    }

    // Listen to the notification of the characteristic
    Stream stream = _bleManager.subscribe(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: sensorSchemeCharacteristicUuid,
    );

    // Request sensor value
    await _bleManager.write(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: requestSensorSchemeCharacteristicUuid,
      byteData: [sensorId],
    );

    // Wait for the notification
    try {
      await for (List<int> value in stream.timeout(const Duration(seconds: 5))) {
      SensorScheme scheme = _parseSensorScheme(value);
      if (scheme.sensorId != sensorId) {
        throw Exception("Sensor id mismatch. Expected: $sensorId, got: ${scheme.sensorId}");
      }

      _sensorSchemes[sensorId] = scheme;
      return scheme;
      }
    } on TimeoutException catch (e) {
      throw Exception("Timeout while waiting for sensor scheme: $e");
    }

    throw Exception("Unknown error while waiting for sensor scheme.");
  }

  @override
  Future<List<SensorScheme>> readSensorSchemes({bool forceRead = false}) async {
    if (_sensorIds.isEmpty || forceRead) {
      await _readSensorIds();
    }

    for (int sensorId in _sensorIds) {
      if (!_sensorSchemes.containsKey(sensorId) || forceRead) {
        SensorScheme scheme = await getSchemeForSensor(sensorId);
        _sensorSchemes[sensorId] = scheme;
      }
    }

    return _sensorSchemes.values.toList();
  }

  SensorScheme _parseSensorScheme(List<int> byteStream) {
    int currentIndex = 0;
    int sensorId = byteStream[currentIndex++];

    int nameLength = byteStream[currentIndex++];

    List<int> nameBytes =
        byteStream.sublist(currentIndex, currentIndex + nameLength);
    String sensorName = utf8.decode(nameBytes);
    currentIndex += nameLength;

    int componentCount = byteStream[currentIndex++];

    SensorScheme sensorScheme =
        SensorScheme(sensorId, sensorName, componentCount, null);

    for (int j = 0; j < componentCount; j++) {
      int componentType = byteStream[currentIndex++];

      int groupNameLength = byteStream[currentIndex++];

      List<int> groupNameBytes =
          byteStream.sublist(currentIndex, currentIndex + groupNameLength);
      String groupName = utf8.decode(groupNameBytes);
      currentIndex += groupNameLength;

      int componentNameLength = byteStream[currentIndex++];

      List<int> componentNameBytes = byteStream.sublist(
        currentIndex,
        currentIndex + componentNameLength,
      );
      String componentName = utf8.decode(componentNameBytes);
      currentIndex += componentNameLength;

      int unitNameLength = byteStream[currentIndex++];

      List<int> unitNameBytes =
          byteStream.sublist(currentIndex, currentIndex + unitNameLength);
      String unitName = utf8.decode(unitNameBytes);
      currentIndex += unitNameLength;

      Component component =
          Component(componentType, groupName, componentName, unitName);
      sensorScheme.components.add(component);
    }

    //Parse config options
    int availableFeatures = byteStream[currentIndex++];
    List<SensorConfigFeatures> features = [];
    for (SensorConfigFeatures f in SensorConfigFeatures.values) {
      if (availableFeatures & f.value == f.value) {
        features.add(f);
      }
    }

    SensorConfigFrequencies? frequencies;
    if (features.contains(SensorConfigFeatures.frequencyDefinition)) {
      int frequencyCount = byteStream[currentIndex++];
      int defaultFreqIndex = byteStream[currentIndex++];
      int maxStreamingFreqIndex = byteStream[currentIndex++];
      List<int> frequenciesBytes = byteStream.sublist(
        currentIndex,
        currentIndex + frequencyCount * 4,
      );
      List<double> freqs = [];
      for (int k = 0; k < frequencyCount; k++) {
        ByteData byteData = ByteData.sublistView(
          Uint8List.fromList(frequenciesBytes.sublist(k * 4, (k + 1) * 4)),
        );
        freqs.add(byteData.getFloat32(0, Endian.little));
      }
      currentIndex += frequencyCount * 4;
      frequencies = SensorConfigFrequencies(maxStreamingFreqIndex, defaultFreqIndex, freqs);
    }
    sensorScheme.options = SensorConfigOptions(features, frequencies);

    return sensorScheme;
  }
}
