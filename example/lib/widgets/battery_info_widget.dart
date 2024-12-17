import 'package:example/widgets/grouped_box.dart';
import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';

class BatteryInfoWidget extends StatelessWidget {
  final ExtendedBatteryService connectedDevice;

  const BatteryInfoWidget({super.key, required this.connectedDevice});

  @override
  Widget build(BuildContext context) {
    return GroupedBox(
      title: "Battery Info",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder(
            stream: connectedDevice.batteryPercentageStream,
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
          StreamBuilder(
            stream: connectedDevice.powerStatusStream,
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
          StreamBuilder(
            stream: connectedDevice.healthStatusStream,
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
          StreamBuilder(
            stream: connectedDevice.energyStatusStream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Voltage: ${snapshot.data!.voltage}V",
                    ),
                    Text(
                      "Available Capacity: ${snapshot.data!.availableCapacity}mAh",
                    ),
                    Text(
                      "Charge Rate: ${snapshot.data!.chargeRate}mAh",
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