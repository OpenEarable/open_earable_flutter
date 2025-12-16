import 'dart:async';
import 'dart:typed_data';

import '../../../open_earable_flutter.dart';

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

class CosinussOne extends Wearable
    implements SensorManager, BatteryLevelStatus {
  static const ppgAndAccServiceUuid = "0000a000-1212-efde-1523-785feabcd123";
  static const temperatureServiceUuid = "00001809-0000-1000-8000-00805f9b34fb";
  static const heartRateServiceUuid = "0000180d-0000-1000-8000-00805f9b34fb";

  static const batteryServiceUuid = "180f";
  static const _batteryLevelCharacteristicUuid = "02a19";

  final List<Sensor> _sensors;
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  CosinussOne({
    required super.name,
    required super.disconnectNotifier,
    required BleGattManager bleManager,
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
      _CosinussOneHeartRateSensor(
        discoveredDevice: _discoveredDevice,
        bleManager: _bleManager,
      ),
    );
  }

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    String basePath =
        'packages/open_earable_flutter/assets/wearable_icons/cosinuss_one';

    if (darkmode) {
      return '$basePath/icon_white.svg';
    }

    return '$basePath/icon.svg';
  }

  @override
  String get deviceId => _discoveredDevice.id;

  @override
  Future<void> disconnect() {
    return _bleManager.disconnect(_discoveredDevice.id);
  }

  @override
  List<Sensor> get sensors => List.unmodifiable(_sensors);

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> streamController = StreamController();

    StreamSubscription subscription = _bleManager
        .subscribe(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    )
        .listen((data) {
      streamController.add(data[0]);
    });

    readBatteryPercentage().then((percentage) {
      streamController.add(percentage);
      streamController.close();
    }).catchError((error) {
      streamController.addError(error);
      streamController.close();
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  @override
  Future<int> readBatteryPercentage() async {
    List<int> batteryLevelList = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: batteryServiceUuid,
      characteristicId: _batteryLevelCharacteristicUuid,
    );

    logger.t("Battery level bytes: $batteryLevelList");

    if (batteryLevelList.length != 1) {
      throw StateError(
        'Battery level characteristic expected 1 value, but got ${batteryLevelList.length}',
      );
    }

    return batteryLevelList[0];
  }
}

// Based on https://github.com/teco-kit/cosinuss-flutter
class _CosinussOneSensor extends Sensor<SensorDoubleValue> {
  final List<String> _axisNames;
  final List<String> _axisUnits;
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  _CosinussOneSensor({
    required super.sensorName,
    required super.chartTitle,
    required super.shortChartTitle,
    required List<String> axisNames,
    required List<String> axisUnits,
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _axisNames = axisNames,
        _axisUnits = axisUnits,
        _bleManager = bleManager,
        _discoveredDevice = discoveredDevice;

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

  Stream<SensorDoubleValue> _createAccStream() {
    StreamController<SensorDoubleValue> streamController = StreamController();

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
          timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch - startTime),
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorDoubleValue> _createPpgStream() {
    StreamController<SensorDoubleValue> streamController = StreamController();

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
          timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch - startTime),
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }

  Stream<SensorDoubleValue> _createTempStream() {
    StreamController<SensorDoubleValue> streamController = StreamController();

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
          timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch - startTime),
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
  Stream<SensorDoubleValue> get sensorStream {
    switch (sensorName) {
      case "ACC":
        return _createAccStream();
      case "PPG":
        return _createPpgStream();
      case "TEMP":
        return _createTempStream();
      default:
        throw UnimplementedError();
    }
  }
}

// Based on https://github.com/teco-kit/cosinuss-flutter
class _CosinussOneHeartRateSensor extends HeartRateSensor {
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  _CosinussOneHeartRateSensor({
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        super();

  @override
  Stream<HeartRateSensorValue> get sensorStream {
    StreamController<HeartRateSensorValue> streamController =
        StreamController();

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
        HeartRateSensorValue(
          heartRateBpm: bpm,
          timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch - startTime),
        ),
      );
    });

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription.cancel();
    };

    return streamController.stream;
  }
}
