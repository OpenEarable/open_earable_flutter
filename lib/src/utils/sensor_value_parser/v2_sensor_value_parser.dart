import 'dart:typed_data';

import '../sensor_scheme_parser/sensor_scheme_reader.dart';
import 'sensor_value_parser.dart';

class V2SensorValueParser extends SensorValueParser {
  @override
  List<Map<String, dynamic>> parse(ByteData data, List<SensorScheme> sensorSchemes) {
    int i = 0;

    // Header
    _requireBytes(data, i, 1, 'sensorId');
    final sensorId = data.getUint8(i);
    i += 1;

    // treat one extra byte as reserved/flags for V2 (safe no-op if unused).
    _requireBytes(data, i, 1, 'reserved/flags');
    i += 1;

    final scheme = sensorSchemes.firstWhere(
      (s) => s.sensorId == sensorId,
      orElse: () => throw FormatException('Unknown sensorId: $sensorId'),
    );

    _requireBytes(data, i, 8, 'timestamp');
    final baseTimestamp = data.getUint64(i, Endian.little);
    i += 8;

    // Precompute size of one component payload for efficiency.
    final compSizes = scheme.components.map((c) => c.type.size()).toList();
    final payloadSizePerSample = compSizes.fold<int>(0, (a, b) => a + b);
    const timestampSize = 8; // size of absolute timestamp
    const offsetSize = 2; // size of relative timestamp offset
    const headerSize = 2;

    if (data.lengthInBytes - headerSize - payloadSizePerSample < 0) {
      throw FormatException('Truncated frame: need at least ${timestampSize + offsetSize} bytes '
          'for first sample, have ${data.lengthInBytes - headerSize}.');
    }
    if ((data.lengthInBytes - headerSize - timestampSize) != payloadSizePerSample &&
        (data.lengthInBytes - headerSize - timestampSize - offsetSize) % payloadSizePerSample != 0) {
      throw FormatException('Truncated frame: have ${data.lengthInBytes - headerSize} bytes, '
          'which is not consistent with sample size $payloadSizePerSample, timestamp and offset sizes.');
    }

    int dataCount;
    if (data.lengthInBytes - headerSize - timestampSize == payloadSizePerSample) {
      dataCount = 1;
    } else {
      dataCount = (data.lengthInBytes - headerSize - timestampSize - offsetSize) ~/ payloadSizePerSample;
    }

    if (dataCount < 1) {
      throw FormatException('Invalid data count: $dataCount');
    }

    final int timeDiff = dataCount > 1 ? _getTimeDiff(data) : 0;

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

    // Parse additional samples (if any)
    for (int sampleIdx = 0; sampleIdx < dataCount; sampleIdx++) {
      int timeOffset = sampleIdx * timeDiff;
      final sample = _parseSample(
        data: data,
        startIndex: i,
        scheme: scheme,
        timestamp: baseTimestamp + timeOffset,
        compSizes: compSizes,
      );
      results.add(sample.map);
      i = sample.nextIndex;
    }

    return results;
  }
}

/// Helpers

dynamic _readValue(ByteData data, int index, ParseType t) {
  switch (t) {
    case ParseType.int8:
      return data.getInt8(index);
    case ParseType.uint8:
      return data.getUint8(index);
    case ParseType.int16:
      return data.getInt16(index, Endian.little);
    case ParseType.uint16:
      return data.getUint16(index, Endian.little);
    case ParseType.int32:
      return data.getInt32(index, Endian.little);
    case ParseType.uint32:
      return data.getUint32(index, Endian.little);
    case ParseType.float:
      return data.getFloat32(index, Endian.little);
    case ParseType.double:
      return data.getFloat64(index, Endian.little);
  }
}

void _requireBytes(ByteData data, int index, int needed, String ctx) {
  if (index + needed > data.lengthInBytes) {
    throw FormatException('Truncated frame while reading $ctx '
        '(need $needed bytes at $index, len=${data.lengthInBytes}).');
  }
}

class _ParsedSample {
  final Map<String, dynamic> map;
  final int nextIndex;
  _ParsedSample(this.map, this.nextIndex);
}

/// Gets the time difference in milliseconds from the given [data] ByteData.
/// The time diffenrence is stored as a 16-bit unsigned integer at the end of the [data].
int _getTimeDiff(ByteData data) {
  return data.getUint16(data.lengthInBytes - 2, Endian.little);
}

_ParsedSample _parseSample({
  required ByteData data,
  required int startIndex,
  required SensorScheme scheme,
  required int timestamp,
  required List<int> compSizes,
}) {
  int i = startIndex;

  // Prepare output structure
  final out = <String, dynamic>{
    'sensorId': scheme.sensorId,
    'sensorName': scheme.sensorName,
    'timestamp': timestamp,
  };

  // Ensure group maps + units exist
  Map<String, Map<String, dynamic>> groupMapCache = {};
  Map<String, String> ensureUnitsMap(String group) {
    final grp = groupMapCache[group] ??= <String, dynamic>{};
    if (grp['units'] == null) grp['units'] = <String, String>{};
    out[group] ??= grp;
    return (grp['units'] as Map<String, String>);
  }

  // Read components in scheme order
  for (final comp in scheme.components) {
    final parseType = comp.type;
    final sz = parseType.size();
    _requireBytes(data, i, sz, 'component ${comp.componentName}');
    final val = _readValue(data, i, parseType);
    i += sz;

    // install group and component
    out.putIfAbsent(comp.groupName, () => <String, dynamic>{'units': <String, String>{}});
    (out[comp.groupName] as Map<String, dynamic>)[comp.componentName] = val;

    // units
    final units = ensureUnitsMap(comp.groupName);
    units[comp.componentName] = comp.unitName;
  }

  return _ParsedSample(out, i);
}
