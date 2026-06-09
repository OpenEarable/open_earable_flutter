import 'dart:typed_data';

enum DeviceErrorLevel {
  info(0, 'Info'),
  warning(1, 'Warning'),
  error(2, 'Error'),
  fatal(3, 'Fatal');

  final int value;
  final String label;

  const DeviceErrorLevel(this.value, this.label);

  static DeviceErrorLevel fromByte(int value) {
    return DeviceErrorLevel.values.firstWhere(
      (level) => level.value == value,
      orElse: () => DeviceErrorLevel.error,
    );
  }
}

class SensorError {
  static const int payloadLength = 57;
  static const int payloadVersion = 1;

  final DeviceErrorLevel level;
  final int errorCode;
  final int sensorId;
  final int timestamp;
  final String message;

  SensorError({
    this.level = DeviceErrorLevel.error,
    required this.errorCode,
    required this.sensorId,
    required this.timestamp,
    required this.message,
  });

  factory SensorError.fromBytes(Uint8List bytes) {
    if (bytes.length < payloadLength) {
      throw Exception('Invalid error data length: ${bytes.length}');
    }

    final byteData = ByteData.sublistView(bytes);
    final version = byteData.getUint8(0);
    if (version != payloadVersion) {
      throw Exception('Unsupported error payload version: $version');
    }

    final messageBytes = bytes.sublist(9, payloadLength);
    final nullIndex = messageBytes.indexOf(0);
    final trimmedMessageBytes =
        nullIndex >= 0 ? messageBytes.sublist(0, nullIndex) : messageBytes;

    return SensorError(
      level: DeviceErrorLevel.fromByte(byteData.getUint8(1)),
      errorCode: byteData.getUint16(2, Endian.little),
      sensorId: byteData.getUint8(4),
      timestamp: byteData.getUint32(5, Endian.little),
      message: String.fromCharCodes(trimmedMessageBytes).trim(),
    );
  }

  String get errorDescription {
    switch (errorCode) {
      case 0x0001:
        return 'SD card removed';
      case 0x0002:
        return 'SD card not mounted';
      case 0x0003:
        return 'SD card mount failed';
      case 0x0004:
        return 'SD card file open failed';
      case 0x0005:
        return 'SD card write failed';
      case 0x0006:
        return 'SD card header write failed';
      case 0x0007:
        return 'SD card flush failed';
      case 0x0008:
        return 'SD card buffer full';
      case 0x0009:
        return 'SD card close failed';
      case 0x0101:
        return 'Sensor queue full';
      case 0x0102:
        return 'Sensor initialization failed';
      case 0x0103:
        return 'Sensor read failed';
      case 0x0104:
        return 'Invalid sensor sample rate';
      case 0x0105:
        return 'Sensor not found';
      case 0x0106:
        return 'Sensor configuration queue full';
      case 0x0201:
        return 'BLE notification failed';
      case 0x0301:
        return 'Firmware fatal error';
      default:
        return 'Unknown code 0x${errorCode.toRadixString(16).padLeft(4, '0')}';
    }
  }

  String get sensorName {
    switch (sensorId) {
      case 0x00:
        return 'IMU';
      case 0x01:
        return 'Temp/Barometer';
      case 0x02:
        return 'Microphone';
      case 0x04:
        return 'PPG';
      case 0x05:
        return 'Pulse oximeter';
      case 0x06:
        return 'Optical temperature';
      case 0x07:
        return 'Bone conduction';
      case 0xFF:
        return 'System';
      default:
        return 'Source 0x${sensorId.toRadixString(16).padLeft(2, '0')}';
    }
  }

  String get formattedMessage {
    final detail =
        message.isEmpty ? errorDescription : '$errorDescription: $message';
    return '${level.label}: [$sensorName] $detail';
  }

  @override
  String toString() => formattedMessage;
}
