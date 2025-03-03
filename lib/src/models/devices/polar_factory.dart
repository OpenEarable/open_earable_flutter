import 'dart:async';
import 'dart:typed_data';

import 'package:open_earable_flutter/src/models/devices/discovered_device.dart';
import 'package:open_earable_flutter/src/models/devices/polar.dart';
import 'package:open_earable_flutter/src/models/devices/wearable.dart';
import 'package:open_earable_flutter/src/models/wearable_factory.dart';
import 'package:universal_ble/universal_ble.dart';
import '../../managers/ble_manager.dart';
import '../capabilities/sensor_specializations/heart_rate_sensor.dart';

class PolarFactory extends WearableFactory {
  static const String _namePrefix = "Polar";

  @override
  Future<Wearable> createFromDevice(DiscoveredDevice device) async {
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

    return Polar(
      name: device.name,
      disconnectNotifier: disconnectNotifier!,
      bleManager: bleManager!,
      discoveredDevice: device,
      sensors: [
        _HeartRateSensor(
          bleManager: bleManager!,
          discoveredDevice: device,
        ),
      ],
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
