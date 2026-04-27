import 'dart:typed_data';

class SensorError {
  final int errorCode;
  final int sensorId;
  final int timestamp;
  final String message;

  SensorError({
    required this.errorCode,
    required this.sensorId,
    required this.timestamp,
    required this.message,
  });

  factory SensorError.fromBytes(Uint8List bytes) {
    if (bytes.length < 70) {
      throw Exception('Invalid error data length: ${bytes.length}');
    }

    return SensorError(
      errorCode: bytes[0],
      sensorId: bytes[1],
      timestamp: (bytes[5] << 24) | 
                 (bytes[4] << 16) | 
                 (bytes[3] << 8) | 
                 bytes[2],
      message: String.fromCharCodes(bytes.sublist(6, 70)).trim(),
    );
  }

  String get errorDescription {
    switch (errorCode) {
      case 0x01: return 'Sensor initialization failed';
      case 0x02: return 'Sensor read failed';
      case 0x03: return 'SD card error';
      case 0x04: return 'Audio playback failed';
      case 0x05: return 'BLE notification failed';
      case 0xFF: return 'Test notification';
      default: return 'Unknown error (code: ${errorCode.toRadixString(16)})';
    }
  }

  String get sensorName {
    switch (sensorId) {
      case 0: return 'IMU';
      case 1: return 'Barometer';
      case 2: return 'PPG';
      case 3: return 'Optic Temp';
      case 4: return 'Bone Conduction';
      case 5: return 'Microphone';
      default: return 'System';
    }
  }
  
  String get formattedMessage => '[$sensorName] $errorDescription: $message';
  
  @override
  String toString() => formattedMessage;
}