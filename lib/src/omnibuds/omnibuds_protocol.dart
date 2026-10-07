import 'dart:convert';

import '../models/capabilities/sensor.dart';
import '../models/capabilities/stereo_device.dart';

/// UUIDs observed in the official OmniBuds Android app 1.6.41.
abstract final class OmniBudsGatt {
  static const service = '00000a00-ae4a-11ed-afa1-0242ac120002';
  static const left = '00000a01-ae4a-11ed-afa1-0242ac120002';
  static const right = '00000a02-ae4a-11ed-afa1-0242ac120002';
  static const control = '00000a05-ae4a-11ed-afa1-0242ac120002';

  /// Both ears are addressed through the same BLE peripheral.
  static String characteristic(DevicePosition ear) =>
      ear == DevicePosition.left ? left : right;
}

/// Peripheral IDs with a raw sensor or vital-sign control in the vendor app.
enum OmniBudsSensorKind {
  accelerometer(0, 'Accelerometer', ['X', 'Y', 'Z'], 'g', [10, 25, 50, 100]),
  gyroscope(1, 'Gyroscope', ['X', 'Y', 'Z'], 'dps', [10, 25, 50, 100]),
  magnetometer(2, 'Magnetometer', ['X', 'Y', 'Z'], 'G', [10, 20, 50, 100]),
  ppg(5, 'PPG', ['Green', 'Red', 'Infrared'], 'raw', [25, 50, 100]),
  temperature(7, 'Temperature', ['Object'], '°C', [0.2]),
  heartRate(9, 'Heart Rate', ['Heart Rate'], 'bpm', []),
  heartRateVariability(10, 'Heart Rate Variability', ['HRV'], 'ms', []),
  oxygenSaturation(11, 'Blood Oxygen', ['SpO2'], '%', []),
  respirationRate(12, 'Respiration Rate', ['Respiration'], 'breaths/min', []);

  const OmniBudsSensorKind(
    this.peripheralId,
    this.label,
    this.axes,
    this.unit,
    this.rates,
  );

  final int peripheralId;
  final String label;
  final List<String> axes;
  final String unit;

  /// Selectable values in the vendor UI, not measured delivery guarantees.
  /// An empty list means the device manages the reporting interval.
  final List<double> rates;

  /// Encodes the rate value expected at configuration endpoint 1.
  String encodeRate(double hz) {
    final index = rates.indexOf(hz);
    if (index < 0) throw ArgumentError.value(hz, 'hz', 'Unsupported rate');
    if (peripheralId <= 2) return '$index';
    return hz == hz.roundToDouble() ? '${hz.toInt()}' : '$hz';
  }
}

/// A decoded notification, including messages not mapped to a typed sensor.
class OmniBudsMessage {
  /// Parses one complete GATT notification. No bytes are silently discarded.
  factory OmniBudsMessage.decode(DevicePosition ear, List<int> bytes) {
    if (bytes.length < 5 || bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid OmniBuds header');
    }
    final type = bytes[1] & 7;
    if (type > 2) throw FormatException('Unknown OmniBuds message type $type');
    if (type == 1 && bytes.length < 6) {
      throw const FormatException('Missing configuration endpoint');
    }
    final offset = type == 1 ? (bytes.length >= 7 ? 7 : 6) : 5;
    final text = utf8.decode(bytes.sublist(offset)).replaceAll('\u0000', '');
    return OmniBudsMessage._(
      ear,
      bytes[0],
      type,
      bytes[3],
      type == 1 ? bytes[5] : null,
      type == 1 && bytes.length >= 7 ? bytes[6] : null,
      text,
      List.unmodifiable(bytes),
    );
  }

  const OmniBudsMessage._(
    this.ear,
    this.peripheralId,
    this.type,
    this.metadata,
    this.endpoint,
    this.errorCode,
    this.text,
    this.bytes,
  );

  final DevicePosition ear;
  final int peripheralId;

  /// 0: event, 1: configuration, 2: sensor data.
  final int type;

  /// For motion data: rate index in high nibble, range index in low nibble.
  /// For PPG: sample rate in Hz. This is not a packet sequence counter.
  final int metadata;
  final int? endpoint;
  final int? errorCode;
  final String text;
  final List<int> bytes;
}

