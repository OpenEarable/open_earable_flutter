import '../configurable_sensor_configuration.dart';

abstract interface class Range {
  const Range();
}

enum GyroRange implements Range {
  range250DPS,
  range500DPS,
  range1000DPS,
  range2000DPS,
}

enum AccelRange implements Range {
  range2G,
  range4G,
  range8G,
  range16G,
}

class SensorRangeOption<R extends Range> extends SensorConfigurationOption {
  final R range;

  const SensorRangeOption({required super.name, required this.range});
}
