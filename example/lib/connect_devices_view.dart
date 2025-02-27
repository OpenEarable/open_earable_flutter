import 'package:example/widgets/battery_info_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

import 'widgets/frequency_player_widget.dart';
import 'widgets/jingle_player_widget.dart';
import 'widgets/rgb_led_control_widget.dart';
import 'widgets/sensor_configuration_view.dart';
import 'widgets/audio_player_control_widget.dart';
import 'widgets/sensor_view.dart';
import 'widgets/storage_path_audio_player_widget.dart';
import 'widgets/grouped_box.dart';

class ConnectedDevicesView extends StatelessWidget {
  final List<Wearable> connectedDevices;

  const ConnectedDevicesView({
    Key? key,
    required this.connectedDevices,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (connectedDevices.isEmpty) {
      return const SizedBox.shrink();
    }

    return DefaultTabController(
      length: connectedDevices.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            isScrollable: true,
            tabs: connectedDevices
                .map((device) => Tab(text: device.name))
                .toList(),
          ),
          Builder(
            builder: (context) {
              final TabController tabController =
                  DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  return _buildDeviceTab(
                    connectedDevices[tabController.index],
                  );
                },
              );
            },
          ),
        ]
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: e,
              ),
            )
            .toList(),
      ),
    );
  }

  /// Builds the UI for a single connected device.
  Widget _buildDeviceTab(Wearable device) {
    List<SensorView>? sensorViews = SensorView.createSensorViews(device);
    List<SensorConfigurationView>? sensorConfigurationViews =
        SensorConfigurationView.createSensorConfigurationViews(device);
    String? wearableIconPath = device.getWearableIconPath();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupedBox(
          title: "Device Info",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wearableIconPath != null)
                SvgPicture.asset(
                  wearableIconPath,
                  width: 100,
                  height: 100,
                ),
              SelectableText("Name: ${device.name}"),
              if (device is DeviceIdentifier)
                FutureBuilder<String?>(
                  future: (device as DeviceIdentifier).readDeviceIdentifier(),
                  builder: (context, snapshot) {
                    return SelectableText(
                      "Device Identifier: ${snapshot.data}",
                    );
                  },
                ),
              if (device is DeviceFirmwareVersion)
                FutureBuilder<String?>(
                  future: (device as DeviceFirmwareVersion)
                      .readDeviceFirmwareVersion(),
                  builder: (context, snapshot) {
                    return SelectableText(
                      "Firmware Version: ${snapshot.data}",
                    );
                  },
                ),
              if (device is DeviceHardwareVersion)
                FutureBuilder<String?>(
                  future: (device as DeviceHardwareVersion)
                      .readDeviceHardwareVersion(),
                  builder: (context, snapshot) {
                    return SelectableText(
                      "Hardware Version: ${snapshot.data}",
                    );
                  },
                ),
            ],
          ),
        ),
        BatteryInfoWidget(connectedDevice: device),
        if (device is RgbLed && device is StatusLed)
          GroupedBox(
            title: "RGB LED",
            child: RgbLedControlWidget(
              rgbLed: device as RgbLed,
              statusLed: device as StatusLed,
            ),
          ),
        if (device is RgbLed && device is! StatusLed)
          GroupedBox(
            title: "RGB LED",
            child: RgbLedControlWidget(rgbLed: device as RgbLed),
          ),
        if (device is FrequencyPlayer)
          GroupedBox(
            title: "Frequency Player",
            child: FrequencyPlayerWidget(
              frequencyPlayer: device as FrequencyPlayer,
            ),
          ),
        if (device is JinglePlayer)
          GroupedBox(
            title: "Jingle Player",
            child: JinglePlayerWidget(
              jinglePlayer: device as JinglePlayer,
            ),
          ),
        if (device is StoragePathAudioPlayer)
          GroupedBox(
            title: "Storage Path Audio Player",
            child: StoragePathAudioPlayerWidget(
              audioPlayer: device as StoragePathAudioPlayer,
            ),
          ),
        if (device is AudioPlayerControls)
          GroupedBox(
            title: "Audio Player Controls",
            child: AudioPlayerControlWidget(
              audioPlayerControls: device as AudioPlayerControls,
            ),
          ),
        if (sensorConfigurationViews != null &&
            sensorConfigurationViews.isNotEmpty)
          GroupedBox(
            title: "Sensor Configurations",
            child: Column(
              children: sensorConfigurationViews,
            ),
          ),
        if (sensorViews != null && sensorViews.isNotEmpty)
          GroupedBox(
            title: "Sensors",
            child: Column(
              children: sensorViews
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(
                        top: 6.0,
                        bottom: 6.0,
                      ),
                      child: e,
                    ),
                  )
                  .toList(),
            ),
          ),
      ].map(
        (e) {
          return Padding(
            padding: const EdgeInsets.only(
              top: 8.0,
              bottom: 8.0,
            ),
            child: e,
          );
        },
      ).toList(),
    );
  }
}
