abstract class BatteryService {
  /// Reads the battery percentage of the device.
  /// The value is between 0 and 100.
  Future<int> readBatteryPercentage();

  Stream<int> get batteryPercentageStream;
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

enum BatteryChargingType {
  unknown,
  constantCurrent,
  constantVoltage,
  trickle,
  float,
}

enum ChargingFaultReason {
  battery,
  externalPowerSource,
  other,
}

abstract class ExtendedBatteryService extends BatteryService {
  Future<BatteryEnergyStatus> readEnergyStatus();

  Future<BatteryHealthStatus> readHealthStatus();

  Future<BatteryPowerStatus> readPowerStatus();

  Stream<BatteryPowerStatus> get powerStatusStream;
  Stream<BatteryEnergyStatus> get energyStatusStream;
  Stream<BatteryHealthStatus> get healthStatusStream;
}

class BatteryEnergyStatus {
  final double voltage;
  final double availableCapacity;
  final double chargeRate;

  const BatteryEnergyStatus({
    required this.voltage,
    required this.availableCapacity,
    required this.chargeRate,
  });

  @override
  String toString() {
    return 'BatteryEnergyStatus(voltage: $voltage, '
        'availableCapacity: $availableCapacity, '
        'chargeRate: $chargeRate)';
  }
}

class BatteryHealthStatus {
  /// The percentage of the battery health.
  final int healthSummary;
  final int cycleCount;
  final int currentTemperature;

  const BatteryHealthStatus({
    required this.healthSummary,
    required this.cycleCount,
    required this.currentTemperature,
  });

  @override
  String toString() {
    return 'BatteryHealthStatus(healthSummary: $healthSummary, '
        'cycleCount: $cycleCount, '
        'currentTemperature: $currentTemperature)';
  }
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
