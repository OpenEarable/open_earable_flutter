import 'dart:async';
import 'dart:typed_data';

import '../../open_earable_flutter.dart';
import '../constants.dart';
import 'sensor_handler.dart';
import '../utils/sensor_scheme_parser/sensor_scheme_reader.dart';
import '../utils/sensor_value_parser/sensor_value_parser.dart';

class V2SensorHandler extends SensorHandler<V2SensorConfig> {
  final DiscoveredDevice _discoveredDevice;
  final BleGattManager _bleManager;

  final SensorSchemeReader _sensorSchemeParser;
  final SensorValueParser _sensorValueParser;
  List<SensorScheme>? _sensorSchemes;
  Future<void>? _sensorSchemesReadFuture;

  V2SensorHandler({
    required DiscoveredDevice discoveredDevice,
    required BleGattManager bleManager,
    required SensorSchemeReader sensorSchemeParser,
    required SensorValueParser sensorValueParser,
  })  : _discoveredDevice = discoveredDevice,
        _bleManager = bleManager,
        _sensorSchemeParser = sensorSchemeParser,
        _sensorValueParser = sensorValueParser;

  @override
  Stream<Map<String, dynamic>> subscribeToSensorData(int sensorId) {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't subscribe to sensor data. Earable not connected");
    }

    late final StreamController<Map<String, dynamic>> streamController;
    // ignore: cancel_subscriptions
    StreamSubscription<List<int>>? subscription;
    streamController = StreamController<Map<String, dynamic>>(
      onListen: () {
        // ignore: cancel_subscriptions
        subscription = _bleManager
            .subscribe(
          deviceId: _discoveredDevice.id,
          serviceId: sensorServiceUuid,
          characteristicId: sensorDataCharacteristicUuid,
        )
            .listen(
          (data) async {
            if (data.isEmpty || data[0] != sensorId) {
              return;
            }

            try {
              List<Map<String, dynamic>> parsedData = await _parseData(data);
              for (var d in parsedData) {
                if (!streamController.isClosed) {
                  streamController.add(d);
                }
              }
            } catch (error, stackTrace) {
              logger.e(
                "Error while processing V2 sensor packet: $error",
                error: error,
                stackTrace: stackTrace,
              );
              if (!streamController.isClosed) {
                streamController.addError(error, stackTrace);
              }
            }
          },
          onError: (error, stackTrace) {
            logger.e(
              "Error while subscribing to sensor data: $error",
              error: error,
              stackTrace: stackTrace,
            );
            if (!streamController.isClosed) {
              streamController.addError(error, stackTrace);
            }
          },
          onDone: () {
            if (!streamController.isClosed) {
              streamController.close();
            }
          },
        );
      },
      onCancel: () async {
        final activeSubscription = subscription;
        subscription = null;
        if (activeSubscription != null) {
          await activeSubscription.cancel();
        }
      },
    );

    return streamController.stream;
  }

  @override
  Future<void> writeSensorConfig(V2SensorConfig sensorConfig) async {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      throw Exception("Can't write sensor config. Earable not connected");
    }
    await _ensureSensorSchemesLoaded();

    Uint8List sensorConfigBytes = sensorConfig.toBytes();

    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigurationV2CharacteristicUuid,
      byteData: sensorConfigBytes,
    );
  }

  /// Parses raw sensor data bytes into a [Map] of sensor values.
  Future<List<Map<String, dynamic>>> _parseData(List<int> data) async {
    await _ensureSensorSchemesLoaded();
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));

    return _sensorValueParser.parse(byteData, _sensorSchemes!);
  }

  Future<void> _ensureSensorSchemesLoaded() async {
    final schemes = _sensorSchemes;
    if (schemes != null && schemes.isNotEmpty) {
      return;
    }

    final pendingRead = _sensorSchemesReadFuture ??= _readSensorScheme();
    try {
      await pendingRead;
    } finally {
      if (identical(_sensorSchemesReadFuture, pendingRead)) {
        _sensorSchemesReadFuture = null;
      }
    }

    final loadedSchemes = _sensorSchemes;
    if (loadedSchemes == null || loadedSchemes.isEmpty) {
      throw StateError('V2 sensor scheme is not available yet');
    }
  }

  /// Reads the sensor scheme that is needed to parse the raw sensor
  /// data bytes
  Future<void> _readSensorScheme() async {
    _sensorSchemes = await _sensorSchemeParser.readSensorSchemes();
  }
}

class V2SensorConfig extends SensorConfig {
  final int sensorId;
  final int sampleRateIndex;
  final bool streamData;
  final bool storeData;

  V2SensorConfig({
    required this.sensorId,
    required this.sampleRateIndex,
    required this.streamData,
    required this.storeData,
  });

  Uint8List toBytes() {
    Uint8List bytes = Uint8List(3);
    bytes[0] = sensorId;
    bytes[1] = sampleRateIndex;
    bytes[2] = (streamData ? 1 : 0) | (storeData ? 1 : 0) << 1;
    return bytes;
  }

  static V2SensorConfig fromBytes(Uint8List bytes) {
    if (bytes.length != 3) {
      throw ArgumentError("Invalid byte length for V2SensorConfig");
    }
    return V2SensorConfig(
      sensorId: bytes[0],
      sampleRateIndex: bytes[1],
      streamData: (bytes[2] & 0x01) != 0,
      storeData: (bytes[2] & 0x02) != 0,
    );
  }

  static List<V2SensorConfig> listFromBytes(Uint8List bytes) {
    if (bytes.length % 3 != 0) {
      throw ArgumentError("Invalid byte length for V2SensorConfig list");
    }
    List<V2SensorConfig> configs = [];
    for (int i = 0; i < bytes.length; i += 3) {
      configs.add(V2SensorConfig.fromBytes(bytes.sublist(i, i + 3)));
    }
    return configs;
  }
}
