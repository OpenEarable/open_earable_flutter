import 'dart:async';
import 'dart:typed_data';

import '../../open_earable_flutter.dart';
import '../constants.dart';
import 'sensor_handler.dart';
import '../utils/sensor_value_parser/sensor_value_parser.dart';

class TauSensorHandler extends SensorHandler<TauSensorConfig> {
  final DiscoveredDevice _discoveredDevice;
  final BleGattManager _bleManager;

  final SensorValueParser _sensorValueParser;

  TauSensorHandler({
    required DiscoveredDevice discoveredDevice,
    required BleGattManager bleManager,
    required SensorValueParser sensorValueParser,
  })  : _discoveredDevice = discoveredDevice,
        _bleManager = bleManager,
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
        if (data.isNotEmpty && data[2] == sensorId) {
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
  Future<void> writeSensorConfig(TauSensorConfig sensorConfig) async {
    //TODO: implement
    throw UnimplementedError();
  }

   /// Parses raw sensor data bytes into a [Map] of sensor values.
  Future<Map<String, dynamic>> _parseData(data) async {
    ByteData byteData = ByteData.sublistView(Uint8List.fromList(data));
    
    return _sensorValueParser.parse(byteData, []);
  }
}

class TauSensorConfig extends SensorConfig {
  //TODO: implement
  Uint8List toBytes() {
    throw UnimplementedError();
  }
}
