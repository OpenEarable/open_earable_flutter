import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:community_charts_flutter/community_charts_flutter.dart' as charts;

class SensorChart extends StatefulWidget {
  final Sensor sensor;

  const SensorChart({Key? key, required this.sensor}) : super(key: key);

  @override
  State<SensorChart> createState() => _SensorChartState();
}

class _SensorChartState extends State<SensorChart> {
  List<charts.Series<ChartData, int>> _chartData = [];
  final List<ChartData> _dataPoints = [];

  @override
  void initState() {
    super.initState();
    _listenToSensorStream();
  }

  void _listenToSensorStream() {
    widget.sensor.sensorStream.listen((sensorValue) {
      setState(() {
        // Add new data points
        for (int i = 0; i < widget.sensor.axisCount; i++) {
          _dataPoints.add(ChartData(sensorValue.timestamp, sensorValue.values[i], widget.sensor.axisNames[i]));
        }

        // Remove data older than 5 seconds
        int cutoffTime = sensorValue.timestamp - 5000;
        _dataPoints.removeWhere((data) => data.time < cutoffTime);

        // Update chart data
        _chartData = [
          for (int i = 0; i < widget.sensor.axisCount; i++)
            charts.Series<ChartData, int>(
              id: widget.sensor.axisNames[i],
              colorFn: (_, __) => charts.MaterialPalette.blue.makeShades(widget.sensor.axisCount)[i],
              domainFn: (ChartData point, _) => point.time, // X-axis (timestamp)
              measureFn: (ChartData point, _) => point.value, // Y-axis (sensor value)
              data: _dataPoints.where((point) => point.axisName == widget.sensor.axisNames[i]).toList(),
            ),
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine min/max range for X and Y axes
    final xValues = _dataPoints.map((e) => e.time).toList();
    final yValues = _dataPoints.map((e) => e.value).toList();

    final int? xMin = xValues.isNotEmpty ? xValues.reduce((a, b) => a < b ? a : b) : null;
    final int? xMax = xValues.isNotEmpty ? xValues.reduce((a, b) => a > b ? a : b) : null;

    final double? yMin = yValues.isNotEmpty ? yValues.reduce((a, b) => a < b ? a : b) : null;
    final double? yMax = yValues.isNotEmpty ? yValues.reduce((a, b) => a > b ? a : b) : null;

    return Column(
      children: [
        Expanded(
          child: charts.LineChart(
            _chartData,
            animate: true,
            domainAxis: charts.NumericAxisSpec(
              viewport: xMin != null && xMax != null
                  ? charts.NumericExtents(xMin.toDouble(), xMax.toDouble())
                  : null,
              tickProviderSpec: const charts.BasicNumericTickProviderSpec(desiredTickCount: 5),
            ),
            primaryMeasureAxis: charts.NumericAxisSpec(
              viewport: yMin != null && yMax != null
                  ? charts.NumericExtents(yMin, yMax)
                  : null,
              tickProviderSpec: const charts.BasicNumericTickProviderSpec(desiredTickCount: 5),
            ),
            behaviors: [
              charts.SeriesLegend(),
              charts.ChartTitle('Time (ms)', behaviorPosition: charts.BehaviorPosition.bottom),
              charts.ChartTitle('Value', behaviorPosition: charts.BehaviorPosition.start),
            ],
          ),
        ),
      ],
    );
  }
}

class ChartData {
  final int time; // Timestamp in milliseconds
  final double value; // Sensor value
  final String axisName; // Name of the axis

  ChartData(this.time, this.value, this.axisName);
}