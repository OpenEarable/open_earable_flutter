import 'dart:async';
import 'dart:typed_data';

import '../capabilities/device_firmware_version.dart';
import '../capabilities/device_hardware_version.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_manager.dart';
import '../../managers/ble_manager.dart';
import '../capabilities/sensor_specializations/heart_rate_sensor.dart';
import 'discovered_device.dart';
import 'wearable.dart';

class Polar extends Wearable
    implements SensorManager, DeviceFirmwareVersion, DeviceHardwareVersion {
  static const disServiceUuid = "0000180a-0000-1000-8000-00805f9b34fb";
  static const heartRateServiceUuid = "0000180D-0000-1000-8000-00805f9b34fb";

  final List<Sensor> _sensors;
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  Polar({
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
      _HeartRateSensor(
        bleManager: _bleManager,
        discoveredDevice: _discoveredDevice,
      ),
    );
  }

  @override
  String? getWearableIconPath({bool darkmode = false}) {
    String basePath =
        'packages/open_earable_flutter/assets/wearable_icons/polar';

    if (_discoveredDevice.name.contains("Unite") ||
        _discoveredDevice.name.contains("Ignite") ||
        _discoveredDevice.name.contains("Vantage") ||
        _discoveredDevice.name.contains("Pacer")) {
      basePath += '/watch';
    } else if (_discoveredDevice.name.contains("H9") ||
        _discoveredDevice.name.contains("H10")) {
      basePath += '/strap_sensor';
    } else {
      basePath += '/default';
    }

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

  /// Reads the device firmware version from the connected Polar device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceFirmwareVersion() async {
    List<int> deviceGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: Polar.disServiceUuid,
      characteristicId: '00002a28-0000-1000-8000-00805f9b34fb',
    );

    // End string after non-printable chars
    String firmwareVersion = '';
    for (int b in deviceGenerationBytes) {
      if (b >= 32 && b < 127) {
        firmwareVersion += String.fromCharCode(b);
      } else {
        break;
      }
    }

    return firmwareVersion;
  }

  /// Reads the device hardware version from the connected Polar device.
  ///
  /// Returns a `Future` that completes with the device firmware version as a `String`.
  @override
  Future<String?> readDeviceHardwareVersion() async {
    List<int> hardwareGenerationBytes = await _bleManager.read(
      deviceId: _discoveredDevice.id,
      serviceId: Polar.disServiceUuid,
      characteristicId: "00002a27-0000-1000-8000-00805f9b34fb",
    );

    // End string after non-printable chars (and some braces, for Polar Unite)
    String hardwareVersion = '';
    for (int b in hardwareGenerationBytes) {
      if (b >= 33 && b <= 122) {
        hardwareVersion += String.fromCharCode(b);
      } else {
        break;
      }
    }

    return hardwareVersion;
  }
}

class _HeartRateSensor extends HeartRateSensor {
  final BleManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  _HeartRateSensor({
    required BleManager bleManager,
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
      serviceId: Polar.heartRateServiceUuid,
      characteristicId: "00002a37-0000-1000-8000-00805f9b34fb",
    )
        .listen((data) {
      Uint8List bytes = Uint8List.fromList(data);

      int hrFormat = data[0] & 0x01;
      bool sensorContact = (data[0] & 0x06) >> 1 == 0x03;
      bool contactSupported = (data[0] & 0x04) != 0;
      bool rrPresent = (data[0] & 0x10) >> 4 == 1;
      int energyExpendedFlag = (data[0] & 0x08) >> 3;

      int heartRate = hrFormat == 1
          ? (data[1] & 0xFF) | ((data[2] & 0xFF) << 8)
          : data[1] & 0xFF;

      int offset = hrFormat + 2;
      int energyExpended = 0;
      if (energyExpendedFlag == 1) {
        energyExpended =
            (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
        offset += 2;
      }

      List<int> rrIntervals = [];
      List<int> rrIntervalsMs = [];
      if (rrPresent) {
        while (offset + 1 < data.length) {
          int rrValue =
              (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
          offset += 2;
          rrIntervals.add(rrValue);
          rrIntervalsMs.add(_mapRr1024ToRrMs(rrValue));
        }
      }

      streamController.add(
        HeartRateSensorValue(
          heartRateBpm: heartRate,
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

  int _mapRr1024ToRrMs(int rrValue) {
    return (rrValue * 1000) ~/ 1024;
  }
}
