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

abstract class BatteryEnergyStatusService {
  Future<BatteryEnergyStatus> readEnergyStatus();

  Stream<BatteryEnergyStatus> get energyStatusStream;
}
