import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import '../../open_earable_flutter.dart';
import '../constants.dart';
import 'ble_manager.dart';
import 'sensor_handler.dart';
import '../utils/sensor_scheme_parser/sensor_scheme_parser.dart';
import '../utils/sensor_value_parser/sensor_value_parser.dart';

class V2SensorHandler extends SensorHandler<V2SensorConfig> {
  final DiscoveredDevice _discoveredDevice;
  final BleManager _bleManager;

  final SensorSchemeParser _sensorSchemeParser;
  final SensorValueParser _sensorValueParser;
  List<SensorScheme>? _sensorSchemes;

  V2SensorHandler({
    required DiscoveredDevice discoveredDevice,
    required BleManager bleManager,
    required SensorSchemeParser sensorSchemeParser,
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
    StreamController<Map<String, dynamic>> streamController =
        StreamController();
    _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: sensorServiceUuid,
      characteristicId: sensorDataCharacteristicUuid,
    )
        .listen(
      (data) async {
        if (data.isNotEmpty && data[0] == sensorId) {
          Map<String, dynamic> parsedData = await _parseData(data);
          streamController.add(parsedData);
        }
      },
      onError: (error) {
        logger.e("Error while subscribing to sensor data: $error");
      },
    );

    return streamController.stream;
  }

  @override
  Future<void> writeSensorConfig(V2SensorConfig sensorConfig) async {
    if (!_bleManager.isConnected(_discoveredDevice.id)) {
      Exception("Can't write sensor config. Earable not connected");
    }
    if (_sensorSchemes == null) {
      await _readSensorScheme();
    }

    Uint8List sensorConfigBytes = Uint8List(3);
    sensorConfigBytes[0] = sensorConfig.sensorId as int;
    sensorConfigBytes[1] = sensorConfig.sampleRateIndex as int;
    sensorConfigBytes[2] = (sensorConfig.streamData ? 1 : 0) |
        (sensorConfig.storeData ? 1 : 0) << 1;

    await _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: sensorServiceUuid,
      characteristicId: sensorConfigurationV2CharacteristicUuid,
      byteData: sensorConfigBytes,
    );
  }

   /// Parses raw sensor data bytes into a [Map] of sensor values.
  Future<Map<String, dynamic>> _parseData(data) async {
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
    
    return _sensorValueParser.parse(byteData, _sensorSchemes!);
  }

  /// Reads the sensor scheme that is needed to parse the raw sensor
  /// data bytes
  Future<void> _readSensorScheme() async {
    List<int> byteStream = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: parseInfoServiceUuid,
      characteristicId: schemeCharacteristicV2Uuid,
    );

    _sensorSchemes = _sensorSchemeParser.parse(byteStream);
  }
}

class V2SensorConfig extends SensorConfig {
  final Uint8 sensorId;
  final Uint8 sampleRateIndex;
  final bool streamData;
  final bool storeData;

  V2SensorConfig({
    required this.sensorId,
    required this.sampleRateIndex,
    required this.streamData,
    required this.storeData,
  });
}
