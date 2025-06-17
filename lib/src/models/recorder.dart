import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class Recorder {
  final List<String> _columns;
  IOSink? _sink;
  StreamSubscription<SensorValue>? _subscription;
  bool _isRecording = false;

  Recorder({
    required List<String> columns,
  }) : _columns = ['timestamp', ...columns];

  /// Starts the recording process.
  /// It writes sensor data to a file at the specified [filepath].
  /// If [append] is true, it appends to the existing file; otherwise, it creates a new file.
  /// Returns the [File] object for the recorded file.
  /// Throws an exception if recording is already in progress.
  Future<File> start({
    required String filepath,
    required Stream<SensorValue> inputStream,
    bool append = false,
  }) async {
    if (_isRecording) throw Exception('Recording is already in progress.');

    _isRecording = true;
    final file = File(filepath);

    await file.parent.create(recursive: true);

    final exists = await file.exists();
    _sink = file.openWrite(
      mode: append && exists ? FileMode.append : FileMode.write,
    );

    if (!append || !exists) {
      _sink!.writeln(_columns.join(','));
    }

    _subscription = inputStream.listen(
      (SensorValue value) {
        final row = _formatSensorValue(value);
        _sink!.writeln(row);
      },
      onDone: stop,
      onError: (error) {
        debugPrint('Recording error: $error');
        stop();
      },
    );

    return file;
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
