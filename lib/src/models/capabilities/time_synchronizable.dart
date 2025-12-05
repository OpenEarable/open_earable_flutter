/// Defines an interface for objects that can be synchronized with a time source.
abstract class TimeSynchronizable {
  bool get isTimeSynchronized;

  Future<void> synchronizeTime();
}
