import 'package:flutter/material.dart';
import '../../../src/model/firmware_update_request.dart';
import '../../../src/providers/firmware_update_request_provider.dart';
import '../../../src/view/peripheral_select/peripheral_list.dart';
import 'package:provider/provider.dart';

class PeripheralSelect extends StatelessWidget {
  const PeripheralSelect({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    FirmwareUpdateRequest updateParameters =
        context.watch<FirmwareUpdateRequestProvider>().updateParameters;

    return Column(
      children: [
        if (updateParameters.peripheral != null)
          Text(updateParameters.peripheral!.name),
        ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PeripheralList()),
              );
            },
            child: Text('Select Peripheral')),
      ],
    );
  }
}
