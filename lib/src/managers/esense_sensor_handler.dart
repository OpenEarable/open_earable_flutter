import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/src/utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import 'package:open_earable_flutter/src/utils/sensor_value_parser/sensor_value_parser.dart';

import '../../open_earable_flutter.dart' show logger;
import '../models/devices/discovered_device.dart';
import '../models/devices/esense.dart';
import 'ble_gatt_manager.dart';
import 'sensor_handler.dart';

class EsenseSensorHandler extends SensorHandler<EsenseSensorConfig> {
  final BleGattManager _bleGattManager;
  final DiscoveredDevice _discoveredDevice;
  final SensorValueParser _sensorValueParser;

  /// Maps eSense sensor config ID -> data packet command header.
  /// For now:
  ///   0x53 (IMU config cmd) -> 0x55 (IMU data packet header)
  final Map<int, int> _sensorConfigIdMap = const {
    0x53: 0x55, // 9-axis IMU
  };

  /// Last known sensor configuration (either written by us or read once).
  EsenseSensorConfig? _cachedSensorConfig;

  /// Cached SensorScheme built from [_cachedSensorConfig].
  SensorScheme? _cachedSensorScheme;

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

    logger.t(
      "Subscribing to Esense sensor data for sensor ID: 0x${sensorId.toRadixString(16).toUpperCase()} "
      "at characteristic $esenseSensorDataCharacteristicUuid",
    );

    final streamController = StreamController<Map<String, dynamic>>();

    final subscription = _bleGattManager
        .subscribe(
          deviceId: _discoveredDevice.id,
          serviceId: esenseServiceUuid,
          characteristicId: esenseSensorDataCharacteristicUuid,
        )
        .listen(
      (data) async {
        if (data.isEmpty) return;

        final parsedData = await _parseData(data);

        logger.t("Received parsed Esense data: $parsedData");

        for (final d in parsedData) {
          if (!streamController.isClosed) {
            streamController.add(d);
          }
        }
      },
      onError: (error) {
        logger.e("Error while subscribing to sensor data: $error");
        if (!streamController.isClosed) {
          streamController.addError(error);
        }
      },
      onDone: () {
        if (!streamController.isClosed) {
          streamController.close();
        }
      },
    );

    // Ensure BLE subscription is cancelled when the consumer cancels our stream.
    streamController.onCancel = () => subscription.cancel();

    return streamController.stream;
  }

  @override
  Future<void> writeSensorConfig(EsenseSensorConfig sensorConfig) async {
    if (!_bleGattManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't write sensor config. Earable not connected");
    }

    final on = sensorConfig.streamData ? 0x1 : 0x0;
    final sampleRate = sensorConfig.sampleRate;

    final command =
        _buildCommand(header: sensorConfig.sensorId, data: [on, sampleRate]);

    logger.t(
      "Writing Esense sensor config: "
      "[${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}]",
    );

    await _bleGattManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorConfigCharacteristicUuid,
      byteData: command,
    );

    List<int> receivedCommand = await _bleGattManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorConfigCharacteristicUuid,
    );

    if (!listEquals(receivedCommand, command)) {
      throw Exception(
        "Esense sensor config write verification failed. "
        "Wrote: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}], "
        "Read back: [${receivedCommand.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}]",
      );
    }

    // Update local cache: we assume our write is authoritative.
    _cachedSensorConfig = sensorConfig;
    _cachedSensorScheme = null; // force rebuild with new sample rate/header
  }

  // MARK: - Helpers

  Uint8List _buildCommand({required int header, required List<int> data}) {
    final dataSize = data.length;
    final sum = data.fold<int>(dataSize, (acc, b) => acc + b);
    final checkSum = sum & 0xFF;

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

    final sensorId = data[0];
    final dataSize = data[2];
    if (dataSize != 2) {
      throw Exception(
        "Invalid sensor config data size: $dataSize. Expected 2. "
        "Full data: ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}",
      );
    }

    final streamData = data[3] == 0x1;
    final sampleRate = data[4];

    return EsenseSensorConfig(
      sensorId: sensorId,
      sampleRate: sampleRate,
      streamData: streamData,
    );
  }

  /// Returns the current sensor config.
  /// Prefers local cache (what we last wrote). If none, reads once from the device.
  Future<EsenseSensorConfig> _getSensorConfig() async {
    // 1. Use cached config if available (we wrote it ourselves).
    final cached = _cachedSensorConfig;
    if (cached != null) {
      return cached;
    }

    // 2. Otherwise read once from the device and cache it.
    final commandData = await _bleGattManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: esenseServiceUuid,
      characteristicId: esenseSensorConfigCharacteristicUuid,
    );

    final config = _buildSensorConfig(commandData);

    logger.t("Esense sensor config read from device: $config");

    _cachedSensorConfig = config;
    _cachedSensorScheme = null; // rebuild scheme based on this config

    return config;
  }

  /// Returns a SensorScheme built from the current config, caching the result.
  Future<SensorScheme> _getSensorScheme() async {
    final cachedScheme = _cachedSensorScheme;
    if (cachedScheme != null) {
      return cachedScheme;
    }

    final sensorConfig = await _getSensorConfig();

    final header = _sensorConfigIdMap[sensorConfig.sensorId];
    if (header == null) {
      throw Exception(
        "Unknown sensor ID in config: 0x${sensorConfig.sensorId.toRadixString(16).toUpperCase()}",
      );
    }

    final scheme = SensorScheme(
      header,
      "6-axis IMU",
      0,
      SensorConfigOptions(
        [SensorConfigFeatures.frequencyDefinition],
        SensorConfigFrequencies(
          0,
          0,
          [sensorConfig.sampleRate.toDouble()],
        ),
      ),
    );

    _cachedSensorScheme = scheme;
    return scheme;
  }

  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    final scheme = await _getSensorScheme();

    final parsedData = _sensorValueParser.parse(
      ByteData.sublistView(Uint8List.fromList(data)),
      [scheme],
    );

    logger.t("Parsed Esense sensor data: $parsedData");
    // TODO: scale raw values according to sensor specifications

    return parsedData;
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
