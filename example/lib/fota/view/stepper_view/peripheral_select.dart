import 'package:flutter/material.dart';
import '../../model/firmware_update_request.dart';
import '../../providers/firmware_update_request_provider.dart';
import '../../view/peripheral_select/peripheral_list.dart';
import 'package:provider/provider.dart';

class PeripheralSelect2 extends StatelessWidget {
  const PeripheralSelect2({Key? key}) : super(key: key);

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
