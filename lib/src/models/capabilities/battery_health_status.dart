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

abstract class BatteryHealthStatusService {
  Future<BatteryHealthStatus> readHealthStatus();

  Stream<BatteryHealthStatus> get healthStatusStream;
}
