import 'dart:async';

import '../../../../open_earable_flutter.dart' show logger;
import '../../capabilities/battery_level_status.dart';
import '../bluetooth_wearable.dart';

const String _batteryLevelStatusCharacteristicUuid = "2BED";
const String _batteryServiceUuid = "180F";

mixin BatteryLevelStatusServiceGattReader on BluetoothWearable
    implements BatteryLevelStatusService {
  @override
  Future<BatteryPowerStatus> readPowerStatus() async {
    List<int> powerStateList = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryLevelStatusCharacteristicUuid,
    );

    if (powerStateList.length < 3) {
      throw StateError(
          'Battery power status requires flags and two state bytes',);
    }
    int powerState = powerStateList[1] | (powerStateList[2] << 8);
    logger.d("Battery power status bits: ${powerState.toRadixString(2)}");

    bool batteryPresent = powerState & 0x1 != 0;

    int wiredExternalPowerSourceConnectedRaw = (powerState >> 1) & 0x3;
    ExternalPowerSourceConnected wiredExternalPowerSourceConnected =
        wiredExternalPowerSourceConnectedRaw <
                ExternalPowerSourceConnected.values.length
            ? ExternalPowerSourceConnected
                .values[wiredExternalPowerSourceConnectedRaw]
            : ExternalPowerSourceConnected.unknown;

    int wirelessExternalPowerSourceConnectedRaw = (powerState >> 3) & 0x3;
    ExternalPowerSourceConnected wirelessExternalPowerSourceConnected =
        wirelessExternalPowerSourceConnectedRaw <
                ExternalPowerSourceConnected.values.length
            ? ExternalPowerSourceConnected
                .values[wirelessExternalPowerSourceConnectedRaw]
            : ExternalPowerSourceConnected.unknown;

    int chargeStateRaw = (powerState >> 5) & 0x3;
    ChargeState chargeState = ChargeState.values[chargeStateRaw];

    int chargeLevelRaw = (powerState >> 7) & 0x3;
    BatteryChargeLevel chargeLevel = BatteryChargeLevel.values[chargeLevelRaw];

    int chargingTypeRaw = (powerState >> 9) & 0x7;
    BatteryChargingType chargingType =
        chargingTypeRaw < BatteryChargingType.values.length
            ? BatteryChargingType.values[chargingTypeRaw]
            : BatteryChargingType.unknown;

    int chargingFaultReasonRaw = (powerState >> 12) & 0x7;
    List<ChargingFaultReason> chargingFaultReason = [];
    if ((chargingFaultReasonRaw & 0x1) != 0) {
      chargingFaultReason.add(ChargingFaultReason.battery);
    }
    if ((chargingFaultReasonRaw & 0x2) != 0) {
      chargingFaultReason.add(ChargingFaultReason.externalPowerSource);
    }
    if ((chargingFaultReasonRaw & 0x4) != 0) {
      chargingFaultReason.add(ChargingFaultReason.other);
    }

    BatteryPowerStatus batteryPowerStatus = BatteryPowerStatus(
      batteryPresent: batteryPresent,
      wiredExternalPowerSourceConnected: wiredExternalPowerSourceConnected,
      wirelessExternalPowerSourceConnected:
          wirelessExternalPowerSourceConnected,
      chargeState: chargeState,
      chargeLevel: chargeLevel,
      chargingType: chargingType,
      chargingFaultReason: chargingFaultReason,
    );

    logger.d('Battery power status: $batteryPowerStatus');

    return batteryPowerStatus;
  }

  @override
  Stream<BatteryPowerStatus> get powerStatusStream {
    StreamController<BatteryPowerStatus> controller =
        StreamController<BatteryPowerStatus>();
    Timer? powerPollingTimer;

    Future<void> pollPowerStatus() async {
      try {
        final powerStatus = await readPowerStatus();
        if (!controller.isClosed) {
          controller.add(powerStatus);
        }
      } catch (e) {
        logger.e('Error reading power status: $e');
      }
    }

    controller.onCancel = () {
      powerPollingTimer?.cancel();
    };

    controller.onListen = () {
      powerPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        unawaited(pollPowerStatus());
      });

      unawaited(pollPowerStatus());
    };

    return controller.stream;
  }
}
