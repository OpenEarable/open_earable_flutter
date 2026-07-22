import 'dart:async';

import '../../../../open_earable_flutter.dart' show logger;
import '../../capabilities/battery_health_status.dart';
import '../bluetooth_wearable.dart';

const String _batteryHealthStatusCharacteristicUuid = "2BEA";
const String _batteryServiceUuid = "180F";

mixin BatteryHealthStatusGattReader on BluetoothWearable
    implements BatteryHealthStatusService {
  @override
  Future<BatteryHealthStatus> readHealthStatus() async {
    List<int> healthStatusList = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryHealthStatusCharacteristicUuid,
    );

    logger.t("Battery health status bytes: $healthStatusList");

    if (healthStatusList.length != 5) {
      throw StateError(
        'Battery health status characteristic expected 5 values, but got ${healthStatusList.length}',
      );
    }

    int healthSummary = healthStatusList[1];
    int cycleCount = (healthStatusList[2] << 8) | healthStatusList[3];
    int currentTemperature = healthStatusList[4];

    BatteryHealthStatus batteryHealthStatus = BatteryHealthStatus(
      healthSummary: healthSummary,
      cycleCount: cycleCount,
      currentTemperature: currentTemperature,
    );

    logger.d('Battery health status: $batteryHealthStatus');

    return batteryHealthStatus;
  }

  @override
  Stream<BatteryHealthStatus> get healthStatusStream {
    StreamController<BatteryHealthStatus> controller =
        StreamController<BatteryHealthStatus>();
    Timer? healthPollingTimer;

    Future<void> pollHealthStatus() async {
      try {
        final healthStatus = await readHealthStatus();
        if (!controller.isClosed) {
          controller.add(healthStatus);
        }
      } catch (e) {
        logger.e('Error reading health status: $e');
      }
    }

    controller.onCancel = () {
      healthPollingTimer?.cancel();
    };

    controller.onListen = () {
      healthPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        unawaited(pollHealthStatus());
      });

      unawaited(pollHealthStatus());
    };

    return controller.stream;
  }
}
