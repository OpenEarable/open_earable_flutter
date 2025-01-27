import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class SensorView extends StatelessWidget {
  final Sensor sensor;

  const SensorView({Key? key, required this.sensor}) : super(key: key);

  static List<SensorView>? createSensorViews(Wearable wearable) {
    if (wearable is SensorManager) {
      final sensorManager = wearable as SensorManager;
      return sensorManager.sensors
          .map((sensor) => SensorView(sensor: sensor))
          .toList();
    } else {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sensor.chartTitle} (${sensor.sensorName}):',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
          child: StreamBuilder<SensorValue>(
            stream: sensor.sensorStream,
            builder: (context, snapshot) {
              List<String> renderedValues = [];
              if (snapshot.hasData) {
                final sensorValue = snapshot.data!;
                renderedValues = sensorValue.valueStrings;

                if (sensorValue is SensorDoubleValue) {
                  renderedValues = sensorValue.values
                      .map((v) => v.toStringAsFixed(2).padLeft(7, ' '))
                      .toList();
                } else if (sensorValue is SensorIntValue) {
                  renderedValues = sensorValue.values
                      .map((v) => v.toString().padLeft(7, ' '))
                      .toList();
                }

              } else {
                renderedValues = List.generate(
                    sensor.axisCount, (_) => "#.##".padLeft(7, ' '));
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(sensor.axisCount, (index) {
                  return Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${sensor.axisNames[index]}:  ',
                          textAlign: TextAlign.left,
                        ),
                        Text(
                          '${renderedValues[index]} ${sensor.axisUnits[index]}',
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}
