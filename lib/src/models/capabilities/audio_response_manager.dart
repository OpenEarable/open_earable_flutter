/// An interface for managing audio response measurements.
abstract class AudioResponseManager {
  Future<Map<String, dynamic>> measureAudioResponse(Map<String, dynamic> parameters);
}
