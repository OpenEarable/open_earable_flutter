import 'dart:async';

import '../../../../open_earable_flutter.dart' show logger;
import '../../capabilities/battery_level.dart';
import '../bluetooth_wearable.dart';

const String _batteryLevelCharacteristicUuid = "2A19";
const String _batteryServiceUuid = "180F";

/// Mixin that implements [BatteryLevelStatus] according to the GATT specification.
mixin BatteryLevelStatusGattReader on BluetoothWearable
    implements BatteryLevelStatus {
  @override
  Future<int> readBatteryPercentage() async {
    List<int> batteryLevelList = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: _batteryServiceUuid,
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

  @override
  Stream<int> get batteryPercentageStream {
    StreamController<int> controller = StreamController<int>();
    Timer? batteryPollingTimer;

    Future<void> pollBatteryPercentage() async {
      try {
        final batteryPercentage = await readBatteryPercentage();
        if (!controller.isClosed) {
          controller.add(batteryPercentage);
        }
      } catch (e) {
        logger.e('Error reading battery percentage: $e');
      }
    }

    controller.onCancel = () {
      batteryPollingTimer?.cancel();
    };

    controller.onListen = () {
      batteryPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        unawaited(pollBatteryPercentage());
      });

      unawaited(pollBatteryPercentage());
    };

    return controller.stream;
  }
}
