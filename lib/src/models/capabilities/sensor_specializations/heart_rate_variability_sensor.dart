import 'dart:async';
import 'dart:math';

import '../sensor.dart';

class HeartRateVariabilitySensor extends Sensor<HeartRateVariabilitySensorValue> {
  // Range to use for calculations
  static const int _hrvIntervalMs = 60000;

  final Stream<List<int>> _rrIntervalsMsStream;
  final _streamController =
      StreamController<HeartRateVariabilitySensorValue>.broadcast();

  final List<_RrIntervalEntry> _rrIntervalEntries = [];

  HeartRateVariabilitySensor({
    super.relatedConfigurations = const [],
    required Stream<List<int>> rrIntervalsMsStream,
  })  : _rrIntervalsMsStream = rrIntervalsMsStream,
        super(
          sensorName: 'HRV',
          chartTitle: 'Heart Rate Variability',
          shortChartTitle: 'HRV',
        ) {
    _readRrIntervalStream();
  }

  void _addAndUpdateIntervals(int timestamp, List<int> rrIntervalsMs) {
    _rrIntervalEntries.add(
      _RrIntervalEntry(
        timestamp: timestamp,
        rrIntervalsMs: rrIntervalsMs,
      ),
    );
    _rrIntervalEntries
        .removeWhere((entry) => !entry.inInterval(timestamp, _hrvIntervalMs));
  }

  List<int> _getFlattenedRrIntervalsMs() {
    return _rrIntervalEntries.expand((entry) => entry.rrIntervalsMs).toList();
  }

  void _readRrIntervalStream() {
    _rrIntervalsMsStream.listen((rrIntervalsMs) {
      int timestamp = DateTime.now().millisecondsSinceEpoch;
      _addAndUpdateIntervals(timestamp, rrIntervalsMs);
      List<int> allRecentRrIntervalsMs = _getFlattenedRrIntervalsMs();

      HeartRateVariabilitySensorValue value = HeartRateVariabilitySensorValue(
        rrIntervalsMs: rrIntervalsMs,
        rmssd: _calculateRmssd(allRecentRrIntervalsMs),
        sdnn: _calculateSDNN(allRecentRrIntervalsMs),
        timestamp: BigInt.from(timestamp),
      );
      _streamController.add(value);
    });
  }

  double _calculateRmssd(List<int> rrIntervalsMs) {
    if (rrIntervalsMs.length < 2) {
      // Not enough data
      return 0.0;
    }

    List<int> differences = List.generate(
      rrIntervalsMs.length - 1,
      (i) => rrIntervalsMs[i + 1] - rrIntervalsMs[i],
    );

    double sumOfSquares =
        differences.fold(0.0, (sum, diff) => sum + (diff * diff));

    return sqrt(sumOfSquares / (differences.length));
  }

  double _calculateSDNN(List<int> rrIntervals) {
    if (rrIntervals.length < 2) {
      // Not enough data
      return 0.0;
    }

    double mean = rrIntervals.reduce((a, b) => a + b) / rrIntervals.length;

    double sumSquaredDifferences = rrIntervals
        .map((rr) => pow(rr - mean, 2).toDouble())
        .reduce((a, b) => a + b);

    double variance = sumSquaredDifferences / (rrIntervals.length - 1);

    return sqrt(variance);
  }

  @override
  List<String> get axisNames => ['rMSSD (60s)', 'SDNN (60s)'];

  @override
  List<String> get axisUnits => ['', ''];

  @override
  int get axisCount => 2;

  @override
  Stream<HeartRateVariabilitySensorValue> get sensorStream =>
      _streamController.stream;
}

class _RrIntervalEntry {
  final List<int> rrIntervalsMs;
  final int timestamp;

  _RrIntervalEntry({
    required this.timestamp,
    required this.rrIntervalsMs,
  });

  bool inInterval(int timestamp, int interval) {
    return timestamp - this.timestamp <= interval;
  }
}

class HeartRateVariabilitySensorValue extends SensorDoubleValue {
  final List<int> _rrIntervalsMs;
  final double rmssd;
  final double sdnn;

  HeartRateVariabilitySensorValue({
    required List<int> rrIntervalsMs,
    required this.rmssd,
    required this.sdnn,
    required super.timestamp,
  })  : _rrIntervalsMs = rrIntervalsMs,
        super(
          values: [rmssd, sdnn],
        );

  /// Get the latest new rr intervals in milliseconds
  List<int> get rrIntervalsMs => _rrIntervalsMs;
}
