import 'package:example/widgets/sensor_chart.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class AllSensorChartsWidget extends StatelessWidget {
  final SensorManager sensorManager;

  const AllSensorChartsWidget({Key? key, required this.sensorManager})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 500,
      child: DefaultTabController(
        length: sensorManager.sensors.length,
        child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabs: sensorManager.sensors.map((sensor) {
            return Tab(text: sensor.sensorName);
            }).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: sensorManager.sensors.map((sensor) {
              return SensorChart(sensor: sensor);
              }).toList(),
            ),
            ),
          ],
        ),
      )
    );
  }
}
