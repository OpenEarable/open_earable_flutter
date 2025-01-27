abstract class BatteryLevelService {
  /// Reads the battery percentage of the device.
  /// The value is between 0 and 100.
  Future<int> readBatteryPercentage();

  Stream<int> get batteryPercentageStream;
}
