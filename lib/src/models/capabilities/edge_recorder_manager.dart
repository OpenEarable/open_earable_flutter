abstract class EdgeRecorderManager {
  Future<String> get filePrefix;
  Future<void> setFilePrefix(String prefix);
}
