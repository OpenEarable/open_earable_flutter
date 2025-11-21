import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class SensorConfigurationView extends StatefulWidget {
  final SensorConfiguration configuration;

  const SensorConfigurationView({super.key, required this.configuration});

  static List<SensorConfigurationView>? createSensorConfigurationViews(
      Wearable wearable) {
    if (wearable is SensorConfigurationManager) {
      final sensorManager = wearable as SensorConfigurationManager;
      return sensorManager.sensorConfigurations
          .map(
            (configuration) => SensorConfigurationView(
              configuration: configuration,
            ),
          )
          .toList();
    } else {
      return null;
    }
  }

  @override
  State<SensorConfigurationView> createState() =>
      _SensorConfigurationViewState();
}

class _SensorConfigurationViewState extends State<SensorConfigurationView> {
  SensorConfigurationValue? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.configuration.values.first;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.configuration.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              DropdownButton<SensorConfigurationValue>(
                value: _selectedValue,
                items: widget.configuration.values.map((value) {
                  return DropdownMenuItem<SensorConfigurationValue>(
                    value: value,
                    child: Text(value.toString()),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedValue = newValue;
                  });
                },
              ),
              if (widget.configuration.unit != null)
                Text(' ${widget.configuration.unit!}'),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  if (_selectedValue != null) {
                    widget.configuration.setConfiguration(_selectedValue!);
                  }
                },
                child: const Text('Set'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