/// Encodes the configuration header followed by its UTF-8 textual value.
List<int> encodeOmniBudsConfiguration(
  int peripheralId,
  int endpoint, {
  String? value,
  int? errorCode,
}) {
  if (peripheralId < 0 ||
      peripheralId > 255 ||
      endpoint < 0 ||
      endpoint > 255) {
    throw ArgumentError('Peripheral and endpoint must be bytes');
  }
  if (errorCode != null && (errorCode < 0 || errorCode > 255)) {
    throw ArgumentError.value(errorCode, 'errorCode');
  }
  final data = utf8.encode(value ?? '');
  if (data.length > 254 || data.contains(0)) {
    throw ArgumentError('OmniBuds values must fit one message without NULs');
  }
  // The vendor time response includes an error byte but still uses 1 + text
  // length in this field. Match that wire format instead of inferring a size.
  return [
    peripheralId,
    value == null ? 1 : 9,
    1 + data.length,
    0,
    0,
    endpoint,
    if (errorCode != null) errorCode,
    ...data,
  ];
}

/// Converted sample plus the untouched values and notification that produced it.
class OmniBudsSensorValue extends SensorDoubleValue {
  /// Creates a timestamped sample. Timestamps are expressed in microseconds.
  OmniBudsSensorValue({
    required super.values,
    required super.timestamp,
    required this.rawValues,
    required this.message,
    required this.sampleIndex,
  });

  final List<double> rawValues;
  final OmniBudsMessage message;
  final int sampleIndex;
}

/// Converts the APK's CSV samples and expands batches without integer-ms drift.
List<OmniBudsSensorValue> decodeOmniBudsSamples(
  OmniBudsMessage message,
  OmniBudsSensorKind kind,
) {
  if (message.type != 2 || message.peripheralId != kind.peripheralId) {
    throw const FormatException('Wrong sensor message');
  }
  final fields = message.text.split(',');
  final timeMs = int.tryParse(fields.first);
  if (timeMs == null || timeMs < 0 || timeMs > 9007199254740) {
    throw const FormatException('Invalid OmniBuds millisecond timestamp');
  }
  final numbers = fields.skip(1).map((field) {
    final value = double.tryParse(field);
    if (value == null || !value.isFinite) {
      throw const FormatException('Invalid OmniBuds numeric sample');
    }
    return value;
  }).toList();
  final width = kind.axes.length;
  if (numbers.isEmpty || numbers.length % width != 0) {
    throw const FormatException('Incomplete OmniBuds sensor sample');
  }
  double? hz;
  double scale = 1;
  if (kind.peripheralId <= 2) {
    final rateIndex = message.metadata >> 4;
    final rangeIndex = message.metadata & 15;
    if (rateIndex > 3) throw const FormatException('Unknown motion rate');
    // The APK decoder says 12 Hz for code 0 although its UI says 10 Hz.
    // Preserve its decoder behaviour and document the unresolved discrepancy.
    hz = (kind == OmniBudsSensorKind.magnetometer
        ? [10.0, 20.0, 50.0, 100.0]
        : [12.0, 25.0, 50.0, 100.0])[rateIndex];
    if (kind == OmniBudsSensorKind.accelerometer) {
      if (rangeIndex > 3) throw const FormatException('Unknown accel range');
      scale = [0.061, 0.122, 0.244, 0.488][rangeIndex] / 1000;
    } else if (kind == OmniBudsSensorKind.gyroscope) {
      if (rangeIndex > 4) throw const FormatException('Unknown gyro range');
      scale = [4.375, 8.75, 17.5, 35.0, 70.0][rangeIndex] / 1000;
    } else {
      scale = 0.0015;
    }
  } else if (kind == OmniBudsSensorKind.ppg) {
    hz = message.metadata.toDouble();
    if (!kind.rates.contains(hz)) {
      throw const FormatException('Unknown PPG rate');
    }
  }
  if (hz == null && numbers.length != width) {
    // The app only defines batch timing for motion and PPG. Do not fabricate
    // timestamps for multiple scalar values or vendor-specific auxiliary data.
    throw const FormatException('Unsupported scalar payload; inspect messages');
  }
  return [
    for (var i = 0; i < numbers.length ~/ width; i++)
      OmniBudsSensorValue(
        values: List.unmodifiable(
          numbers.sublist(i * width, (i + 1) * width).map((v) => v * scale),
        ),
        timestamp:
            timeMs * 1000 + (hz == null ? 0 : (i * 1000000 / hz).round()),
        rawValues:
            List.unmodifiable(numbers.sublist(i * width, (i + 1) * width)),
        message: message,
        sampleIndex: i,
      ),
  ];
}
