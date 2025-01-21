import 'package:example/fota/src/bloc/bloc/update_bloc.dart';
import 'package:example/fota/src/model/firmware_update_request.dart';
import 'package:example/fota/src/providers/firmware_update_request_provider.dart';
import 'package:example/fota/src/view/stepper_view/firmware_select.dart';
import 'package:example/fota/src/view/stepper_view/peripheral_select.dart';
import 'package:example/fota/src/view/stepper_view/update_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:provider/provider.dart';

class FirmwareUpdateWidget extends StatefulWidget {
  const FirmwareUpdateWidget({super.key});

  @override
  State<FirmwareUpdateWidget> createState() => _FirmwareUpdateWidget();
}

class _FirmwareUpdateWidget extends State<FirmwareUpdateWidget> {
  @override
  Widget build(BuildContext context) {
    return _body(context);
  }

  Widget _body(BuildContext context) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    return Stepper(
      currentStep: provider.currentStep,
      onStepContinue: () {
        setState(() {
          provider.nextStep();
        });
      },
      onStepCancel: () {
        setState(() {
          provider.previousStep();
        });
      },
      controlsBuilder: _controlBuilder,
      steps: [
        Step(
          title: Text('Select Firmware'),
          content: Center(child: FirmwareSelect()),
          isActive: provider.currentStep == 0,
        ),
        /*
        Step(
          title: Text('Select Device'),
          content: Center(child: PeripheralSelect()),
          isActive: provider.currentStep == 1,
        ),
        */
        Step(
          title: Text('Update'),
          content: Text('Update'),
          isActive: provider.currentStep == 1,
        ),
      ],
    );
  }

  Widget _controlBuilder(BuildContext context, ControlsDetails details) {
    final provider = context.watch<FirmwareUpdateRequestProvider>();
    FirmwareUpdateRequest parameters = provider.updateParameters;
    switch (provider.currentStep) {
      case 0:
        if (parameters.firmware == null) {
          return Container();
        }
        return Row(
          children: [
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
      /*
      case 1:
        if (parameters.peripheral == null) {
          return Container();
        }
        return Row(
          children: [
            TextButton(
              onPressed: details.onStepCancel,
              child: Text('Back'),
            ),
            ElevatedButton(
              onPressed: details.onStepContinue,
              child: Text('Next'),
            ),
          ],
        );
        */
      case 1:
        print("ID");
        print(parameters.peripheral!.identifier);
        return BlocProvider(
          create: (context) => UpdateBloc(firmwareUpdateRequest: parameters),
          child: UpdateStepView(),
        );
      default:
        throw Exception('Unknown step');
    }
  }
}
