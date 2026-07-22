import 'dart:async';
import 'dart:typed_data';

import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/models/devices/polar.dart';
import 'package:open_earable_flutter/src/models/devices/wearable.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';
import '../../managers/ble_gatt_manager.dart';
import '../capabilities/sensor.dart';
import '../capabilities/sensor_specializations/heart_rate_sensor.dart';
import '../capabilities/sensor_specializations/heart_rate_variability_sensor.dart';

class PolarFactory extends WearableFactory {
  static const String _namePrefix = "Polar";

  @override
  Set<String> get usedServiceUuids => const {
        Polar.disServiceUuid,
        Polar.heartRateServiceUuid,
      };

  @override
  Future<Wearable> createFromDevice(
    DiscoveredDevice device, {
    Set<ConnectionOption> options = const {},
  }) async {
    if (bleManager == null) {
      throw Exception("bleManager needs to be set before using the factory");
    }
    if (disconnectNotifier == null) {
      throw Exception(
        "disconnectNotifier needs to be set before using the factory",
      );
    }

    if (!device.name.startsWith(_namePrefix)) {
      throw Exception("device is not a polar device");
    }

    List<Sensor> sensors = [
      _PolarHeartRateSensor(
        bleManager: bleManager!,
        discoveredDevice: device,
      ),
    ];

    bool isWatch = device.name.contains("Unite") ||
        device.name.contains("Ignite") ||
        device.name.contains("Vantage") ||
        device.name.contains("Pacer");

    if (device.name.contains(" H9") ||
        device.name.contains(" H10") ||
        isWatch) {
      // Chest straps support HRV, watches with connected strap too.
      // TODO Do strap detection on for Polar watches
      sensors.add(
        _PolarHeartRateVariabilitySensor(
          bleManager: bleManager!,
          discoveredDevice: device,
        ),
      );
    }

    return Polar(
      name: device.name,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      discoveredDevice: device,
      sensors: sensors,
    );
  }

  @override
  Future<bool> matches(
    DiscoveredDevice device,
    List<BleService> services,
  ) async {
    return device.name.startsWith(_namePrefix);
  }
}

class _PolarHeartRateSensor extends HeartRateSensor {
  final BleGattManager _bleManager;
  final DiscoveredDevice _discoveredDevice;

  _PolarHeartRateSensor({
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
  })  : _bleManager = bleManager,
        _discoveredDevice = discoveredDevice,
        super();

  @override
  Stream<HeartRateSensorValue> get sensorStream {
    StreamController<HeartRateSensorValue> streamController =
        StreamController();
    StreamSubscription<List<int>>? subscription;

    int startTime = DateTime.now().millisecondsSinceEpoch;

    streamController.onListen = () async {
      try {
        final heartRateStream = await _bleManager.subscribe(
          deviceId: _discoveredDevice.id,
          serviceId: Polar.heartRateServiceUuid,
          characteristicId: "00002a37-0000-1000-8000-00805f9b34fb",
        );
        if (streamController.isClosed) {
          return;
        }
        subscription = heartRateStream.listen((data) {
          Uint8List bytes = Uint8List.fromList(data);

          int hrFormat = bytes[0] & 0x01;

          int heartRate = hrFormat == 1
              ? (bytes[1] & 0xFF) | ((bytes[2] & 0xFF) << 8)
              : bytes[1] & 0xFF;

          if (!streamController.isClosed) {
            streamController.add(
              HeartRateSensorValue(
                heartRateBpm: heartRate,
                timestamp: DateTime.now().millisecondsSinceEpoch - startTime,
              ),
            );
          }
        });
      } catch (error, stack) {
        if (!streamController.isClosed) {
          streamController.addError(error, stack);
        }
      }
    };

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription?.cancel();
    };

    return streamController.stream;
  }
}

class _PolarHeartRateVariabilitySensor extends HeartRateVariabilitySensor {
  _PolarHeartRateVariabilitySensor({
    required BleGattManager bleManager,
    required DiscoveredDevice discoveredDevice,
  }) : super(
          rrIntervalsMsStream:
              _getRrIntervalsMsStream(bleManager, discoveredDevice),
        );

  static Stream<List<int>> _getRrIntervalsMsStream(
    BleGattManager bleManager,
    DiscoveredDevice discoveredDevice,
  ) {
    StreamController<List<int>> streamController = StreamController();
    StreamSubscription<List<int>>? subscription;

    streamController.onListen = () async {
      try {
        final heartRateStream = await bleManager.subscribe(
          deviceId: discoveredDevice.id,
          serviceId: Polar.heartRateServiceUuid,
          characteristicId: "00002a37-0000-1000-8000-00805f9b34fb",
        );
        if (streamController.isClosed) {
          return;
        }
        subscription = heartRateStream.listen((data) {
          Uint8List bytes = Uint8List.fromList(data);

          int hrFormat = bytes[0] & 0x01;
          bool rrPresent = (bytes[0] & 0x10) >> 4 == 1;
          int energyExpendedFlag = (bytes[0] & 0x08) >> 3;

          int offset = hrFormat + 2;
          if (energyExpendedFlag == 1) {
            offset += 2;
          }

          List<int> rrIntervalsMs = [];
          if (rrPresent) {
            while (offset + 1 < bytes.length) {
              int rrValue =
                  (bytes[offset] & 0xFF) | ((bytes[offset + 1] & 0xFF) << 8);
              offset += 2;
              rrIntervalsMs.add(_mapRr1024ToRrMs(rrValue));
            }

            if (!streamController.isClosed) {
              streamController.add(rrIntervalsMs);
            }
          }
        });
      } catch (error, stack) {
        if (!streamController.isClosed) {
          streamController.addError(error, stack);
        }
      }
    };

    // Cancel BLE subscription when canceling stream
    streamController.onCancel = () {
      subscription?.cancel();
    };

    return streamController.stream;
  }

  static int _mapRr1024ToRrMs(int rrValue) {
    return (rrValue * 1000) ~/ 1024;
  }
}
