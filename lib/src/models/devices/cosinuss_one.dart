import 'dart:async';
import 'dart:typed_data';

import '../capabilities/sensor.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import 'discovered_device.dart';
import 'wearable.dart';

// For activating PPG and ACC
final List<int> _sensorBluetoothCharacteristics = [
  0x32,
  0x31,
  0x39,
  0x32,
  0x37,
  0x34,
  0x31,
  0x30,
  0x35,
  0x39,
  0x35,
  0x35,
  0x30,
  0x32,
  0x34,
  0x35,
];

class CosinussOne extends Wearable implements SensorManager {
  static const ppgAndAccServiceUuid = "0000a000-1212-efde-1523-785feabcd123";
  static const temperatureServiceUuid = "00001809-0000-1000-8000-00805f9b34fb";
  static const heartRateServiceUuid = "0000180d-0000-1000-8000-00805f9b34fb";

  final List<Sensor> _sensors;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  CosinussOne({
    required super.name,
    required super.disconnectNotifier,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _sensors = [],
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice {
    _initSensors();
  }

  void _initSensors() {
    _sensors.add(
      _CosinussOneSensor(
        discoveredDevice: _discoveredDevice,
        bleManager: _bleManager,
        sensorName: 'ACC',
        chartTitle: 'Accelerometer',
        shortChartTitle: 'Acc.',
        axisNames: ['X', 'Y', 'Z'],
        axisUnits: ["(unknown unit)", "(unknown unit)", "(unknown unit)"],
      ),
    );
    _sensors.add(
      _CosinussOneSensor(
        discoveredDevice: _discoveredDevice,
        bleManager: _bleManager,
        sensorName: 'PPG',
        chartTitle: 'PPG',
        shortChartTitle: 'PPG',
        axisNames: ['Raw Red', 'Raw Green', 'Ambient'],
        axisUnits: ["(unknown unit)", "(unknown unit)", "(unknown unit)"],
      ),
    );
    _sensors.add(
      _CosinussOneSensor(
        discoveredDevice: _discoveredDevice,
        bleManager: _bleManager,
        sensorName: 'TEMP',
        chartTitle: 'Body Temperature',
        shortChartTitle: 'Temp.',
        axisNames: ['Temperature'],
        axisUnits: ["°C"],
      ),
    );
    _sensors.add(
      _CosinussOneSensor(
        discoveredDevice: _discoveredDevice,
        bleManager: _bleManager,
        sensorName: 'HR',
        chartTitle: 'Heart Rate',
        shortChartTitle: 'HR',
        axisNames: ['Heart Rate'],
        axisUnits: ["BPM"],
      ),
    );
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);
}

// Based on https://github.com/teco-kit/cosinuss-flutter
class _CosinussOneSensor extends Sensor {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  _CosinussOneSensor({
    required String sensorName,
    required String chartTitle,
    required String shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required BleManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        super(
          sensorName: sensorName,
          chartTitle: chartTitle,
          shortChartTitle: shortChartTitle,
        );

  @override
  List<String> get axisNames => _axisNames;

  @override
  List<String> get axisUnits => _axisUnits;

  int _twosComplimentOfNegativeMantissa(int mantissa) {
    if ((4194304 & mantissa) != 0) {
      return (((mantissa ^ -1) & 16777215) + 1) * -1;
    }

    return mantissa;
  }

  Stream<SensorValue> _createAccStream() {
    StreamController<SensorValue> streamController = StreamController();

    int startTime = DateTime.now().millisecondsSinceEpoch;

    _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.ppgAndAccServiceUuid,
      characteristicId: "0000a001-1212-efde-1523-785feabcd123",
      byteData: _sensorBluetoothCharacteristics,
    );

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.ppgAndAccServiceUuid,
      characteristicId: "0000a001-1212-efde-1523-785feabcd123",
    )
        .listen((data) {
      Int8List bytes = Int8List.fromList(data);

      // description based on placing the earable into your right ear canal
      int accX = bytes[14];
      int accY = bytes[16];
      int accZ = bytes[18];

      streamController.add(
        SensorDoubleValue(
          values: [accX.toDouble(), accY.toDouble(), accZ.toDouble()],
          timestamp: DateTime.now().millisecondsSinceEpoch - startTime,
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorValue> _createPpgStream() {
    StreamController<SensorValue> streamController = StreamController();

    int startTime = DateTime.now().millisecondsSinceEpoch;

    _bleManager.write(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.ppgAndAccServiceUuid,
      characteristicId: "0000a001-1212-efde-1523-785feabcd123",
      byteData: _sensorBluetoothCharacteristics,
    );

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.ppgAndAccServiceUuid,
      characteristicId: "0000a001-1212-efde-1523-785feabcd123",
    )
        .listen((data) {
      Uint8List bytes = Uint8List.fromList(data);

      // corresponds to the raw reading of the PPG sensor from which the heart rate is computed
      //
      // example plot https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/73/Screen-Shot-2019_2D00_01_2D00_24-at-19.30.24.png
      // (image just for illustration purpose, obtained from a different sensor! Sensor value range differs.)

      var ppgRed = bytes[0] |
          bytes[1] << 8 |
          bytes[2] << 16 |
          bytes[3] << 32; // raw green color value of PPG sensor
      var ppgGreen = bytes[4] |
          bytes[5] << 8 |
          bytes[6] << 16 |
          bytes[7] << 32; // raw red color value of PPG sensor

      var ppgGreenAmbient = bytes[8] |
          bytes[9] << 8 |
          bytes[10] << 16 |
          bytes[11] <<
              32; // ambient light sensor (e.g., if sensor is not placed correctly)

      streamController.add(
        SensorDoubleValue(
          values: [
            ppgRed.toDouble(),
            ppgGreen.toDouble(),
            ppgGreenAmbient.toDouble(),
          ],
          timestamp: DateTime.now().millisecondsSinceEpoch - startTime,
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorValue> _createTempStream() {
    StreamController<SensorValue> streamController = StreamController();

    int startTime = DateTime.now().millisecondsSinceEpoch;

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.temperatureServiceUuid,
      characteristicId: "00002a1c-0000-1000-8000-00805f9b34fb",
    )
        .listen((data) {
      var flag = data[0];

      // based on GATT standard
      double temperature = _twosComplimentOfNegativeMantissa(
            ((data[3] << 16) | (data[2] << 8) | data[1]) & 16777215,
          ) /
          100.0;
      if ((flag & 1) != 0) {
        temperature = ((98.6 * temperature) - 32.0) *
            (5.0 / 9.0); // convert Fahrenheit to Celsius
      }

      streamController.add(
        SensorDoubleValue(
          values: [temperature],
          timestamp: DateTime.now().millisecondsSinceEpoch - startTime,
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorValue> _createHeartRateStream() {
    StreamController<SensorValue> streamController = StreamController();

    int startTime = DateTime.now().millisecondsSinceEpoch;

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: CosinussOne.heartRateServiceUuid,
      characteristicId: "00002a37-0000-1000-8000-00805f9b34fb",
    )
        .listen((data) {
      Uint8List bytes = Uint8List.fromList(data);

      // based on GATT standard
      int bpm = bytes[1];
      if (!((bytes[0] & 0x01) == 0)) {
        bpm = (((bpm >> 8) & 0xFF) | ((bpm << 8) & 0xFF00));
      }

      streamController.add(
        SensorDoubleValue(
          values: [bpm.toDouble()],
          timestamp: DateTime.now().millisecondsSinceEpoch - startTime,
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  @override
  Stream<SensorValue> get sensorStream {
    switch (sensorName) {
      case "ACC":
        return _createAccStream();
      case "PPG":
        return _createPpgStream();
      case "TEMP":
        return _createTempStream();
      case "HR":
        return _createHeartRateStream();
      default:
        throw UnimplementedError();
    }
  }
}
