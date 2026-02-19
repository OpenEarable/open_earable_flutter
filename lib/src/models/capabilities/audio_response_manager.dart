/// An interface for managing audio response measurements.
abstract class AudioResponseManager {
  Future<Map<String, dynamic>> measureAudioResponse(
    Map<String, dynamic> parameters,
  );

  Future<Map<String, dynamic>> measureOuterAudioResponse({
    Map<String, dynamic> parameters = const {},
  });

  Future<Map<String, dynamic>> measureInnerAudioResponse({
    Map<String, dynamic> parameters = const {},
  });
}
