import 'dart:async';

import '../../../../open_earable_flutter.dart' show logger;
import '../../capabilities/battery_level_status.dart';
import '../bluetooth_wearable.dart';

const String _batteryLevelStatusCharacteristicUuid = "2BED";
const String _batteryServiceUuid = "180F";

mixin BatteryLevelStatusServiceGattReader on BluetoothWearable implements BatteryLevelStatusService {
  @override
  Future<BatteryPowerStatus> readPowerStatus() async {
    List<int> powerStateList = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryLevelStatusCharacteristicUuid,
    );

    int powerState = (powerStateList[1] << 8) | powerStateList[2];
    logger.d("Battery power status bits: ${powerState.toRadixString(2)}");

    bool batteryPresent = powerState >> 15 & 0x1 != 0;

    int wiredExternalPowerSourceConnectedRaw = (powerState >> 13) & 0x3;
    ExternalPowerSourceConnected wiredExternalPowerSourceConnected =
        ExternalPowerSourceConnected
            .values[wiredExternalPowerSourceConnectedRaw];

    int wirelessExternalPowerSourceConnectedRaw = (powerState >> 11) & 0x3;
    ExternalPowerSourceConnected wirelessExternalPowerSourceConnected =
        ExternalPowerSourceConnected
            .values[wirelessExternalPowerSourceConnectedRaw];

    int chargeStateRaw = (powerState >> 9) & 0x3;
    ChargeState chargeState = ChargeState.values[chargeStateRaw];

    int chargeLevelRaw = (powerState >> 7) & 0x3;
    BatteryChargeLevel chargeLevel = BatteryChargeLevel.values[chargeLevelRaw];

    int chargingTypeRaw = (powerState >> 5) & 0x7;
    BatteryChargingType chargingType =
        BatteryChargingType.values[chargingTypeRaw];

    int chargingFaultReasonRaw = (powerState >> 2) & 0x5;
    List<ChargingFaultReason> chargingFaultReason = [];
    if ((chargingFaultReasonRaw & 0x1) != 0) {
      chargingFaultReason.add(ChargingFaultReason.other);
    }
    if ((chargingFaultReasonRaw & 0x2) != 0) {
      chargingFaultReason.add(ChargingFaultReason.externalPowerSource);
    }
    if ((chargingFaultReasonRaw & 0x4) != 0) {
      chargingFaultReason.add(ChargingFaultReason.battery);
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

    controller.onCancel = () {
      powerPollingTimer?.cancel();
    };

    controller.onListen = () {
      powerPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readPowerStatus().then((powerStatus) {
          controller.add(powerStatus);
        }).catchError((e) {
          logger.e('Error reading power status: $e');
        });
      });

      readPowerStatus().then((powerStatus) {
        controller.add(powerStatus);
      }).catchError((e) {
        logger.e('Error reading power status: $e');
      });
    };

    return controller.stream;
  }
}
