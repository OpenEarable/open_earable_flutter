import 'dart:typed_data';

import '../../../open_earable_flutter.dart' show logger;
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
    final firstSampleSize = 8 + payloadSizePerSample; // absolute timestamp + payload
    final subsequentSampleSize = 2 + payloadSizePerSample; // u16 offset + payload
    const headerSize = 2;

    if (data.lengthInBytes - headerSize - firstSampleSize < 0) {
      throw FormatException('Truncated frame: need at least $firstSampleSize bytes '
          'for first sample, have ${data.lengthInBytes - headerSize}.');
    }
    if (((data.lengthInBytes - headerSize - firstSampleSize) % subsequentSampleSize) != 0) {
      logger.e("Data length not aligned for subsequent samples. "
          "Data len: ${data.lengthInBytes}, headerSize: $headerSize, firstSampleSize: $firstSampleSize, subsequentSampleSize: $subsequentSampleSize");
      throw FormatException('Truncated frame: subsequent samples must be '
          '$subsequentSampleSize bytes each, have ${data.lengthInBytes - headerSize - firstSampleSize}.');
    }

    // Parse first (anchor) sample
    final results = <Map<String, dynamic>>[];
    final firstSample = _parseSample(
      data: data,
      startIndex: i,
      scheme: scheme,
      absoluteTimestamp: baseTimestamp,
      compSizes: compSizes,
      hasOffsetPrefix: false,
    );
    results.add(firstSample.map);
    i = firstSample.nextIndex;

    // Parse additional samples (if any)
    while (i < data.lengthInBytes) {
      // If not enough bytes for even the offset + payload, stop gracefully.
      final remaining = data.lengthInBytes - i;
      if (remaining < subsequentSampleSize) break;

      final sample = _parseSample(
        data: data,
        startIndex: i,
        scheme: scheme,
        absoluteTimestamp: baseTimestamp,
        compSizes: compSizes,
        hasOffsetPrefix: true,
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

_ParsedSample _parseSample({
  required ByteData data,
  required int startIndex,
  required SensorScheme scheme,
  required int absoluteTimestamp,
  required List<int> compSizes,
  required bool hasOffsetPrefix,
}) {
  int i = startIndex;
  late int timestamp;

  if (hasOffsetPrefix) {
    _requireBytes(data, i, 2, 'timestamp offset');
    final offset = data.getUint16(i, Endian.little);
    i += 2;
    timestamp = absoluteTimestamp + offset;
  } else {
    // First sample already read base ts before; here we just reuse it.
    timestamp = absoluteTimestamp;
  }

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
