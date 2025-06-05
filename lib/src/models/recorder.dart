import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart'; // Assuming SensorValue is from here
import 'package:path_provider/path_provider.dart';

class Recorder {
  final List<String> _columns;
  IOSink? _sink;
  StreamSubscription<SensorValue>? _subscription;
  bool _isRecording = false;

  Recorder({
    required List<String> columns,
  }) : _columns = columns;

  Future<String> _getPublicDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Starts the recording process.
  void start({
    required String filepath,
    required Stream<SensorValue> inputStream,
    bool append = false,
  }) async {
    if (_isRecording) return;

    _isRecording = true;
    final publicDirectory = await _getPublicDirectory();
    final fullPath = '$publicDirectory/$filepath';
    final file = File(fullPath);

    final exists = await file.exists();
    _sink = file.openWrite(mode: append && exists ? FileMode.append : FileMode.write);

    // Write header only if not appending or file didn't exist
    if (!append || !exists) {
      _sink!.writeln(_columns.join(','));
    }

    _subscription = inputStream.listen((SensorValue value) {
      final row = _formatSensorValue(value);
      _sink!.writeln(row);
    }, onDone: stop, onError: (error) {
      debugPrint('Recording error: $error');
      stop();
    },);
  }

  /// Stops the recording process.
  void stop() async {
    if (!_isRecording) return;
    _isRecording = false;

    await _subscription?.cancel();
    await _sink?.flush();
    await _sink?.close();

    _subscription = null;
    _sink = null;
  }

  String _formatSensorValue(SensorValue value) {
    final values = <String>[
      value.timestamp.toString(),
      ...value.valueStrings,
    ];

    return values.join(',');
  }
}
