import '../../constants.dart';
import '../../managers/ble_gatt_manager.dart';
import 'sensor_scheme_reader.dart';

/// This class is used to parse the sensor scheme from the byte stream of Devices, matching the EdgeML sensor scheme.
class EdgeMlSensorSchemeReader extends SensorSchemeReader {

  final BleGattManager _bleManager;
  final String _deviceId;

  Map<int, SensorScheme> _sensorSchemes = {};

  /// Creates a [EdgeMlSensorSchemeReader] instance with the specified [bleManager] and [deviceId].
  EdgeMlSensorSchemeReader(this._bleManager, this._deviceId);

  /// Parses the sensor scheme from the byte stream.
  /// The [byteStream] is a list of bytes that contains the sensor scheme.
  /// Returns a list of [SensorScheme] objects.
  List<SensorScheme> _parse(List<int> byteStream) {
    int currentIndex = 0;

    int numSensors = byteStream[currentIndex++];
    List<SensorScheme> sensorSchemes = [];
    for (int i = 0; i < numSensors; i++) {
      int sensorId = byteStream[currentIndex++];

      int nameLength = byteStream[currentIndex++];

      List<int> nameBytes =
          byteStream.sublist(currentIndex, currentIndex + nameLength);
      String sensorName = String.fromCharCodes(nameBytes);
      currentIndex += nameLength;

      int componentCount = byteStream[currentIndex++];

      SensorScheme sensorScheme =
          SensorScheme(sensorId, sensorName, componentCount, null);

      for (int j = 0; j < componentCount; j++) {
        int componentType = byteStream[currentIndex++];

        int groupNameLength = byteStream[currentIndex++];

        List<int> groupNameBytes =
            byteStream.sublist(currentIndex, currentIndex + groupNameLength);
        String groupName = String.fromCharCodes(groupNameBytes);
        currentIndex += groupNameLength;

        int componentNameLength = byteStream[currentIndex++];

        List<int> componentNameBytes = byteStream.sublist(
          currentIndex,
          currentIndex + componentNameLength,
        );
        String componentName = String.fromCharCodes(componentNameBytes);
        currentIndex += componentNameLength;

        int unitNameLength = byteStream[currentIndex++];

        List<int> unitNameBytes =
            byteStream.sublist(currentIndex, currentIndex + unitNameLength);
        String unitName = String.fromCharCodes(unitNameBytes);
        currentIndex += unitNameLength;

        Component component =
            Component(ParseType.fromInt(componentType), groupName, componentName, unitName);
        sensorScheme.components.add(component);
      }

      sensorSchemes.add(sensorScheme);
    }

    return sensorSchemes;
  }
  
  @override
  Future<SensorScheme> getSchemeForSensor(int sensorId) async {
    if (_sensorSchemes.isEmpty || !_sensorSchemes.containsKey(sensorId)) {
      try {
        await readSensorSchemes();
      } catch (e) {
        throw Exception('Failed to read sensor schemes: $e');
      }
      if (_sensorSchemes.containsKey(sensorId)) {
        return _sensorSchemes[sensorId]!;
      } else {
        throw Exception('Sensor scheme not found for sensor id: $sensorId');
      }
    } else {
      return Future.value(_sensorSchemes[sensorId]);
    }
  }
  
  @override
  Future<List<SensorScheme>> readSensorSchemes({bool forceRead = false}) {
    if (!forceRead && _sensorSchemes.isNotEmpty) {
      return Future.value(_sensorSchemes.values.toList());
    }

    return _bleManager.read(
      deviceId: _deviceId,
      serviceId: parseInfoServiceUuid,
      characteristicId: schemeCharacteristicUuid,
    ).then((byteStream) {
      List<SensorScheme> sensorSchemeList = _parse(byteStream);
      _sensorSchemes = Map.fromEntries(sensorSchemeList.map((e) => MapEntry(e.sensorId, e)));
      return _sensorSchemes.values.toList();
    });
  }
}
