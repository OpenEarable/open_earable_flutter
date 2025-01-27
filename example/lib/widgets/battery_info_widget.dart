import 'package:example/widgets/grouped_box.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class BatteryInfoWidget extends StatelessWidget {
  final Wearable connectedDevice;

  const BatteryInfoWidget({super.key, required this.connectedDevice});

  @override
  Widget build(BuildContext context) {
    return GroupedBox(
      title: "Battery Info",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (connectedDevice is BatteryLevelService)
            StreamBuilder(
              stream: (connectedDevice as BatteryLevelService).batteryPercentageStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(
                    "Battery Percentage:\t${snapshot.data}%",
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          if (connectedDevice is BatteryLevelStatusService)
          StreamBuilder(
            stream: (connectedDevice as BatteryLevelStatusService).powerStatusStream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Battery connected: ${snapshot.data!.batteryPresent ? "✅" : "❌"}",
                    ),
                    Text(
                      "Wired Power Connected: ${snapshot.data!.wiredExternalPowerSourceConnected}",
                    ),
                    Text(
                      "Wireless Power Connected: ${snapshot.data!.wirelessExternalPowerSourceConnected}",
                    ),
                    Text(
                      "Charge State: ${snapshot.data!.chargeState}",
                    ),
                    Text(
                      "Charge Level: ${snapshot.data!.chargeLevel}",
                    ),
                    Text(
                      "Charging Type: ${snapshot.data!.chargingType}",
                    ),
                    Text(
                      "Charging Fault Reason: ${snapshot.data!.chargingFaultReason}",
                    ),
                  ],
                );
              } else {
                return const CircularProgressIndicator();
              }
            },
          ),
          const Divider(),
          if (connectedDevice is BatteryHealthStatusService)
            StreamBuilder(
              stream: (connectedDevice as BatteryHealthStatusService).healthStatusStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Health Summary: ${snapshot.data!.healthSummary}%",
                      ),
                      Text(
                        "Cycle Count: ${snapshot.data!.cycleCount}",
                      ),
                      Text(
                        "Current Temperature: ${snapshot.data!.currentTemperature}°C",
                      ),
                    ],
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          const Divider(),
          if (connectedDevice is BatteryEnergyStatusService)
            StreamBuilder(
              stream: (connectedDevice as BatteryEnergyStatusService).energyStatusStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Voltage: ${snapshot.data!.voltage}V",
                      ),
                      Text(
                        "Available Capacity: ${snapshot.data!.availableCapacity}Wh",
                      ),
                      Text(
                        "Charge Rate: ${snapshot.data!.chargeRate}W",
                      ),
                    ],
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
        ],
      ),
    );
  }
}