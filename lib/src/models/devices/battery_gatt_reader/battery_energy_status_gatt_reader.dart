import 'dart:async';
import 'dart:math';

import '../../../../open_earable_flutter.dart' show logger;
import '../../capabilities/battery_energy_status.dart';
import '../bluetooth_wearable.dart';

const String _batteryEnergyStatusCharacteristicUuid = "2BF0";
const String _batteryServiceUuid = "180F";

mixin BatteryEnergyStatusGattReader on BluetoothWearable implements BatteryEnergyStatusService {
  @override
  Future<BatteryEnergyStatus> readEnergyStatus() async {
    List<int> energyStatusList = await bleManager.read(
      deviceId: discoveredDevice.id,
      serviceId: _batteryServiceUuid,
      characteristicId: _batteryEnergyStatusCharacteristicUuid,
    );

    logger.t("Battery energy status bytes: $energyStatusList");

    if (energyStatusList.length != 7) {
      throw StateError(
        'Battery energy status characteristic expected 7 values, but got ${energyStatusList.length}',
      );
    }

    int rawVoltage = (energyStatusList[2] << 8) | energyStatusList[1];
    double voltage = _convertSFloat(rawVoltage);

    int rawAvailableCapacity = (energyStatusList[4] << 8) | energyStatusList[3];
    double availableCapacity = _convertSFloat(rawAvailableCapacity);

    int rawChargeRate = (energyStatusList[6] << 8) | energyStatusList[5];
    double chargeRate = _convertSFloat(rawChargeRate);

    BatteryEnergyStatus batteryEnergyStatus = BatteryEnergyStatus(
      voltage: voltage,
      availableCapacity: availableCapacity,
      chargeRate: chargeRate,
    );

    logger.d('Battery energy status: $batteryEnergyStatus');

    return batteryEnergyStatus;
  }

  double _convertSFloat(int rawBits) {
    int exponent = ((rawBits & 0xF000) >> 12) - 16;
    int mantissa = rawBits & 0x0FFF;

    if (mantissa >= 0x800) {
      mantissa = -((0x1000) - mantissa);
    }
    logger.t("Exponent: $exponent, Mantissa: $mantissa");
    double result = mantissa.toDouble() * pow(10.0, exponent.toDouble());
    return result;
  }

  @override
  Stream<BatteryEnergyStatus> get energyStatusStream {
    StreamController<BatteryEnergyStatus> controller =
        StreamController<BatteryEnergyStatus>();
    Timer? energyPollingTimer;

    controller.onCancel = () {
      energyPollingTimer?.cancel();
    };

    controller.onListen = () {
      energyPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        readEnergyStatus().then((energyStatus) {
          controller.add(energyStatus);
        }).catchError((e) {
          logger.e('Error reading energy status: $e');
        });
      });

      readEnergyStatus().then((energyStatus) {
        controller.add(energyStatus);
      }).catchError((e) {
        logger.e('Error reading energy status: $e');
      });
    };

    return controller.stream;
  }
}
