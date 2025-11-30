import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/sensor_value_parser.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../open_earable_flutter.dart' show logger;
import '../models/devices/discovered_device.dart';
import '../models/devices/esense.dart';
import 'ble_gatt_manager.dart';
import 'sensor_handler.dart';

class EsenseSensorHandler extends SensorHandler<EsenseSensorConfig> {
  final BleGattManager _bleGattManager;
  final DiscoveredDevice _discoveredDevice;

  final SensorValueParser _sensorValueParser;

  final Map<int, int> _sensorConfigIdMap = {
    0x53: 0x55, // 9-axis IMU
  };

  EsenseSensorHandler({
    required BleGattManager bleGattManager,
    required DiscoveredDevice discoveredDevice,
    required SensorValueParser sensorValueParser,
  })  : _bleGattManager = bleGattManager,
        _discoveredDevice = discoveredDevice,
        _sensorValueParser = sensorValueParser;

  @override
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleGattManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't subscribe to sensor data. Earable not connected");
    }
    logger.t("Subscribing to Esense sensor data for sensor ID: 0x${sensorId.toRadixString(16).toUpperCase()} at characteristic $esenseSensorDataCharacteristicUuid");

    StreamController<Map<String, dynamic>> streamController =
        StreamController();

    _bleGattManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorDataCharacteristicUuid,
    )
        .listen(
      (data) async {
        // logger.t("Received raw Esense: $data");

        //TODO: check somehow if the sensor ID matches
        if (data.isNotEmpty) {
          List<Map<String, dynamic>> parsedData = await _parseData(data);

          logger.t("Received parsed Esense data: $parsedData");
          
          for (var d in parsedData) {
            streamController.add(d);
          }
        }
      },
      onError: (error) async {
        logger.e("Error while subscribing to sensor data: $error");
      },
    );

    return streamController.stream;
  }

  @override
  Future<void> writeSensorConfig(EsenseSensorConfig sensorConfig) async {
    if (!_bleGattManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't write sensor config. Earable not connected");
    }

    int on = sensorConfig.streamData ? 0x1 : 0x0;
    int sampleRate = sensorConfig.sampleRate;

    List<int> command =
        _buildCommand(header: sensorConfig.sensorId, data: [on, sampleRate]);

    logger.t(
      "Writing Esense sensor config: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}]",
    );
    await _bleGattManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorConfigCharacteristicUuid,
      byteData: command,
    );

    // logger.t("Reading back Esense sensor config to verify write...");

    // List<int> response = await _bleGattManager.read(
    //   deviceId: _discoveredDevice.id,
    //   serviceId: esenseServiceUuid,
    //   characteristicId: esenseSensorConfigCharacteristicUuid,
    // );

    // if (!listEquals(command, response)) {
    //   throw Exception(
    //     "Failed to write sensor config. Response does not match command."
    //     " Sent: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}], "
    //     "Received: [${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}]",
    //   );
    // }
  }

  Uint8List _buildCommand({required int header, required List<int> data}) {
    int dataSize = data.length;
    int checkSum = (dataSize + data.reduce((a, b) => a + b)) & 0xFF;
    return Uint8List.fromList([
      header,
      checkSum,
      dataSize,
      ...data,
    ]);
  }

  EsenseSensorConfig _buildSensorConfig(List<int> data) {
    if (data.length != 5) {
      throw Exception("Invalid sensor config data length: ${data.length}");
    }
    int sensorId = data[0];
    int dataSize = data[2];
    if (dataSize != 2) {
      throw Exception("Invalid sensor config data size: $dataSize. Expected 2. Full data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}");
    }
    bool streamData = data[3] == 0x1;
    int sampleRate = data[4];

    return EsenseSensorConfig(
      sensorId: sensorId,
      sampleRate: sampleRate,
      streamData: streamData,
    );
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    List<int> commandData = await _bleGattManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorConfigCharacteristicUuid,
    );
    EsenseSensorConfig sensorConfig = _buildSensorConfig(
      commandData,
    );

    logger.t("Esense sensor config for parsing: $sensorConfig");

    if (!_sensorConfigIdMap.containsKey(sensorConfig.sensorId)) {
      throw Exception("Unknown sensor ID in config: 0x${sensorConfig.sensorId.toRadixString(16).toUpperCase()}");
    }

    SensorScheme scheme = SensorScheme(
      _sensorConfigIdMap[sensorConfig.sensorId]!,
      "6-axis IMU",
      0,
      SensorConfigOptions(
        [SensorConfigFeatures.frequencyDefinition],
        SensorConfigFrequencies(0, 0, [sensorConfig.sampleRate.toDouble()]),
      ),
    );

    List<Map<String, dynamic>> parsedData = _sensorValueParser.parse(
      ByteData.sublistView(Uint8List.fromList(data)),
      [scheme],
    );

    logger.t("Parsed Esense sensor data: $parsedData");
    //TODO: Implement Esense data parsing logic
    throw UnimplementedError();
  }
}

class EsenseSensorConfig extends SensorConfig {
  int sensorId;
  int sampleRate;
  bool streamData;

  EsenseSensorConfig({
    required this.sensorId,
    required this.sampleRate,
    required this.streamData,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EsenseSensorConfig &&
        other.sensorId == sensorId &&
        other.sampleRate == sampleRate &&
        other.streamData == streamData;
  }
  
  @override
  int get hashCode => sensorId.hashCode ^ sampleRate.hashCode ^ streamData.hashCode;
}
