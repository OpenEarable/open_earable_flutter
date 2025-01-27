enum BatteryChargingType {
  unknown,
  constantCurrent,
  constantVoltage,
  trickle,
  float,
}

enum ExternalPowerSourceConnected {
  no,
  yes,
  unknown,
}

enum ChargeState {
  unknown,
  charging,
  dischargingActive,
  dischargingInactive,
}

enum BatteryChargeLevel {
  unknown,
  good,
  low,
  critical,
}

enum ChargingFaultReason {
  battery,
  externalPowerSource,
  other,
}

class BatteryPowerStatus {
  final bool batteryPresent;
  final ExternalPowerSourceConnected wiredExternalPowerSourceConnected;
  final ExternalPowerSourceConnected wirelessExternalPowerSourceConnected;
  final ChargeState chargeState;
  final BatteryChargeLevel chargeLevel;
  final BatteryChargingType chargingType;
  final List<ChargingFaultReason> chargingFaultReason;

  const BatteryPowerStatus({
    required this.batteryPresent,
    required this.wiredExternalPowerSourceConnected,
    required this.wirelessExternalPowerSourceConnected,
    required this.chargeState,
    required this.chargeLevel,
    required this.chargingType,
    required this.chargingFaultReason,
  });

  @override
  String toString() {
    return 'BatteryPowerStatus(batteryPresent: $batteryPresent, '
        'wiredExternalPowerSourceConnected: $wiredExternalPowerSourceConnected, '
        'wirelessExternalPowerSourceConnected: $wirelessExternalPowerSourceConnected, '
        'chargeState: $chargeState, '
        'chargeLevel: $chargeLevel, '
        'chargingType: $chargingType, '
        'chargingFaultReason: $chargingFaultReason)';
  }
}

abstract class BatteryLevelStatusService {
  Future<BatteryPowerStatus> readPowerStatus();

  Stream<BatteryPowerStatus> get powerStatusStream;
}
